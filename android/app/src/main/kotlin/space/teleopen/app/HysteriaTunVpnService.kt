package space.teleopen.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.annotation.Keep
import androidx.core.app.ServiceCompat
import io.flutter.plugin.common.EventChannel
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileDescriptor
import java.io.FileOutputStream

class HysteriaTunVpnService : VpnService() {

    companion object {
        const val TAG = "TeleOpenVpn"

        const val ACTION_START_HYSTERIA = "space.teleopen.app.START_HYSTERIA"
        const val ACTION_START_V2RAY    = "space.teleopen.app.START_V2RAY"
        const val ACTION_START_BYEDPI   = "space.teleopen.app.START_BYEDPI"
        const val ACTION_STOP           = "space.teleopen.app.STOP_VPN"

        const val EXTRA_CONFIG      = "config"
        const val EXTRA_REMARK      = "remark"
        const val EXTRA_SOCKS5_PORT = "socks5_port"
        const val EXTRA_BYEDPI_ARGS = "byedpi_args"
        // Headless-запуск hysteria из виджета/тайла: Dart не поднимает бинарь
        // (приложение не открыто), поэтому конфиг едет сюда и сервис спавнит
        // libhysteria2.so сам. В обычном (Dart) пути этот extra отсутствует —
        // бинарь уже поднят Hysteria2Manager.start.
        const val EXTRA_HYSTERIA_CONFIG = "hysteria_config"
        const val EXTRA_PERAPP_ENABLED  = "perapp_enabled"
        const val EXTRA_ALLOWED_PACKAGES = "allowed_packages"
        const val EXTRA_KILL_SWITCH      = "kill_switch"
        // ── Новые INCY-фичи ──────────────────────────────────────────────
        const val EXTRA_XRAY_TUN_MODE    = "xray_tun_mode"
        const val EXTRA_KEEP_AWAKE       = "keep_awake"
        const val EXTRA_MEMORY_LIMIT_MB  = "memory_limit_mb"
        const val EXTRA_PROXY_ONLY       = "proxy_only"
        const val EXTRA_SOCKS_AUTH_USER  = "socks_auth_user"
        const val EXTRA_SOCKS_AUTH_PASS  = "socks_auth_pass"

        const val NOTIF_CHANNEL = "vpn_tun_channel"
        const val NOTIF_ID      = 7777

        // Локальный socks-порт для proxy-only режима (без TUN).
        const val proxyOnlySocksPort = 10808

        @Volatile var eventSink: EventChannel.EventSink? = null

        // Текущее состояние сервиса — чтобы UI при холодном старте мог узнать,
        // что туннель уже поднят (foreground-сервис жив в этом же процессе),
        // и не показывал «не подключено» при работающем VPN. См. isVpnRunning.
        @Volatile var serviceRunning = false
        @Volatile var activeRemark: String? = null

        // Application-контекст для зеркалирования статуса в виджет/тайл из
        // статического pushStatus (сам сервис — Context, но pushStatus static).
        @Volatile var appContext: Context? = null

        fun pushStatus(status: String) {
            val up = status.uppercase()
            when (up) {
                "CONNECTED" -> serviceRunning = true
                "STOPPED"   -> { serviceRunning = false; activeRemark = null }
            }
            // Зеркалим статус в FlutterSharedPreferences и перерисовываем
            // виджет/тайл — чтобы они были актуальны и при headless-запуске
            // (Dart не открыт и WidgetBridge.exportStatus не вызывался).
            mirrorWidgetStatus(up)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(status)
            }
        }

