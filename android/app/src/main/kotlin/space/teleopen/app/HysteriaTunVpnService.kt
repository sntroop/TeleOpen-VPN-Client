package space.teleopen.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.ServiceCompat
import io.flutter.plugin.common.EventChannel
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileDescriptor

class HysteriaTunVpnService : VpnService() {

    companion object {
        const val TAG = "TeleOpenVpn"

        const val ACTION_START_HYSTERIA = "space.teleopen.app.START_HYSTERIA"
        const val ACTION_START_V2RAY    = "space.teleopen.app.START_V2RAY"
        const val ACTION_STOP           = "space.teleopen.app.STOP_VPN"

        const val EXTRA_CONFIG      = "config"
        const val EXTRA_REMARK      = "remark"
        const val EXTRA_SOCKS5_PORT = "socks5_port"
        const val EXTRA_PERAPP_ENABLED  = "perapp_enabled"
        const val EXTRA_ALLOWED_PACKAGES = "allowed_packages"
        const val EXTRA_KILL_SWITCH      = "kill_switch"

        const val NOTIF_CHANNEL = "vpn_tun_channel"
        const val NOTIF_ID      = 7777

        @Volatile var eventSink: EventChannel.EventSink? = null

        fun pushStatus(status: String) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(status)
            }
        }

        /**
         * Отправить кадр статистики через EventChannel в виде JSON-строки.
         * Dart-сторона различает события: строки начинающиеся с `{` — это
         * статистика, остальное — статус.
         */
        fun pushStats(rxBytes: Long, txBytes: Long, rxRate: Long, txRate: Long, uptimeMs: Long) {
            val obj = JSONObject()
                .put("type", "stats")
                .put("rx", rxBytes)
                .put("tx", txBytes)
                .put("rxRate", rxRate)
                .put("txRate", txRate)
                .put("uptimeMs", uptimeMs)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(obj.toString())
            }
        }

        /**
         * Сигнал «конфиг изменился, перечитай при ближайшей возможности».
         * Сейчас просто пишет в лог — реальное применение настроек
         * (DNS-перехват, sniffing, fake-IP) делает onStartCommand при
         * следующем старте VPN, читая filesDir/core_config.json.
         *
         * Если хочешь горячее применение — добавь сюда вызов своих
         * приватных методов вроде reapplyDnsFromConfig() / reapplySniffing()
         * которые правят tun2socks/xray на лету.
         */
        fun notifyConfigChanged() {
            flog("config", "core_config.json changed — will be picked up on next start")
        }

        /**
         * Загрузить core_config.json (если есть) — это карта настроек,
         * которую UI пишет через MethodChannel "applyCoreConfig".
         * При ошибке/отсутствии файла возвращает пустой JSONObject.
         */
        fun loadCoreConfig(ctx: android.content.Context): JSONObject {
            return try {
                val f = File(ctx.filesDir, "core_config.json")
                if (f.exists()) JSONObject(f.readText()) else JSONObject()
            } catch (e: Throwable) {
                flogE("config", "loadCoreConfig failed: ${e.message}", e)
                JSONObject()
            }
        }

        /**
         * Извлечь IP из строки DNS-сервера: tcp://1.2.3.4, https://1.2.3.4/...,
         * udp://1.2.3.4:53, или просто "1.2.3.4". Если не удалось — null.
         */
        fun extractDnsIp(raw: String): String? {
            if (raw.isEmpty()) return null
            // убрать схему
            val noScheme = raw.replace(Regex("""^[a-z]+://"""), "")
            // убрать путь и порт
            val host = noScheme.substringBefore("/").substringBefore(":")
            return if (host.matches(Regex("""^\d{1,3}(\.\d{1,3}){3}$"""))) host else null
        }

        // Файловое логирование — лог пишется в filesDir/vpn_debug.log
        // Путь видно в логах при старте; забрать его потом через приложение.
        @Volatile private var logFile: File? = null
        private val logLock = Any()

        fun initFileLog(ctx: android.content.Context) {
            try {
                val f = File(ctx.filesDir, "vpn_debug.log")
                // Ротация: если файл > 1MB — пересоздаём
                if (f.exists() && f.length() > 1_000_000) f.delete()
                logFile = f
            } catch (_: Throwable) {}
        }

        fun flog(tag: String, msg: String) {
            android.util.Log.i(tag, msg)
            synchronized(logLock) {
                try {
                    val f = logFile ?: return
                    val ts = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US)
                        .format(java.util.Date())
                    f.appendText("$ts [$tag] $msg\n")
                } catch (_: Throwable) {}
            }
        }

        fun flogE(tag: String, msg: String, t: Throwable? = null) {
            android.util.Log.e(tag, msg, t)
            synchronized(logLock) {
                try {
                    val f = logFile ?: return
                    val ts = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US)
                        .format(java.util.Date())
                    f.appendText("$ts [$tag] ERROR: $msg\n")
                    if (t != null) {
                        val sw = java.io.StringWriter()
                        t.printStackTrace(java.io.PrintWriter(sw))
                        f.appendText(sw.toString() + "\n")
                    }
                } catch (_: Throwable) {}
            }
        }
    }

    // Hysteria: pfd удерживаем сами; tun2socks читает с fd через unix socket
    private var tunInterface: ParcelFileDescriptor? = null
    // V2Ray: fd «отвязываем» (detachFd) и отдаём xray. Он сам управляет жизнью fd.
    private var v2rayDetachedFd: Int = -1

    private var tun2socksProcess: Process? = null
    private var coreController: CoreController? = null
    private var isRunning = false
    // Защита от повторного входа: пока идёт start*, второй вызов onStartCommand
    // (в т.ч. Android-retry с flags=START_FLAG_RETRY) не должен запускать
    // второй core поверх первого — иначе нативный краш 'bind: address in use'.
    @Volatile private var starting = false
    // Время последнего принятого старта (мс). Быстрые повторные нажатия
    // «Подключить» в течение debounce-окна отбрасываются: каждый старт
    // делает stopInternals()+новый core, и наложение нескольких циклов
    // приводило к драке за TUN fd и нативному краху.
    @Volatile private var lastStartAcceptedAt = 0L
    private val startDebounceMs = 1500L
    // Глобальный замок: пока идёт start ИЛИ stop, другие команды ждут/отбиваются.
    private val lifecycleLock = Any()
    private var mode: String = ""  // "hysteria" | "v2ray" | ""

    // Per-app proxy для текущей сессии
    private var perAppEnabled: Boolean = false
    private var allowedPackages: List<String> = emptyList()

    // Kill-switch: если включён и core упал не по команде пользователя, НЕ рвём
    // туннель — держим TUN открытым без рабочего ядра, чтобы трафик не утекал
    // мимо VPN (fail-closed). intentionalStop отличает штатный stopVpn от краха.
    @Volatile private var killSwitchEnabled: Boolean = false
    @Volatile private var intentionalStop: Boolean = false

    // Статистика трафика
    private var statsThread: Thread? = null
    @Volatile private var statsRunning: Boolean = false
    private var statsBaselineRx: Long = -1L
    private var statsBaselineTx: Long = -1L
    private var statsLastRx: Long = 0L
    private var statsLastTx: Long = 0L
    private var statsLastTickMs: Long = 0L

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        initFileLog(this)
        flog(TAG, "=== onStartCommand action=${intent?.action} flags=$flags startId=$startId ===")
        flog(TAG, "log file: ${File(filesDir, "vpn_debug.log").absolutePath}")

        // ── null-intent / неизвестный action ───────────────────────────────────
        // Sticky-рестарт после убийства процесса приходит с intent=null.
        // Конфиг неизвестен — поднять туннель нельзя. Выполняем контракт FGS
        // (startForeground) и тихо останавливаемся.
        if (intent?.action == null ||
            (intent.action != ACTION_STOP &&
             intent.action != ACTION_START_V2RAY &&
             intent.action != ACTION_START_HYSTERIA)) {
            flog(TAG, "no usable action — satisfying FGS contract then stopping")
            try { startVpnForeground("TeleOpen") } catch (t: Throwable) {
                flogE(TAG, "fallback startForeground failed: ${t.message}", t)
            }
            stopVpn()
            return START_NOT_STICKY
        }

        if (intent.action == ACTION_STOP) {
            // Stop тоже под lifecycleLock и в фоне — иначе при нажатии Stop
            // во время идущего старта главный поток встал бы в ожидании замка (ANR).
            // Пользователь сам остановил → это штатный стоп, kill-switch НЕ держит туннель.
            intentionalStop = true
            starting = false
            Thread({
                synchronized(lifecycleLock) { stopVpn() }
            }, "vpn-stop").apply { isDaemon = true; start() }
            return START_NOT_STICKY
        }

        // ── Защита от повторного входа + debounce ──────────────────────────────
        // 1) Если старт уже идёт — игнорируем дубликат.
        // 2) Если предыдущий старт был принят менее startDebounceMs назад —
        //    тоже игнорируем. Это гасит «нажал Подключить 5 раз подряд»:
        //    раньше каждое нажатие делало stopInternals()+новый core, циклы
        //    накладывались, несколько xray дрались за один TUN fd → краш.
        val now = android.os.SystemClock.elapsedRealtime()
        if (starting) {
            flog(TAG, "start already in progress — ignoring duplicate onStartCommand")
            return START_NOT_STICKY
        }
        if (now - lastStartAcceptedAt < startDebounceMs) {
            flog(TAG, "start debounced (${now - lastStartAcceptedAt}ms since last) — ignoring")
            return START_NOT_STICKY
        }
        starting = true
        lastStartAcceptedAt = now

        perAppEnabled = intent.getBooleanExtra(EXTRA_PERAPP_ENABLED, false)
        allowedPackages = intent.getStringArrayListExtra(EXTRA_ALLOWED_PACKAGES) ?: emptyList()
        killSwitchEnabled = intent.getBooleanExtra(EXTRA_KILL_SWITCH, false)
        intentionalStop = false // новый старт → следующий обрыв считается внезапным
        flog(TAG, "perApp enabled=$perAppEnabled pkgs=${allowedPackages.size} killSwitch=$killSwitchEnabled")

        // FGS-контракт: startForeground ДО ухода в фоновый поток, синхронно,
        // чтобы Android точно увидел foreground в течение 5 секунд.
        val remark = intent.getStringExtra(EXTRA_REMARK) ?: "TeleOpen"
        try {
            startVpnForeground(remark)
        } catch (t: Throwable) {
            flogE(TAG, "startForeground failed: ${t.message}", t)
            starting = false
            pushStatus("STOPPED"); stopSelf()
            return START_NOT_STICKY
        }
        pushStatus("CONNECTING")

        // ── Тяжёлый старт core — В ОТДЕЛЬНОМ ПОТОКЕ ─────────────────────────────
        // Раньше startV2Ray/startHysteria выполнялись прямо в onStartCommand,
        // т.е. на главном потоке сервиса. ctrl.startLoop() может блокироваться
        // (мёртвая сеть, Doze) — Android считал сервис зависшим и делал retry,
        // накладывая второй core на первый → краш. Уносим в фон.
        val action = intent.action!!
        val config = intent.getStringExtra(EXTRA_CONFIG) ?: ""
        val port   = intent.getIntExtra(EXTRA_SOCKS5_PORT, 10900)
        Thread({
            try {
                // Сериализуем весь жизненный цикл: пока идёт start, stop ждёт,
                // и наоборот. Исключает одновременную работу двух core с одним TUN.
                synchronized(lifecycleLock) {
                    when (action) {
                        ACTION_START_V2RAY    -> startV2Ray(config, remark)
                        ACTION_START_HYSTERIA -> startHysteria(port, remark)
                    }
                }
            } catch (t: Throwable) {
                flogE(TAG, "start thread fatal: ${t.javaClass.simpleName}: ${t.message}", t)
                pushStatus("STOPPED")
                try { stopSelf() } catch (_: Throwable) {}
            } finally {
                starting = false
            }
        }, "vpn-start").apply { isDaemon = true; start() }

        return START_NOT_STICKY
    }

    override fun onDestroy() { stopVpn(); super.onDestroy() }
    override fun onRevoke()  { stopVpn() }

    // ── Hysteria2 mode (tun2socks → внешний hysteria SOCKS) ───────────────────

    private fun startHysteria(socks5Port: Int, remark: String) {
        Log.i(TAG, "startHysteria port=$socks5Port")
        stopInternals()
        // Пауза, чтобы прошлый tun2socks/TUN освободили ресурсы.
        // Увеличена до 1000ms для надежности (особенно после kill-switch).
        try { Thread.sleep(1000) } catch (_: InterruptedException) {}
        mode = "hysteria"

        // foreground уже поднят в onStartCommand; здесь только строим TUN.
        val tun: ParcelFileDescriptor
        try {
            tun = buildTunInterface(remark) ?: run {
                Log.e(TAG, "startHysteria: buildTunInterface returned null")
                pushStatus("STOPPED"); stopSelf(); return
            }
        } catch (t: Throwable) {
            flogE(TAG, "startHysteria pre-start fatal: ${t.javaClass.simpleName}: ${t.message}", t)
            pushStatus("STOPPED"); stopSelf(); return
        }
        tunInterface = tun
        isRunning = true

        try {
            startTun2Socks(tun.fileDescriptor, socks5Port, "sock_path_hysteria")
            pushStatus("CONNECTED"); startStatsReporter()
            Log.i(TAG, "Hysteria VPN started")
        } catch (e: Exception) {
            Log.e(TAG, "startHysteria error: $e")
            pushStatus("STOPPED"); stopSelf()
        }
    }

    // ── V2Ray mode (встроенный TUN внутри xray-core) ──────────────────────────

    private fun startV2Ray(rawConfig: String, remark: String) {
        flog(TAG, "startV2Ray BEGIN remark=$remark configLen=${rawConfig.length}")
        stopInternals()
        // Даём предыдущему core/TUN полностью освободить ресурсы (stopLoop
        // асинхронен). Без паузы повторный коннект мог наложиться на ещё
        // живой core. Увеличена до 1000ms для надежности (особенно после kill-switch).
        try { Thread.sleep(1000) } catch (_: InterruptedException) {}
        mode = "v2ray"

        if (rawConfig.isBlank()) {
            flogE(TAG, "empty config")
            pushStatus("STOPPED"); stopSelf(); return
        }

        var pfd: ParcelFileDescriptor? = null
        try {
            // 1) Готовим конфиг с TUN-inbound
            val config = ensureTunInbound(rawConfig)
            flog(TAG, "config after ensureTunInbound, len=${config.length}")
            // Печатаем конфиг по кусочкам — в logcat он бы порезался, в файл влезет
            flog(TAG, "=== CONFIG START ===")
            config.chunked(500).forEach { flog(TAG, it) }
            flog(TAG, "=== CONFIG END ===")

            // 2) Поднимаем TUN
            pfd = buildTunInterface(remark) ?: run {
                flogE(TAG, "buildTunInterface returned null (no VPN permission?)")
                pushStatus("STOPPED"); stopSelf(); return
            }
            flog(TAG, "VpnService.Builder.establish() OK, pfd=$pfd")

            val fd = pfd.detachFd()
            pfd = null
            v2rayDetachedFd = fd
            flog(TAG, "TUN detachedFd=$fd")

            // 3) initCoreEnv
            try {
                val assetsDir = filesDir.absolutePath
                // ВАЖНО: второй аргумент initCoreEnv — это xudp BaseKey
                // (env xray.xudp.basekey), а НЕ ещё один путь. xray-core
                // v26.5.9+ строго валидирует его: ждёт base64 ровно на 32
                // байта. Раньше сюда ошибочно передавался assetsDir — путь
                // декодировался в 0 байт, и Go-ядро паниковало (SIGABRT) →
                // приложение крашилось при коннекте. Пустая строка = xray
                // использует дефолт; для vless/vision/tcp без mux xudp не
                // задействован, так что это безопасно.
                flog(TAG, "calling initCoreEnv(env=$assetsDir, xudpKey=<empty>)")
                Libv2ray.initCoreEnv(assetsDir, "")
                flog(TAG, "initCoreEnv OK")
            } catch (t: Throwable) {
                flogE(TAG, "initCoreEnv threw: ${t.javaClass.simpleName}", t)
            }

            // Проверим версию ядра — заодно убедимся что библиотека грузится
            try {
                val v = Libv2ray.checkVersionX()
                flog(TAG, "xray version: $v")
            } catch (t: Throwable) {
                flogE(TAG, "checkVersionX threw", t)
            }

            // 4) Контроллер
            val ctrl = Libv2ray.newCoreController(object : CoreCallbackHandler {
                override fun startup(): Long {
                    flog(TAG, "callback.startup()")
                    return 0L
                }

                override fun shutdown(): Long {
                    flog(TAG, "callback.shutdown() — xray просит выключения")
                    if (isRunning) {
                        // Ядро упало не по нашей команде → kill-switch решает,
                        // рвать туннель или держать blackhole (fail-closed).
                        handleUnexpectedDeath("xray.shutdown")
                    }
                    return 0L
                }

                override fun onEmitStatus(l: Long, s: String?): Long {
                    flog(TAG, "callback.onEmitStatus(code=$l, msg=$s)")
                    return 0L
                }
            })
            coreController = ctrl
            flog(TAG, "newCoreController OK")

            // 5) startLoop
            flog(TAG, "calling ctrl.startLoop(config, fd=$fd)")
            ctrl.startLoop(config, fd)
            flog(TAG, "ctrl.startLoop returned, isRunning=${ctrl.isRunning}")

            if (!ctrl.isRunning) {
                flogE(TAG, "ctrl.isRunning=false after startLoop — xray не стартанул")
                closeDetachedFd()
                pushStatus("STOPPED"); stopSelf(); return
            }

            isRunning = true
            pushStatus("CONNECTED"); startStatsReporter()
            flog(TAG, "V2Ray VPN started OK")

        } catch (e: Throwable) {
            flogE(TAG, "startV2Ray fatal: ${e.javaClass.simpleName}: ${e.message}", e)
            closeDetachedFd()
            try { pfd?.close() } catch (_: Throwable) {}
            pushStatus("STOPPED"); stopSelf()
        }
    }

    private fun closeDetachedFd() {
        if (v2rayDetachedFd >= 0) {
            try {
                // adoptFd создаёт ParcelFileDescriptor-владельца для уже открытого fd и корректно его закрывает
                ParcelFileDescriptor.adoptFd(v2rayDetachedFd).close()
            } catch (e: Throwable) {
                Log.w(TAG, "closeDetachedFd: $e")
            }
            v2rayDetachedFd = -1
        }
    }

    /**
     * Гарантирует наличие inbound с protocol="tun" в xray-конфиге.
     * xray-core активирует TUN-обработчик ТОЛЬКО при наличии такого inbound.
     * Существующие inbounds (socks/http) оставляем — они не мешают (для in-app proxy/тестов).
     *
     * Также мерджит sniffing-настройки и DNS-блок из core_config.json
     * (см. NativeExtensions.applyCoreConfig).
     */
    private fun ensureTunInbound(raw: String): String {
        return try {
            val root = JSONObject(raw)
            val cfg = loadCoreConfig(this)

            // ── Sniffing: формируем общий блок из настроек ─────────────
            val destOverride = JSONArray()
            val httpOver = cfg.optString("meta_sniff_http_override", "")
            val tlsOver  = cfg.optString("meta_sniff_tls_override", "")
            val quicOver = cfg.optString("meta_sniff_quic_override", "")
            // Если пользователь явно выключил — не добавляем; иначе добавляем
            // (умолчание = «как было», т.е. http + tls).
            if (httpOver != "Выключить") destOverride.put("http")
            if (tlsOver  != "Выключить") destOverride.put("tls")
            if (quicOver == "Включить")  destOverride.put("quic")
            if (cfg.optBoolean("packet_analysis", true) && destOverride.length() == 0) {
                destOverride.put("http").put("tls")
            }

            val sniffingObj = JSONObject()
                .put("enabled", destOverride.length() > 0)
                .put("destOverride", destOverride)
            // Исключения доменов (sniffing.domainsExcluded)
            val skip = cfg.optString("meta_skip_domain", "")
            if (skip.isNotEmpty() && skip != "Не менять") {
                val arr = JSONArray()
                for (d in skip.split(",", ";", " ").map { it.trim() }.filter { it.isNotEmpty() }) {
                    arr.put(d)
                }
                if (arr.length() > 0) sniffingObj.put("domainsExcluded", arr)
            }
            val parsePure = cfg.optString("meta_parse_pure_ip", "")
            if (parsePure == "Включить") sniffingObj.put("routeOnly", false)

            // ── TUN inbound ─────────────────────────────────────────────
            val inbounds = root.optJSONArray("inbounds") ?: JSONArray().also { root.put("inbounds", it) }
            var hasTun = false
            for (i in 0 until inbounds.length()) {
                val inb = inbounds.optJSONObject(i) ?: continue
                if (inb.optString("protocol").equals("tun", ignoreCase = true)) {
                    hasTun = true
                    // обновим sniffing у существующего TUN-inbound
                    inb.put("sniffing", sniffingObj)
                    break
                }
                // и в обычных inbound тоже подкинем sniffing, если он не был задан
                if (!inb.has("sniffing") && sniffingObj.optBoolean("enabled")) {
                    inb.put("sniffing", sniffingObj)
                }
            }
            if (!hasTun) {
                val tunInb = JSONObject()
                    .put("port", 0)
                    .put("protocol", "tun")
                    .put("tag", "tun-in")
                    .put("settings", JSONObject()
                        .put("name", "tun0")
                        .put("MTU", 1500))
                    .put("sniffing", sniffingObj)
                inbounds.put(tunInb)
                Log.i(TAG, "tun inbound injected into config")
            }

            // ── DNS-блок ────────────────────────────────────────────────
            val dnsRemote = cfg.optString("dns_remote", "")
            val dnsDirect = cfg.optString("dns_direct", "")
            if (dnsRemote.isNotEmpty() || dnsDirect.isNotEmpty()) {
                val dns = root.optJSONObject("dns") ?: JSONObject()
                val servers = JSONArray()
                if (dnsRemote.isNotEmpty()) servers.put(dnsRemote)
                if (dnsDirect.isNotEmpty()) servers.put(dnsDirect)
                dns.put("servers", servers)
                // FakeIP (если включён)
                if (cfg.optBoolean("dns_fake", false)) {
                    dns.put("queryStrategy", "UseIP")
                }
                root.put("dns", dns)
                flog(TAG, "DNS block merged: remote=$dnsRemote direct=$dnsDirect")
            }

            // ── Log level из External Controller ───────────────────────
            val logLevel = cfg.optString("ec_log_level", "")
            if (logLevel.isNotEmpty() && logLevel != "Не менять") {
                val logObj = root.optJSONObject("log") ?: JSONObject()
                logObj.put("loglevel", logLevel)
                root.put("log", logObj)
            }

            root.toString()
        } catch (e: Exception) {
            Log.e(TAG, "ensureTunInbound failed, using raw config: $e")
            raw
        }
    }

    // ── tun2socks (только для Hysteria) ───────────────────────────────────────

    private fun startTun2Socks(tunFd: FileDescriptor, socks5Port: Int, sockFileName: String) {
        val tun2socksPath = File(applicationInfo.nativeLibraryDir, "libtun2socks.so").absolutePath
        val sockFile = File(filesDir, sockFileName)
        try { if (sockFile.exists()) sockFile.delete() } catch (_: Exception) {}
        val sockPath = sockFile.absolutePath

        val cmd = listOf(
            tun2socksPath,
            "--netif-ipaddr",      "10.8.0.2",
            "--netif-netmask",     "255.255.255.0",
            "--socks-server-addr", "127.0.0.1:$socks5Port",
            "--tunmtu",            "1500",
            "--sock-path",         sockPath,
            "--enable-udprelay",
            "--loglevel",          "error"
        )
        tun2socksProcess = ProcessBuilder(cmd)
            .redirectErrorStream(true)
            .directory(filesDir)
            .start()

        Thread({
            try {
                tun2socksProcess?.inputStream?.bufferedReader()?.forEachLine {
                    Log.d(TAG, "tun2socks: $it")
                }
            } catch (_: Exception) {}
            // forEachLine вернулся → процесс tun2socks завершился. Если мы при этом
            // ещё «работаем», значит он умер не по нашей команде → kill-switch.
            if (isRunning && mode == "hysteria") {
                handleUnexpectedDeath("tun2socks.exit")
            }
        }, "tun2socks_log").start()

        sendFdToSock(tunFd, sockPath)
    }

    private fun sendFdToSock(tunFd: FileDescriptor, sockPath: String) {
        Thread({
            var tries = 0
            while (tries < 10) {
                try {
                    Thread.sleep(100L * (tries + 1))
                    val sock = android.net.LocalSocket()
                    sock.connect(android.net.LocalSocketAddress(
                        sockPath, android.net.LocalSocketAddress.Namespace.FILESYSTEM))
                    sock.setFileDescriptorsForSend(arrayOf(tunFd))
                    sock.outputStream.write(32)
                    sock.setFileDescriptorsForSend(null)
                    sock.shutdownOutput()
                    sock.close()
                    Log.i(TAG, "TUN fd sent OK")
                    return@Thread
                } catch (e: Exception) {
                    Log.w(TAG, "sendFd try $tries: $e")
                    tries++
                }
            }
            Log.e(TAG, "sendFd: failed after $tries tries")
        }, "sendFd").start()
    }

    // ── Stop ──────────────────────────────────────────────────────────────────

    private fun stopVpn() {
        Log.i(TAG, "stopVpn")
        starting = false
        stopStatsReporter()
        stopInternals()
        pushStatus("STOPPED")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * Внезапная смерть ядра (не по команде пользователя). Если kill-switch
     * выключен — ведём себя как раньше (рвём туннель, STOPPED). Если включён —
     * закрываем всё корректно, но шлём DROPPED вместо STOPPED, чтобы Dart
     * показал ошибку и при autoFailover переподключился. Трафик блокируется
     * тем, что VPN-туннель закрыт, но failover быстро переподключится.
     */
    private fun handleUnexpectedDeath(where: String) {
        if (intentionalStop) {
            // На самом деле это был штатный стоп, просто колбэк прилетел следом.
            flog(TAG, "core down at $where but intentionalStop=true — normal stop")
            return
        }
        if (!killSwitchEnabled) {
            flog(TAG, "core down at $where, killSwitch OFF — tearing down")
            stopVpn()
            return
        }
        // Kill-switch ON: закрываем всё корректно, чтобы следующий коннект не крашился.
        // Трафик блокируется короткое время до автоматического переподключения.
        flog(TAG, "core down at $where, killSwitch ON — closing cleanly for reconnect")
        isRunning = false
        stopStatsReporter()
        try { coreController?.stopLoop() } catch (e: Exception) { Log.w(TAG, "stopLoop: $e") }
        coreController = null
        try { tun2socksProcess?.destroy() } catch (_: Exception) {}
        tun2socksProcess = null
        // Закрываем TUN корректно, чтобы следующий establish() не конфликтовал
        closeDetachedFd()
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null
        try { updateNotification("Переподключение...") } catch (_: Throwable) {}
        pushStatus("DROPPED")
    }

    private fun stopInternals() {
        isRunning = false

        // 1) Останавливаем прокси-движок (он перестанет читать с TUN fd)
        try { coreController?.stopLoop() } catch (e: Exception) { Log.w(TAG, "stopLoop: $e") }
        coreController = null

        // 2) Глушим tun2socks (если был)
        try { tun2socksProcess?.destroy() } catch (_: Exception) {}
        tun2socksProcess = null

        // 3) Закрываем TUN
        closeDetachedFd()
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null

        mode = ""
    }

    // ── TUN Builder ───────────────────────────────────────────────────────────

    private fun buildTunInterface(remark: String): ParcelFileDescriptor? {
        return try {
            val cfg = loadCoreConfig(this)
            val stopPi = PendingIntent.getService(
                this, 0,
                Intent(this, HysteriaTunVpnService::class.java).apply { action = ACTION_STOP },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = Builder()
                .setMtu(1500)
                .addAddress("10.8.0.1", 24)
                .setSession(remark)
                // xray (gVisor) ожидает blocking fd; tun2socks умеет non-blocking
                .setBlocking(mode == "v2ray")
                .setConfigureIntent(stopPi)

            // ── Per-app proxy ───────────────────────────────────────────
            // Allowed-режим: только указанные приложения идут через VPN.
            // В allowed-режиме нельзя одновременно использовать disallowed,
            // включая «себя» — поэтому сам пакет добавляем в allowed списком
            // (на самом деле приложение и так не ходит через свой VPN, но
            // безопаснее явно исключить — см. ниже).
            if (perAppEnabled && allowedPackages.isNotEmpty()) {
                var added = 0
                for (pkg in allowedPackages) {
                    if (pkg == packageName) continue  // себя не добавляем
                    try {
                        builder.addAllowedApplication(pkg)
                        added++
                    } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                        flog(TAG, "perApp: package not found, skip: $pkg")
                    }
                }
                flog(TAG, "perApp: allowed apps added=$added (of ${allowedPackages.size})")
            } else {
                // Стандартный режим: весь трафик через VPN, кроме своего пакета
                // (иначе loops при обращении приложения к серверу через VPN).
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                    flog(TAG, "self disallow failed: ${e.message}")
                }
            }

            // ── DNS из настроек ─────────────────────────────────────────
            // Берём dns_remote (приоритет) → dns_direct → дефолты.
            val dnsCandidates = listOf(
                cfg.optString("dns_remote", ""),
                cfg.optString("dns_direct", "")
            )
            var dnsAdded = 0
            for (raw in dnsCandidates) {
                val ip = extractDnsIp(raw) ?: continue
                builder.addDnsServer(ip)
                flog(TAG, "TUN DNS: $ip (from '$raw')")
                dnsAdded++
            }
            if (dnsAdded == 0) {
                builder.addDnsServer("1.1.1.1").addDnsServer("8.8.8.8")
                flog(TAG, "TUN DNS: default 1.1.1.1 + 8.8.8.8")
            }

            // ── IPv6 ────────────────────────────────────────────────────
            val allowIpv6 = cfg.optBoolean("net_allow_ipv6", false)
            if (allowIpv6) {
                try {
                    builder.addAddress("fd00:1:fd00:1:fd00:1:fd00:1", 64)
                    builder.addRoute("::", 0)
                    flog(TAG, "TUN: IPv6 enabled")
                } catch (t: Throwable) {
                    flog(TAG, "TUN: IPv6 setup failed: ${t.message}")
                }
            }

            // ── Маршрутизация: системный трафик или нет ─────────────────
            val routeSystem = cfg.optBoolean("net_route_system", true)
            val bypassPrivate = cfg.optBoolean("net_bypass_private", false)

            if (routeSystem) {
                if (bypassPrivate && android.os.Build.VERSION.SDK_INT >= 33) {
                    builder.addRoute("0.0.0.0", 0)
                    try {
                        // API 33+: VpnService.Builder.excludeRoute(IpPrefix)
                        builder.excludeRoute(android.net.IpPrefix(
                            java.net.InetAddress.getByName("10.0.0.0"), 8))
                        builder.excludeRoute(android.net.IpPrefix(
                            java.net.InetAddress.getByName("172.16.0.0"), 12))
                        builder.excludeRoute(android.net.IpPrefix(
                            java.net.InetAddress.getByName("192.168.0.0"), 16))
                        flog(TAG, "TUN: bypass private networks (excludeRoute)")
                    } catch (t: Throwable) {
                        flog(TAG, "TUN: excludeRoute failed: ${t.message}")
                    }
                } else {
                    builder.addRoute("0.0.0.0", 0)
                }
            } else {
                flog(TAG, "TUN: route_system=false — only allowed apps go through VPN")
            }

            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "buildTun error: $e"); null
        }
    }

    // ── Traffic stats ─────────────────────────────────────────────────────────

    /**
     * Запускает фоновый поток, который раз в секунду снимает счётчики
     * Android TrafficStats и шлёт кадр статистики в UI через EventChannel.
     *
     * Считаем по своему UID (Process.myUid()) — это весь трафик процесса,
     * включающий и TUN-туннель, и обычные HTTP-запросы приложения.
     * Для VPN-приложения почти весь трафик — туннельный, поэтому
     * погрешность копеечная.
     */
    private fun startStatsReporter() {
        stopStatsReporter()
        val uid = android.os.Process.myUid()
        statsBaselineRx = android.net.TrafficStats.getUidRxBytes(uid)
        statsBaselineTx = android.net.TrafficStats.getUidTxBytes(uid)
        statsLastRx = 0L
        statsLastTx = 0L
        statsLastTickMs = System.currentTimeMillis()
        val startMs = statsLastTickMs

        statsRunning = true
        statsThread = Thread({
            while (statsRunning) {
                try {
                    val nowMs = System.currentTimeMillis()
                    val curRxRaw = android.net.TrafficStats.getUidRxBytes(uid)
                    val curTxRaw = android.net.TrafficStats.getUidTxBytes(uid)
                    // На некоторых устройствах getUid* возвращает UNSUPPORTED (-1).
                    // В этом случае используем общесистемные счётчики.
                    val totalRx: Long
                    val totalTx: Long
                    if (curRxRaw < 0 || curTxRaw < 0) {
                        totalRx = (android.net.TrafficStats.getTotalRxBytes() - statsBaselineRx).coerceAtLeast(0L)
                        totalTx = (android.net.TrafficStats.getTotalTxBytes() - statsBaselineTx).coerceAtLeast(0L)
                    } else {
                        totalRx = (curRxRaw - statsBaselineRx).coerceAtLeast(0L)
                        totalTx = (curTxRaw - statsBaselineTx).coerceAtLeast(0L)
                    }
                    val dtMs = (nowMs - statsLastTickMs).coerceAtLeast(1L)
                    val rxRate = ((totalRx - statsLastRx) * 1000L) / dtMs
                    val txRate = ((totalTx - statsLastTx) * 1000L) / dtMs
                    statsLastRx = totalRx
                    statsLastTx = totalTx
                    statsLastTickMs = nowMs

                    pushStats(totalRx, totalTx,
                        rxRate.coerceAtLeast(0L),
                        txRate.coerceAtLeast(0L),
                        nowMs - startMs)
                } catch (t: Throwable) {
                    flog(TAG, "stats tick error: ${t.message}")
                }
                try { Thread.sleep(1000) } catch (_: InterruptedException) { break }
            }
        }, "vpn-stats").apply { isDaemon = true; start() }
    }

    private fun stopStatsReporter() {
        statsRunning = false
        statsThread?.interrupt()
        statsThread = null
    }

    // ── Notification ──────────────────────────────────────────────────────────

    /**
     * Запуск foreground-сервиса с ЯВНЫМ типом.
     *
     * На Android 14+ (targetSdk 34..36) двухаргументный startForeground()
     * без типа бросает InvalidForegroundServiceTypeException, а тип
     * specialUse для VPN-сервиса — ForegroundServiceTypeNotAllowedException.
     * Используем connectedDevice (корректный тип для VPN-туннеля) и
     * ServiceCompat, который сам выбирает нужную перегрузку по версии ОС.
     *
     * Любое исключение здесь логируем в файл и пробрасываем — без foreground
     * сервис всё равно нежизнеспособен, но теперь причина будет видна в логе.
     */
    private fun startVpnForeground(remark: String) {
        val notification = buildNotification(remark)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
            flog(TAG, "startForeground OK (type=connectedDevice, sdk=${Build.VERSION.SDK_INT})")
        } catch (t: Throwable) {
            flogE(TAG, "startForeground FAILED: ${t.javaClass.simpleName}: ${t.message}", t)
            throw t
        }
    }

    private fun buildNotification(remark: String): Notification {
        ensureNotificationChannel()
        val stopPi = PendingIntent.getService(this, 1,
            Intent(this, HysteriaTunVpnService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val openPi = PendingIntent.getActivity(this, 2,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("TeleOpen VPN")
            .setContentText(remark)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(openPi)
            .addAction(Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel, "Отключить", stopPi
            ).build())
            .setOngoing(true)
            .build()
    }

    private fun ensureNotificationChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(NOTIF_CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(
                NOTIF_CHANNEL, "TeleOpen VPN", NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) })
        }
    }

    /** Обновить текст уже показанной foreground-нотификации (kill-switch и т.п.). */
    private fun updateNotification(text: String) {
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotification(text))
        } catch (t: Throwable) {
            flogE(TAG, "updateNotification failed: ${t.message}", t)
        }
    }
}