        private fun mirrorWidgetStatus(upStatus: String) {
            val ctx = appContext ?: return
            // Промежуточные статусы (CONNECTING/DROPPED) не трогают виджет —
            // он показывает только установившееся «подключено/отключено».
            val running = when (upStatus) {
                "CONNECTED" -> true
                "STOPPED"   -> false
                else        -> return
            }
            try {
                ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean("flutter.widget_vpn_running", running)
                    .putString("flutter.widget_last_remark", if (running) (activeRemark ?: "") else "")
                    .apply()
            } catch (_: Throwable) {}
            try { ServerWidgetProvider.refresh(ctx) } catch (_: Throwable) {}
            try {
                android.service.quicksettings.TileService.requestListeningState(
                    ctx,
                    android.content.ComponentName(ctx, VpnTileService::class.java)
                )
            } catch (_: Throwable) {}
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
                // Ротация по размеру: если файл > 1MB — пересоздаём
                if (f.exists() && f.length() > 1_000_000) f.delete()
                // Ротация по возрасту (настройка log_retention: 1h/6h/24h/7d/all).
                // 'all' — не чистим по времени.
                val retentionMs = when (loadCoreConfig(ctx).optString("log_retention", "24h")) {
                    "1h"  -> 3_600_000L
                    "6h"  -> 21_600_000L
                    "24h" -> 86_400_000L
                    "7d"  -> 604_800_000L
                    else  -> 0L // all
                }
                if (retentionMs > 0 && f.exists() &&
                    System.currentTimeMillis() - f.lastModified() > retentionMs) {
                    f.delete()
                }
                logFile = f
            } catch (_: Throwable) {}
        }

        // CRIT-3: дамп полного конфига в лог по умолчанию выключен. Включать
        // только локально при отладке — лог пишется на диск и переживает сессию.
        const val DEBUG_CONFIG_DUMP = false

        /**
         * Маскирует секреты в JSON-конфиге перед записью в лог: значения полей
         * id/password/auth/privateKey/publicKey/secret/psk и т.п. заменяются на
         * «***». Грубая, но достаточная защита для отладочного дампа.
         */
        fun redactSecrets(config: String): String {
            val keys = "id|uuid|password|pass|auth|secret|psk|privateKey|" +
                "publicKey|preSharedKey|token|obfs-password"
            val rx = Regex("\"($keys)\"\\s*:\\s*\"[^\"]*\"", RegexOption.IGNORE_CASE)
            return rx.replace(config) { m -> "\"${m.groupValues[1]}\":\"***\"" }
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
    // Бинарь hysteria, поднятый САМИМ сервисом (headless-запуск из виджета/тайла).
    // На обычном Dart-пути бинарь поднимает Hysteria2Manager, и это поле null.
    private var hysteriaProcess: Process? = null
    // ByeDPI: ciadpi работает как нативная библиотека В ПРОЦЕССЕ приложения
    // (не внешний процесс), чтобы его исходящие сокеты можно было protect()-ить
    // от VPN — иначе прямые соединения зациклились бы обратно в TUN.
    private var ciadpiThread: Thread? = null
    @Volatile private var ciadpiRunning = false
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
    private var mode: String = ""  // "hysteria" | "v2ray" | "byedpi" | ""

    // Per-app proxy для текущей сессии
    private var perAppEnabled: Boolean = false
    private var allowedPackages: List<String> = emptyList()

    // Kill-switch: если включён и core упал не по команде пользователя, НЕ рвём
    // туннель — держим TUN открытым без рабочего ядра, чтобы трафик не утекал
    // мимо VPN (fail-closed). intentionalStop отличает штатный stopVpn от краха.
    @Volatile private var killSwitchEnabled: Boolean = false
    @Volatile private var intentionalStop: Boolean = false

    // ── Новые INCY-фичи (текущая сессия) ───────────────────────────────────────
    @Volatile private var xrayTunMode: Boolean = false
    @Volatile private var keepDeviceAwake: Boolean = false
    @Volatile private var memoryLimitMB: Int = 100      // 0 = unlimited
    @Volatile private var proxyOnlyMode: Boolean = false
    @Volatile private var socksAuthUser: String = ""
    @Volatile private var socksAuthPass: String = ""
    // Wakelock, удерживающий CPU активным при keepDeviceAwake (Xiaomi и пр.)
    private var wakeLock: PowerManager.WakeLock? = null

    // Статистика трафика
    private var statsThread: Thread? = null
    @Volatile private var statsRunning: Boolean = false
    private var statsBaselineRx: Long = -1L
    private var statsBaselineTx: Long = -1L
    private var statsLastRx: Long = 0L
    private var statsLastTx: Long = 0L
    private var statsLastTickMs: Long = 0L

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        // App-контекст для зеркалирования статуса в виджет/тайл из static pushStatus.
        appContext = applicationContext
    }

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
             intent.action != ACTION_START_BYEDPI &&
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

        // ── Новые INCY-фичи: вычитываем из Intent в поля сессии ─────────────────
        xrayTunMode     = intent.getBooleanExtra(EXTRA_XRAY_TUN_MODE, false)
        keepDeviceAwake = intent.getBooleanExtra(EXTRA_KEEP_AWAKE, false)
        memoryLimitMB   = intent.getIntExtra(EXTRA_MEMORY_LIMIT_MB, 100)
        proxyOnlyMode   = intent.getBooleanExtra(EXTRA_PROXY_ONLY, false)
        socksAuthUser   = intent.getStringExtra(EXTRA_SOCKS_AUTH_USER) ?: ""
        socksAuthPass   = intent.getStringExtra(EXTRA_SOCKS_AUTH_PASS) ?: ""
        flog(TAG, "features: xrayTun=$xrayTunMode keepAwake=$keepDeviceAwake " +
            "memLimit=${memoryLimitMB}MB proxyOnly=$proxyOnlyMode socksAuth=${socksAuthUser.isNotEmpty()}")
        acquireWakeLockIfNeeded()

        // FGS-контракт: startForeground ДО ухода в фоновый поток, синхронно,
        // чтобы Android точно увидел foreground в течение 5 секунд.
        val remark = intent.getStringExtra(EXTRA_REMARK) ?: "TeleOpen"
        activeRemark = remark
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
        val byedpiArgs = intent.getStringArrayListExtra(EXTRA_BYEDPI_ARGS) ?: arrayListOf()
        // Headless hysteria: конфиг бинаря (пусто на обычном Dart-пути).
        val hysteriaConfig = intent.getStringExtra(EXTRA_HYSTERIA_CONFIG) ?: ""
        Thread({
            try {
                // Сериализуем весь жизненный цикл: пока идёт start, stop ждёт,
                // и наоборот. Исключает одновременную работу двух core с одним TUN.
                synchronized(lifecycleLock) {
                    when (action) {
                        ACTION_START_V2RAY    -> startV2Ray(config, remark)
                        ACTION_START_HYSTERIA -> startHysteria(port, remark, hysteriaConfig)
                        ACTION_START_BYEDPI   -> startByeDpi(byedpiArgs, port, remark)
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

    // ── Wakelock (keepDeviceAwake) ──────────────────────────────────────────────
    // На агрессивных прошивках (Xiaomi/MIUI, Huawei) система может усыплять CPU
    // под Doze, обрывая туннель. PARTIAL_WAKE_LOCK держит CPU активным, экран не
    // трогаем. Берём при старте, отпускаем в stopInternals/onDestroy — идемпотентно.
    private fun acquireWakeLockIfNeeded() {
        if (!keepDeviceAwake) return
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TeleOpen:vpn").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire()
                flog(TAG, "wakeLock acquired (keepDeviceAwake)")
            }
        } catch (t: Throwable) {
            flogE(TAG, "wakeLock acquire failed: ${t.message}", t)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                flog(TAG, "wakeLock released")
            }
        } catch (_: Throwable) {}
        wakeLock = null
    }

    // ── Hysteria2 mode (tun2socks → внешний hysteria SOCKS) ───────────────────

    private fun startHysteria(socks5Port: Int, remark: String, hysteriaConfig: String = "") {
        Log.i(TAG, "startHysteria port=$socks5Port headless=${hysteriaConfig.isNotEmpty()}")
        stopInternals()
        // Пауза, чтобы прошлый tun2socks/TUN освободили ресурсы.
        // Увеличена до 1000ms для надежности (особенно после kill-switch).
        try { Thread.sleep(1000) } catch (_: InterruptedException) {}
        mode = "hysteria"

        // Headless-путь (виджет/тайл): Dart не открыт, поднимаем бинарь hysteria
        // сами. На обычном пути hysteriaConfig пуст — бинарь уже поднял Dart.
        if (hysteriaConfig.isNotEmpty()) {
            if (!spawnHysteriaBinary(hysteriaConfig)) {
                flogE(TAG, "startHysteria: не удалось поднять бинарь hysteria")
                pushStatus("STOPPED"); stopSelf(); return
            }
        }

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

    /**
     * Поднять бинарь hysteria (libhysteria2.so) силами самого сервиса — нужно
     * на headless-пути (виджет/тайл), где Dart не запущен и Hysteria2Manager не
     * вызывался. Конфиг пишем в filesDir/hy2_widget.json (тот же формат, что и
     * Dart-конфиг). Возвращает false, если бинарь не стартовал или сразу умер.
     */
    private fun spawnHysteriaBinary(config: String): Boolean {
        return try {
            val binPath = File(applicationInfo.nativeLibraryDir, "libhysteria2.so").absolutePath
            val cfgFile = File(filesDir, "hy2_widget.json")
            cfgFile.writeText(config)
            val pb = ProcessBuilder(binPath, "-c", cfgFile.absolutePath)
                .redirectErrorStream(true)
                .directory(filesDir)
            // Лимит памяти (фича №5): hysteria — внешний Go-процесс, поэтому
            // GOMEMLIMIT здесь работает надёжно (рантайм читает env при старте).
            if (memoryLimitMB > 0) {
                pb.environment()["GOMEMLIMIT"] = "${memoryLimitMB}MiB"
                flog(TAG, "hysteria GOMEMLIMIT=${memoryLimitMB}MiB")
            }
            val proc = pb.start()
            hysteriaProcess = proc
            // Лог бинаря → файловый лог; заодно ловим внезапную смерть.
            Thread({
                try {
                    proc.inputStream.bufferedReader().forEachLine { flog("hy2", it) }
                } catch (_: Exception) {}
                if (isRunning && mode == "hysteria") handleUnexpectedDeath("hysteria.exit")
            }, "hy2_log").apply { isDaemon = true }.start()
            // Бинарь мог упасть сразу (битый конфиг/занятый порт) — даём подняться.
            try { Thread.sleep(1500) } catch (_: InterruptedException) {}
            if (!proc.isAlive) {
                flogE(TAG, "hysteria бинарь завершился сразу после старта")
                hysteriaProcess = null
                return false
            }
            flog(TAG, "hysteria бинарь поднят (headless)")
            true
        } catch (t: Throwable) {
            flogE(TAG, "spawnHysteriaBinary fatal: ${t.message}", t)
            hysteriaProcess = null
            false
        }
    }

    // ── ByeDPI mode (ciadpi в процессе → tun2socks → напрямую, без сервера) ────

    private fun startByeDpi(args: ArrayList<String>, socks5Port: Int, remark: String) {
        flog(TAG, "startByeDpi port=$socks5Port argc=${args.size}")
        stopInternals()
        try { Thread.sleep(1000) } catch (_: InterruptedException) {}
        mode = "byedpi"

        // Мягкая деградация: если libciadpi.so не собрана — не падаем, а честно
        // сообщаем и останавливаемся (см. android/app/src/main/jni/README.md).
        if (!CiadpiNative.available) {
            flogE(TAG, "ciadpi native lib отсутствует — собери libciadpi.so (jni/README.md)")
            pushStatus("STOPPED"); stopSelf(); return
        }

        val tun: ParcelFileDescriptor
        try {
            tun = buildTunInterface(remark) ?: run {
                flogE(TAG, "startByeDpi: buildTunInterface вернул null")
                pushStatus("STOPPED"); stopSelf(); return
            }
        } catch (t: Throwable) {
            flogE(TAG, "startByeDpi pre-start fatal: ${t.javaClass.simpleName}: ${t.message}", t)
            pushStatus("STOPPED"); stopSelf(); return
        }
        tunInterface = tun
        isRunning = true

        // ciadpi слушает 127.0.0.1:port; его исходящие сокеты protect()-им, чтобы
        // прямые соединения шли мимо TUN (иначе петля). Колбэк зовётся из натива.
        ciadpiRunning = true
        ciadpiThread = Thread({
            try {
                val rc = CiadpiNative.nativeStart(
                    args.toTypedArray(), "127.0.0.1", socks5Port,
                    object : CiadpiNative.SocketProtector {
                        override fun protect(fd: Int): Boolean =
                            this@HysteriaTunVpnService.protect(fd)
                    })
                flog(TAG, "ciadpi loop exited rc=$rc")
            } catch (t: Throwable) {
                flogE(TAG, "ciadpi thread fatal: ${t.message}", t)
            }
            // Поток ciadpi завершился. Если мы при этом ещё «работаем» — это
            // внезапная смерть движка → kill-switch.
            if (isRunning && mode == "byedpi") handleUnexpectedDeath("ciadpi.exit")
        }, "ciadpi").apply { isDaemon = true; start() }

        try {
            startTun2Socks(tun.fileDescriptor, socks5Port, "sock_path_byedpi")
            pushStatus("CONNECTED"); startStatsReporter()
            flog(TAG, "ByeDPI VPN started")
        } catch (e: Exception) {
            flogE(TAG, "startByeDpi error: $e", e)
            pushStatus("STOPPED"); stopSelf()
        }
    }

    // ── V2Ray mode (встроенный TUN внутри xray-core) ──────────────────────────

    private fun startV2Ray(rawConfig: String, remark: String) {
        flog(TAG, "startV2Ray BEGIN remark=$remark configLen=${rawConfig.length}")
        // Даём предыдущему core/TUN полностью освободить ресурсы (stopLoop
        // асинхронен). Без паузы повторный коннект мог наложиться на ещё
        // живой core. Увеличена до 1000ms для надежности (особенно после kill-switch).
        try { Thread.sleep(1000) } catch (_: InterruptedException) {}
        mode = "v2ray"

        if (rawConfig.isBlank()) {
            flogE(TAG, "empty config")
            pushStatus("STOPPED"); stopSelf(); return
        }

        // xrayTunMode (фича №1): для vless/vmess/trojan xray и так управляет TUN
        // напрямую через inbound protocol:"tun" (gVisor, setBlocking=true ниже),
        // tun2socks здесь не используется. Поэтому тоггл для этого пути —
        // подтверждение текущего поведения, а не развилка. Альтернативный путь
        // «xray → socks → tun2socks» как fallback — отдельная задача.
        if (!proxyOnlyMode) {
            flog(TAG, "xray-TUN direct mode active (xrayTunMode=$xrayTunMode, gVisor TUN inbound)")
        }

        var pfd: ParcelFileDescriptor? = null
        try {
            // 1) Готовим конфиг с TUN-inbound
            val config = ensureTunInbound(rawConfig)
            flog(TAG, "config after ensureTunInbound, len=${config.length}")
            // CRIT-3: НЕ дампим конфиг в файловый лог — он содержит пароли/UUID/
            // reality-ключи в открытом виде, а лог переживает сессию на диске.
            // Дамп только при явно включённом локальном флаге и с маскировкой
            // секретов. По умолчанию выключено.
            @Suppress("ConstantConditionIf")
            if (DEBUG_CONFIG_DUMP) {
                flog(TAG, "config (redacted): ${redactSecrets(config).take(4000)}")
            }

            // 2) Поднимаем TUN — кроме proxy-only режима (фича №6), где xray
            //    работает чистым локальным прокси без VpnService.establish()
            //    (а значит без VPN-ключа в статусбаре).
            val fd: Int
            if (proxyOnlyMode) {
                fd = -1
                v2rayDetachedFd = -1
                flog(TAG, "proxy-only mode: TUN не поднимаем, xray как локальный socks")
            } else {
                pfd = buildTunInterface(remark) ?: run {
                    flogE(TAG, "buildTunInterface returned null (no VPN permission?)")
                    pushStatus("STOPPED"); stopSelf(); return
                }
                flog(TAG, "VpnService.Builder.establish() OK, pfd=$pfd")

                fd = pfd.detachFd()
                pfd = null
                v2rayDetachedFd = fd
                flog(TAG, "TUN detachedFd=$fd")
            }

            // 3) initCoreEnv
            try {
                val assetsDir = filesDir.absolutePath
                // geoip.dat/geosite.dat вшиты в assets/geo и нужны xray для
                // правил geosite:/geoip: (блок рекламы, маршрут по стране).
                // xray ищет их в assetsDir (= filesDir), поэтому копируем туда
                // при первом старте (если ещё не скопированы).
                copyGeoAssets(assetsDir)
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
     * Копирует вшитые geoip.dat / geosite.dat из assets/geo в каталог,
     * где их ищет xray (assetsDir = filesDir). Чтобы не копировать ~15МБ на
     * каждый коннект, ставим маркер .geo_version с versionCode приложения —
     * перекопируем только при первом старте и после обновления приложения.
     * Отсутствие файлов в assets не фатально — правила geosite:/geoip: просто
     * не сработают (xray не падает).
     */
    private fun copyGeoAssets(destDir: String) {
        val verCode = try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0).versionCode.toString()
        } catch (_: Throwable) { "0" }
        val marker = File(destDir, ".geo_version")
        val upToDate = marker.exists() &&
            marker.readText() == verCode &&
            File(destDir, "geoip.dat").exists() &&
            File(destDir, "geosite.dat").exists()
        if (upToDate) {
            flog(TAG, "geo: файлы актуальны (v$verCode)")
            return
        }
        var ok = true
        for (name in listOf("geoip.dat", "geosite.dat")) {
            try {
                val out = File(destDir, name)
                assets.open("geo/$name").use { input ->
                    FileOutputStream(out).use { os -> input.copyTo(os, 64 * 1024) }
                }
                flog(TAG, "geo: $name скопирован (${out.length()} б)")
            } catch (e: java.io.FileNotFoundException) {
                ok = false
                flog(TAG, "geo: $name отсутствует в assets — правила geo не будут работать")
            } catch (t: Throwable) {
                ok = false
                flogE(TAG, "geo: копирование $name упало", t)
            }
        }
        if (ok) marker.writeText(verCode)
    }

    /**
     * xray-core активирует TUN-обработчик ТОЛЬКО при наличии такого inbound.
     * Существующие inbounds (socks/http) оставляем — они не мешают (для in-app proxy/тестов).
     *
     * Также мерджит sniffing-настройки и DNS-блок из core_config.json
     * (см. NativeExtensions.applyCoreConfig).
     */
    /**
     * Включает password-авторизацию у локального socks/http inbound xray.
     * Формат xray: settings.auth="password" + settings.accounts=[{user,pass}].
     * Существующие ключи settings (udp, ip и т.п.) сохраняем.
     */
    private fun applyProxyAuth(inbound: JSONObject, user: String, pass: String) {
        val settings = inbound.optJSONObject("settings") ?: JSONObject().also {
            inbound.put("settings", it)
        }
        settings.put("auth", "password")
        val accounts = JSONArray().put(
            JSONObject().put("user", user).put("pass", pass)
        )
        settings.put("accounts", accounts)
    }

    /**
     * Лимит памяти (MB) → размер буфера соединения xray (KB). Меньше памяти —
     * меньше буфер. Подобрано так, чтобы 40MB был ощутимо экономным, а 150MB —
     * близок к дефолту xray.
     */
    private fun memLimitToBufferKb(limitMB: Int): Int = when {
        limitMB <= 40  -> 16
        limitMB <= 60  -> 32
        limitMB <= 80  -> 64
        limitMB <= 100 -> 128
        else           -> 256
    }

    private fun ensureTunInbound(raw: String): String {
        return try {
            val root = JSONObject(raw)
            val cfg = loadCoreConfig(this)

            // ── Sniffing: формируем общий блок из настроек ─────────────
            val destOverride = JSONArray()
            val httpOver = cfg.optString("meta_sniff_http_override", "")
            val tlsOver  = cfg.optString("meta_sniff_tls_override", "")
            val quicOver = cfg.optString("meta_sniff_quic_override", "")
            val blockAdsOn = cfg.optBoolean("block_ads", false)
            // Если пользователь явно выключил — не добавляем; иначе добавляем
            // (умолчание = «как было», т.е. http + tls).
            if (httpOver != "Выключить") destOverride.put("http")
            if (tlsOver  != "Выключить") destOverride.put("tls")
            // QUIC (HTTP/3): без сниффинга QUIC домен из соединения не
            // извлекается, и domain-правило блока рекламы не срабатывает —
            // именно поэтому реклама по HTTP/3 (Google/YouTube) проходила.
            // При включённом блоке рекламы сниффим QUIC принудительно, если
            // пользователь явно его не выключил.
            val wantQuic = quicOver == "Включить" ||
                (blockAdsOn && quicOver != "Выключить")
            if (wantQuic) destOverride.put("quic")
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

            // ── Авторизация локальных прокси (фича №2) ──────────────────
            // socksAuth прилетает по bridge (поля сервиса), httpAuth — только в
            // FlutterSharedPreferences (Dart его по MethodChannel не шлёт).
            val httpPrefs = try {
                getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            } catch (_: Throwable) { null }
            val httpAuthOn = httpPrefs?.getBoolean("flutter.s_httpAuthEnabled", false) ?: false
            val httpUser = httpPrefs?.getString("flutter.s_httpAuthUsername", "") ?: ""
            val httpPass = httpPrefs?.getString("flutter.s_httpAuthPassword", "") ?: ""

            // ── TUN inbound ─────────────────────────────────────────────
            val inbounds = root.optJSONArray("inbounds") ?: JSONArray().also { root.put("inbounds", it) }

            // Отдельный проход: инжект accounts в локальные socks/http inbound.
            // Отдельно от tun-цикла, т.к. там есть break (socks/http могут идти
            // после tun-inbound и иначе были бы пропущены).
            for (i in 0 until inbounds.length()) {
                val inb = inbounds.optJSONObject(i) ?: continue
                when (inb.optString("protocol").lowercase()) {
                    "socks" -> if (socksAuthUser.isNotEmpty()) {
                        applyProxyAuth(inb, socksAuthUser, socksAuthPass)
                        flog(TAG, "socks inbound: auth injected (user=$socksAuthUser)")
                    }
                    "http" -> if (httpAuthOn && httpUser.isNotEmpty()) {
                        applyProxyAuth(inb, httpUser, httpPass)
                        flog(TAG, "http inbound: auth injected (user=$httpUser)")
                    }
                }
            }

            // ── Режим туннеля (tunnel_mode): tun_only убирает локальные ──
            // socks/http inbounds — наружу торчит только TUN, без прокси-порта.
            // (proxy_only обрабатывается отдельно через proxyOnlyMode/без TUN.)
            if (cfg.optString("tunnel_mode", "tun_proxy") == "tun_only" && !proxyOnlyMode) {
                val kept = JSONArray()
                var removed = 0
                for (i in 0 until inbounds.length()) {
                    val inb = inbounds.optJSONObject(i) ?: continue
                    val p = inb.optString("protocol").lowercase()
                    if (p == "socks" || p == "http") { removed++; continue }
                    kept.put(inb)
                }
                if (removed > 0) {
                    // inbounds уже лежит в root — мутируем на месте (clear + refill).
                    while (inbounds.length() > 0) inbounds.remove(inbounds.length() - 1)
                    for (i in 0 until kept.length()) inbounds.put(kept.get(i))
                    flog(TAG, "tunnel_mode=tun_only: removed $removed local socks/http inbounds")
                }
            }

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
            if (proxyOnlyMode) {
                // Proxy-only (фича №6): TUN не поднимаем — xray работает чистым
                // локальным прокси. Гарантируем наличие socks inbound на
                // 127.0.0.1:<port>, чтобы было куда подключаться приложениям.
                var hasSocks = false
                for (i in 0 until inbounds.length()) {
                    if (inbounds.optJSONObject(i)?.optString("protocol")
                            .equals("socks", ignoreCase = true)) { hasSocks = true; break }
                }
                if (!hasSocks) {
                    // Адрес/порт берём из настроек (0.0.0.0 = доступ через хотспот).
                    val bindAddr = cfg.optString("socks_bind_address", "127.0.0.1")
                        .ifBlank { "127.0.0.1" }
                    val bindPort = cfg.optInt("socks_port", proxyOnlySocksPort)
                        .takeIf { it in 1024..65535 } ?: proxyOnlySocksPort
                    val socksInb = JSONObject()
                        .put("listen", bindAddr)
                        .put("port", bindPort)
                        .put("protocol", "socks")
                        .put("tag", "socks-in")
                        .put("settings", JSONObject().put("udp", true))
                        .put("sniffing", sniffingObj)
                    if (socksAuthUser.isNotEmpty()) applyProxyAuth(socksInb, socksAuthUser, socksAuthPass)
                    inbounds.put(socksInb)
                    flog(TAG, "proxy-only: socks inbound injected on $bindAddr:$bindPort")
                }
            } else if (!hasTun) {
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

            // ── Policy: лимит памяти (№5) + таймаут простоя (idle timeout) ───
            // Реальный рычаг памяти xray — размер буфера на соединение
            // (policy.levels.<level>.bufferSize, в КБ). connIdle закрывает
            // простаивающие коннекты (экономит память и дескрипторы).
            // GOMEMLIMIT для in-process xray ненадёжен (рантайм поднят при dlopen),
            // поэтому ограничиваем именно буфером; для внешнего hysteria см. ProcessBuilder.
            run {
                val connIdle = cfg.optInt("conn_idle_timeout", 300)
                val needBuf = memoryLimitMB > 0
                if (needBuf || connIdle > 0) {
                    val policy = root.optJSONObject("policy") ?: JSONObject().also { root.put("policy", it) }
                    val levels = policy.optJSONObject("levels") ?: JSONObject().also { policy.put("levels", it) }
                    val lvl0 = levels.optJSONObject("0") ?: JSONObject().also { levels.put("0", it) }
                    if (needBuf) lvl0.put("bufferSize", memLimitToBufferKb(memoryLimitMB))
                    if (connIdle > 0) lvl0.put("connIdle", connIdle)
                    flog(TAG, "policy: bufferSize=${if (needBuf) memLimitToBufferKb(memoryLimitMB) else -1}KB " +
                        "connIdle=${connIdle}s (limit=${memoryLimitMB}MB)")
                }
                // Примечание: max_tcp_conns/max_udp_conns из настроек xray-core
                // напрямую не ограничивает (нет такого knob), поэтому здесь не
                // применяются — только сохраняются/показываются в UI.
                val maxTcp = cfg.optInt("max_tcp_conns", 0)
                val maxUdp = cfg.optInt("max_udp_conns", 0)
                if (maxTcp > 0 || maxUdp > 0) {
                    flog(TAG, "conn limits (informational, xray не энфорсит): tcp=$maxTcp udp=$maxUdp")
                }
            }

            // ── DNS-блок ────────────────────────────────────────────────
            val dnsRemote = cfg.optString("dns_remote", "")
            val dnsDirect = cfg.optString("dns_direct", "")
            // Тип IP (ip_type): ipv4/ipv6/auto → xray dns.queryStrategy.
            val ipQueryStrategy = when (cfg.optString("ip_type", "auto")) {
                "ipv4" -> "UseIPv4"
                "ipv6" -> "UseIPv6"
                else   -> "UseIP"
            }
            if (dnsRemote.isNotEmpty() || dnsDirect.isNotEmpty()) {
                val dns = root.optJSONObject("dns") ?: JSONObject()
                val servers = JSONArray()
                if (dnsRemote.isNotEmpty()) servers.put(dnsRemote)
                if (dnsDirect.isNotEmpty()) servers.put(dnsDirect)
                dns.put("servers", servers)
                // queryStrategy: FakeIP форсит UseIP; иначе берём из ip_type.
                dns.put("queryStrategy", if (cfg.optBoolean("dns_fake", false)) "UseIP" else ipQueryStrategy)
                root.put("dns", dns)
                flog(TAG, "DNS block merged: remote=$dnsRemote direct=$dnsDirect qs=$ipQueryStrategy")
            }

            // ── Log level из External Controller ───────────────────────
            val logLevel = cfg.optString("ec_log_level", "")
            if (logLevel.isNotEmpty() && logLevel != "Не менять") {
                val logObj = root.optJSONObject("log") ?: JSONObject()
                logObj.put("loglevel", logLevel)
                root.put("log", logObj)
            }

            // ── Routing: блок рекламы + маршрут по стране (geo) ─────────
            // Требуют вшитых geoip.dat/geosite.dat (copyGeoAssets). Если их нет,
            // xray тихо проигнорирует правила — поведение деградирует, не падает.
            // Правила добавляем В НАЧАЛО списка (приоритетнее дефолтного
            // private-IP→direct из Dart-конфига). Порядок: сперва блок рекламы,
            // затем direct по стране.
            val routing = root.optJSONObject("routing") ?: JSONObject().also {
                it.put("domainStrategy", "IPIfNonMatch")
                root.put("routing", it)
            }
            val existingRules = routing.optJSONArray("rules") ?: JSONArray()
            val newRules = JSONArray()
            // 0) Пользовательские правила (geosite/geoip/домен/IP → proxy|direct|block).
            // Идут ПЕРВЫМИ: в xray выигрывает первое совпавшее правило, а явные
            // пользовательские правила должны иметь приоритет над авто-правилами.
            val userRules = cfg.optJSONArray("routing_rules")
            if (userRules != null) {
                for (i in 0 until userRules.length()) {
                    val r = userRules.optJSONObject(i) ?: continue
                    val kind = r.optString("kind", "")
                    val value = r.optString("value", "").trim()
                    val action = r.optString("action", "proxy")
                    if (value.isEmpty()) continue
                    val tag = when (action) {
                        "direct" -> "direct"
                        "block" -> "block"
                        else -> "proxy"
                    }
                    val rule = JSONObject().put("type", "field").put("outboundTag", tag)
                    when (kind) {
                        "geosite" -> rule.put("domain", JSONArray().put("geosite:$value"))
                        "geoip" -> rule.put("ip", JSONArray().put("geoip:$value"))
                        "ip" -> rule.put("ip", JSONArray().put(value))
                        "domain" -> {
                            // "*.example.com" → "domain:example.com"; голый домен без
                            // известного префикса тоже оборачиваем в "domain:" (матч
                            // домена и поддоменов). Префиксы full:/regexp:/geosite:
                            // пропускаем как есть для продвинутых пользователей.
                            val dv = when {
                                value.startsWith("*.") -> "domain:${value.substring(2)}"
                                value.contains(":") -> value
                                else -> "domain:$value"
                            }
                            rule.put("domain", JSONArray().put(dv))
                        }
                        else -> continue
                    }
                    newRules.put(rule)
                }
                if (userRules.length() > 0) flog(TAG, "routing: +${userRules.length()} user rules")
            }
            // 0b) Блокировка UDP (block_udp): ломает QUIC/DoH-UDP/звонки/игры —
            // включается осознанно. Правило раньше блока рекламы и региона.
            if (cfg.optBoolean("block_udp", false)) {
                newRules.put(JSONObject()
                    .put("type", "field")
                    .put("network", "udp")
                    .put("outboundTag", "block"))
                flog(TAG, "routing: block_udp → network:udp → block")
            }
            // 1) Блок рекламы
            if (blockAdsOn) {
                newRules.put(JSONObject()
                    .put("type", "field")
                    .put("domain", JSONArray().put("geosite:category-ads-all"))
                    .put("outboundTag", "block"))
                flog(TAG, "routing: block_ads → geosite:category-ads-all")
            }
            // 2) Регион: трафик страны идёт мимо VPN (direct). Код страны
            // (напр. "ru") приходит готовым из Dart (AppSettings.regionCodeOf).
            val regionCode = cfg.optString("region_code", "").lowercase()
            if (regionCode.isNotEmpty()) {
                // Исключение: заблокированные сервисы (Telegram и др.) форсируем
                // через proxy ДО правила regional-direct, т.к. их IP могут
                // попадать в geoip:ru (российские CDN/серверы после разблокировки).
                val proxyBeforeRegion = JSONArray()
                    .put("geosite:telegram")
                    .put("geosite:google")
                    .put("geosite:meta")
                    .put("geosite:twitter")
                    .put("geosite:instagram")
                    .put("geosite:youtube")
                newRules.put(JSONObject()
                    .put("type", "field")
                    .put("domain", proxyBeforeRegion)
                    .put("outboundTag", "proxy"))
                flog(TAG, "routing: blocked services → proxy (before region)")
                newRules.put(JSONObject()
                    .put("type", "field")
                    .put("ip", JSONArray().put("geoip:$regionCode"))
                    .put("outboundTag", "direct"))
                flog(TAG, "routing: region → geoip:$regionCode direct")
            }
            // Склейка: новые (приоритетные) + существующие.
            if (newRules.length() > 0) {
                for (i in 0 until existingRules.length()) newRules.put(existingRules.get(i))
                routing.put("rules", newRules)

                // Правила выше ссылаются на outboundTag "block"/"direct".
                // Если в пер-нодовом конфиге таких outbound'ов нет, xray роняет
                // правило в никуда — реклама/региональный трафик тогда проходят
                // мимо блока. Досыпаем недостающие blackhole/freedom.
                val outbounds = root.optJSONArray("outbounds")
                    ?: JSONArray().also { root.put("outbounds", it) }
                var hasBlock = false
                var hasDirect = false
                for (i in 0 until outbounds.length()) {
                    when (outbounds.optJSONObject(i)?.optString("tag")) {
                        "block" -> hasBlock = true
                        "direct" -> hasDirect = true
                    }
                }
                if (!hasBlock) {
                    outbounds.put(JSONObject()
                        .put("protocol", "blackhole")
                        .put("tag", "block"))
                    flog(TAG, "outbounds: + blackhole 'block'")
                }
                if (!hasDirect) {
                    outbounds.put(JSONObject()
                        .put("protocol", "freedom")
                        .put("tag", "direct"))
                    flog(TAG, "outbounds: + freedom 'direct'")
                }
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
            if (isRunning && (mode == "hysteria" || mode == "byedpi")) {
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
        stopCiadpi()
        try { tun2socksProcess?.destroy() } catch (_: Exception) {}
        tun2socksProcess = null
        try { hysteriaProcess?.destroy() } catch (_: Exception) {}
        if (hysteriaProcess != null) {
            hysteriaProcess = null
            try { File(filesDir, "hy2_widget.json").delete() } catch (_: Exception) {}
        }
        // Закрываем TUN корректно, чтобы следующий establish() не конфликтовал
        closeDetachedFd()
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null
        try { updateNotification("Переподключение...") } catch (_: Throwable) {}
        pushStatus("DROPPED")
    }

    /** Останавливает движок ciadpi (режим byedpi), если он запущен. */
    private fun stopCiadpi() {
        if (!ciadpiRunning && ciadpiThread == null) return
        ciadpiRunning = false
        try { if (CiadpiNative.available) CiadpiNative.nativeStop() } catch (_: Throwable) {}
        try { ciadpiThread?.join(1000) } catch (_: Exception) {}
        ciadpiThread = null
    }

    private fun stopInternals() {
        isRunning = false

        // 0) Отпускаем wakelock (если держали)
        releaseWakeLock()

        // 1) Останавливаем прокси-движок (он перестанет читать с TUN fd)
        try { coreController?.stopLoop() } catch (e: Exception) { Log.w(TAG, "stopLoop: $e") }
        coreController = null

        // 1b) Останавливаем ciadpi (режим byedpi)
        stopCiadpi()

        // 2) Глушим tun2socks (если был)
        try { tun2socksProcess?.destroy() } catch (_: Exception) {}
        tun2socksProcess = null

        // 2b) Глушим бинарь hysteria, если его поднимал сам сервис (headless).
        // Конфиг содержит auth/obfs-password в открытом виде — удаляем его.
        try { hysteriaProcess?.destroy() } catch (_: Exception) {}
        if (hysteriaProcess != null) {
            hysteriaProcess = null
            try { File(filesDir, "hy2_widget.json").delete() } catch (_: Exception) {}
        }

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
            // routeLanThroughProxy (фича №7) — инверсия bypassPrivate: если включён,
            // приватные подсети (10/8, 172.16/12, 192.168/16) НЕ исключаются из TUN,
            // т.е. весь LAN-трафик уходит в туннель. Флаг по bridge не передаётся —
            // читаем напрямую из FlutterSharedPreferences (ключ с префиксом flutter.).
            val routeLanThroughProxy = try {
                getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getBoolean("flutter.s_routeLanThroughProxy", false)
            } catch (_: Throwable) { false }
            val bypassPrivate = !routeLanThroughProxy && cfg.optBoolean("net_bypass_private", false)
            flog(TAG, "routing: routeSystem=$routeSystem bypassPrivate=$bypassPrivate " +
                "routeLanThroughProxy=$routeLanThroughProxy")

            if (routeSystem) {
                if (bypassPrivate && android.os.Build.VERSION.SDK_INT >= 33) {
                    builder.addRoute("0.0.0.0", 0)
                    // Список исключаемых из туннеля подсетей берём из настроек
                    // (редактор «Исключённые маршруты»); если пуст — дефолтный набор.
                    val routes = cfg.optJSONArray("excluded_routes")
                    val cidrs = ArrayList<String>()
                    if (routes != null && routes.length() > 0) {
                        for (i in 0 until routes.length()) {
                            routes.optString(i).trim().takeIf { it.isNotEmpty() }?.let { cidrs.add(it) }
                        }
                    }
                    if (cidrs.isEmpty()) cidrs.addAll(listOf("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
                    var excluded = 0
                    for (cidr in cidrs) {
                        try {
                            val slash = cidr.indexOf('/')
                            if (slash <= 0) continue
                            val ip = cidr.substring(0, slash)
                            val prefix = cidr.substring(slash + 1).toIntOrNull() ?: continue
                            builder.excludeRoute(android.net.IpPrefix(
                                java.net.InetAddress.getByName(ip), prefix))
                            excluded++
                        } catch (t: Throwable) {
                            flog(TAG, "TUN: excludeRoute skip '$cidr': ${t.message}")
                        }
                    }
                    flog(TAG, "TUN: bypass private networks — excluded $excluded routes")
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
    /** Человекочитаемая скорость: B/s → KB/s/MB/s. */
    private fun fmtSpeed(bps: Long): String = when {
        bps >= 1_000_000 -> String.format("%.1f MB/s", bps / 1_000_000.0)
        bps >= 1_000     -> String.format("%.0f KB/s", bps / 1_000.0)
        else             -> "$bps B/s"
    }

    private fun startStatsReporter() {
        stopStatsReporter()
        // Показывать скорость в уведомлении? (настройка show_speed_notification)
        val showSpeed = try { loadCoreConfig(this).optBoolean("show_speed_notification", false) }
            catch (_: Throwable) { false }
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

                    // Скорость в уведомлении (если включено): ↓ загрузка · ↑ отдача.
                    if (showSpeed) {
                        val remark = activeRemark ?: "TeleOpen"
                        updateNotification("$remark   ↓ ${fmtSpeed(rxRate.coerceAtLeast(0L))} · ↑ ${fmtSpeed(txRate.coerceAtLeast(0L))}")
                    }
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

/**
 * JNI-мост к движку ByeDPI (ciadpi), собранному как libciadpi.so.
 *
 * Библиотека грузится «мягко»: если её нет в jniLibs (не собрана), [available]
 * == false и режим ByeDPI честно сообщит об ошибке вместо краша. Инструкция по
 * сборке: android/app/src/main/jni/README.md.
 *
 * Контракт нативной стороны:
 *   nativeStart(args, ip, port, protector) — БЛОКИРУЮЩИЙ: поднимает SOCKS5 на
 *     ip:port с десинхронизацией по [args] и крутит цикл до nativeStop().
 *     Для каждого исходящего сокета зовёт protector.protect(fd), чтобы прямые
 *     соединения шли мимо VPN. Возвращает код выхода.
 *   nativeStop() — сигнал циклу завершиться (вызывается из другого потока).
 */
object CiadpiNative {
    /** Интерфейс защиты сокетов от VPN (реализуется VpnService.protect).
     *  @Keep обязателен: нативный код зовёт protect(I)Z по строковому имени
     *  через JNI, R8 не должен переименовывать метод (иначе NoSuchMethodError). */
    @Keep
    interface SocketProtector {
        @Keep
        fun protect(fd: Int): Boolean
    }

    @Volatile
    var available: Boolean = false
        private set

    init {
        available = try {
            System.loadLibrary("ciadpi")
            true
        } catch (t: Throwable) {
            Log.w(HysteriaTunVpnService.TAG, "libciadpi.so не загружена: ${t.message}")
            false
        }
    }

    external fun nativeStart(
        args: Array<String>,
        ip: String,
        port: Int,
        protector: SocketProtector,
    ): Int

    external fun nativeStop()
}
