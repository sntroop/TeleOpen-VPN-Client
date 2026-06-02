package space.teleopen.app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL         = "space.teleopen.app/native"
        const val EVENT_CHANNEL          = "space.teleopen.app/vpn_status"
        const val VPN_PERMISSION_REQUEST = 1001
        const val GEO_FILE_PICK_REQUEST  = 1002
        // Action для PendingIntent, который PackageInstaller дёргает с
        // результатом установки (см. installApk + installResultReceiver).
        const val ACTION_INSTALL_STATUS  = "space.teleopen.app.INSTALL_STATUS"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingAction: String = ""
    private var pendingConfig: String = ""
    private var pendingRemark: String = ""
    private var pendingPort: Int = 10900
    private var pendingPerAppEnabled: Boolean = false
    private var pendingAllowedPackages: List<String> = emptyList()
    private var pendingKillSwitch: Boolean = false

    // Для импорта geo-файла: ждём результата SAF picker
    private var pendingGeoResult: MethodChannel.Result? = null
    private var pendingGeoKind: String = ""

    // Установка APK через PackageInstaller асинхронна: commit() возвращается
    // сразу, а реальный итог (успех/ошибка/нужно подтверждение) прилетает
    // позже бродкастом. Поэтому держим Result от MethodChannel здесь, пока
    // не получим финальный статус, и регистрируем ресивер.
    private var pendingInstallResult: MethodChannel.Result? = null
    private var installReceiverRegistered = false

    private val installResultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_INSTALL_STATUS) return
            val status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    // Системе нужно подтверждение юзера — запускаем диалог.
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            startActivity(confirm)
                        } catch (t: Throwable) {
                            finishInstall(false, "INSTALL_ERR",
                                "Не удалось открыть диалог установки: ${t.message}")
                        }
                    } else {
                        finishInstall(false, "INSTALL_ERR",
                            "Система не вернула диалог подтверждения")
                    }
                    // Финальный статус (успех/ошибка) прилетит ещё одним бродкастом.
                }
                PackageInstaller.STATUS_SUCCESS -> {
                    finishInstall(true, null, null)
                }
                else -> {
                    // Любая ошибка установки. Распознаём конфликт подписи —
                    // он бывает при обновлении поверх версии, подписанной
                    // другим ключом (после смены keystore).
                    val incompatible = msg?.contains(
                        "INSTALL_FAILED_UPDATE_INCOMPATIBLE", ignoreCase = true) == true ||
                        msg?.contains("signatures do not match", ignoreCase = true) == true
                    if (incompatible) {
                        finishInstall(false, "UPDATE_INCOMPATIBLE",
                            "Установлена версия с другим ключом подписи. " +
                            "Удалите старое приложение и установите заново.")
                    } else {
                        finishInstall(false, "INSTALL_FAILED",
                            msg ?: "Установка не выполнена (код $status)")
                    }
                }
            }
        }
    }

    /** Отдать финальный результат установки в Dart ровно один раз. */
    private fun finishInstall(ok: Boolean, errorCode: String?, errorMsg: String?) {
        val r = pendingInstallResult ?: return
        pendingInstallResult = null
        runOnUiThread {
            if (ok) r.success(true)
            else r.error(errorCode ?: "INSTALL_ERR", errorMsg, null)
        }
    }

    /**
     * Установка APK через PackageInstaller. В отличие от старого
     * Intent.ACTION_VIEW, здесь система присылает РЕАЛЬНЫЙ код результата
     * (успех / конкретная ошибка / нужно подтверждение) бродкастом на
     * ACTION_INSTALL_STATUS → installResultReceiver. Тяжёлое копирование APK
     * в сессию делаем в фоновом потоке.
     */
    private fun installViaPackageInstaller(apk: File) {
        Thread {
            var session: PackageInstaller.Session? = null
            try {
                val installer = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                val sessionId = installer.createSession(params)
                session = installer.openSession(sessionId)

                apk.inputStream().use { input ->
                    session.openWrite("teleopen.apk", 0, apk.length()).use { out ->
                        input.copyTo(out, 256 * 1024)
                        session.fsync(out)
                    }
                }

                // PendingIntent, по которому система пришлёт результат. На S+
                // (API 31) обязателен флаг mutable — система дописывает в Intent
                // свои extra (статус, confirm-Intent).
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                else
                    PendingIntent.FLAG_UPDATE_CURRENT
                val statusIntent = Intent(ACTION_INSTALL_STATUS).setPackage(packageName)
                val pi = PendingIntent.getBroadcast(this, sessionId, statusIntent, flags)

                session.commit(pi.intentSender)
                // Дальше результат прилетит в installResultReceiver.
            } catch (t: Throwable) {
                try { session?.abandon() } catch (_: Throwable) {}
                HysteriaTunVpnService.flogE("pkgInstaller", t.message ?: "?", t)
                finishInstall(false, "INSTALL_ERR",
                    "Не удалось начать установку: ${t.message}")
            } finally {
                try { session?.close() } catch (_: Throwable) {}
            }
        }.start()
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ресивер результатов PackageInstaller. RECEIVER_NOT_EXPORTED — статус
        // приходит только от системного PackageInstaller внутри нашего процесса.
        if (!installReceiverRegistered) {
            ContextCompat.registerReceiver(
                this,
                installResultReceiver,
                IntentFilter(ACTION_INSTALL_STATUS),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            installReceiverRegistered = true
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    HysteriaTunVpnService.eventSink = sink
                }
                override fun onCancel(args: Any?) {
                    HysteriaTunVpnService.eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)

                    // Hysteria2 → наш TUN сервис
                    "startVpn" -> {
                        val port    = call.argument<Int>("socks5Port") ?: 10900
                        val remark  = call.argument<String>("remark") ?: "TeleOpen"
                        val perApp  = call.argument<Boolean>("perAppEnabled") ?: false
                        val allowed = call.argument<List<String>>("allowedPackages") ?: emptyList()
                        val killSw  = call.argument<Boolean>("killSwitch") ?: false
                        requestPermissionAndStart(result,
                            HysteriaTunVpnService.ACTION_START_HYSTERIA,
                            remark = remark, port = port,
                            perAppEnabled = perApp, allowedPackages = allowed,
                            killSwitch = killSw)
                    }

                    // vless/vmess/trojan → наш TUN сервис с CoreController
                    "startV2RayVpn" -> {
                        val config  = call.argument<String>("config") ?: ""
                        val remark  = call.argument<String>("remark") ?: "TeleOpen"
                        val perApp  = call.argument<Boolean>("perAppEnabled") ?: false
                        val allowed = call.argument<List<String>>("allowedPackages") ?: emptyList()
                        val killSw  = call.argument<Boolean>("killSwitch") ?: false
                        requestPermissionAndStart(result,
                            HysteriaTunVpnService.ACTION_START_V2RAY,
                            remark = remark, config = config,
                            perAppEnabled = perApp, allowedPackages = allowed,
                            killSwitch = killSw)
                    }

                    "stopVpn" -> {
                        startService(Intent(this, HysteriaTunVpnService::class.java).apply {
                            action = HysteriaTunVpnService.ACTION_STOP
                        })
                        result.success("ok")
                    }

                    // Прочитать debug-лог VPN (последние ~50KB)
                    "getVpnLog" -> {
                        try {
                            val f = File(filesDir, "vpn_debug.log")
                            if (!f.exists()) {
                                result.success("(log file not found yet: ${f.absolutePath})")
                            } else {
                                val text = f.readText()
                                val tail = if (text.length > 50_000)
                                    "...[truncated]...\n" + text.substring(text.length - 50_000)
                                else text
                                result.success(tail)
                            }
                        } catch (e: Throwable) {
                            result.success("(error reading log: ${e.message})")
                        }
                    }

                    "clearVpnLog" -> {
                        try {
                            File(filesDir, "vpn_debug.log").delete()
                            result.success("ok")
                        } catch (e: Throwable) {
                            result.success("err: ${e.message}")
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                    // Расширения: mihomo/meta-style настройки, geo-файлы, тесты
                    // ═════════════════════════════════════════════════════════

                    "applyCoreConfig" -> {
                        try {
                            @Suppress("UNCHECKED_CAST")
                            val config = call.argument<Map<String, Any?>>("config") ?: emptyMap()
                            NativeExtensions.applyCoreConfig(this, config)
                            result.success(true)
                        } catch (e: Throwable) {
                            HysteriaTunVpnService.flogE("applyCoreConfig", e.message ?: "?", e)
                            result.success(false)
                        }
                    }

                    "importGeoFile" -> {
                        val kind = call.argument<String>("kind") ?: ""
                        // sourcePath игнорируем — открываем системный picker
                        if (kind.isEmpty()) {
                            result.success(null)
                        } else {
                            pendingGeoResult = result
                            pendingGeoKind = kind
                            try {
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "*/*"
                                }
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, GEO_FILE_PICK_REQUEST)
                            } catch (e: Throwable) {
                                pendingGeoResult = null
                                HysteriaTunVpnService.flogE("importGeoFile", e.message ?: "?", e)
                                result.success(null)
                            }
                        }
                    }

                    "runDnsLeakTest" -> {
                        // Тяжёлая работа — в IO потоке
                        Thread {
                            val res = try {
                                NativeExtensions.runDnsLeakTest()
                            } catch (e: Throwable) {
                                HysteriaTunVpnService.flogE("dnsLeak", e.message ?: "?", e)
                                emptyList()
                            }
                            runOnUiThread { result.success(res) }
                        }.start()
                    }

                    "runProxyVisibilityCheck" -> {
                        Thread {
                            val res = try {
                                NativeExtensions.runProxyVisibilityCheck()
                            } catch (e: Throwable) {
                                HysteriaTunVpnService.flogE("proxyVis", e.message ?: "?", e)
                                emptyList()
                            }
                            runOnUiThread { result.success(res) }
                        }.start()
                    }

                    // ═════════════════════════════════════════════════════════
                    // MTProto Proxy: открыть tg://proxy?... в Telegram/форке
                    // ═════════════════════════════════════════════════════════

                    // Открыть deep-link установки прокси в КОНКРЕТНОМ клиенте
                    // (package передан из Dart — пользователь выбрал форк).
                    "openProxyInApp" -> {
                        val url = call.argument<String>("url") ?: ""
                        val pkg = call.argument<String>("package") ?: ""
                        if (url.isEmpty() || pkg.isEmpty()) {
                            result.error("BAD_ARGS", "url и package обязательны", null)
                        } else if (!isAllowedProxyScheme(url)) {
                            // LOW-3: не пускаем произвольные схемы в ACTION_VIEW.
                            result.error("BAD_SCHEME", "Недопустимая схема ссылки", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                    setPackage(pkg)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success("ok")
                            } catch (e: android.content.ActivityNotFoundException) {
                                // Форк не обработал ссылку (удалён / нет intent-filter).
                                result.error("NO_ACTIVITY",
                                    "Приложение не смогло открыть ссылку", null)
                            } catch (e: Throwable) {
                                HysteriaTunVpnService.flogE("openProxyInApp", e.message ?: "?", e)
                                result.error("LAUNCH_FAILED", e.message, null)
                            }
                        }
                    }

                    // Открыть deep-link через системный chooser ("Открыть с
                    // помощью..."). createChooser форсирует диалог даже если
                    // у пользователя задано приложение по умолчанию.
                    "openProxyChooser" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (url.isEmpty()) {
                            result.error("BAD_ARGS", "url обязателен", null)
                        } else if (!isAllowedProxyScheme(url)) {
                            // LOW-3: валидируем схему перед ACTION_VIEW.
                            result.error("BAD_SCHEME", "Недопустимая схема ссылки", null)
                        } else {
                            try {
                                val view = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                val chooser = Intent.createChooser(view, "Открыть прокси в")
                                    .apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                                startActivity(chooser)
                                result.success("ok")
                            } catch (e: android.content.ActivityNotFoundException) {
                                result.error("NO_ACTIVITY",
                                    "Нет приложения для Telegram-ссылок", null)
                            } catch (e: Throwable) {
                                HysteriaTunVpnService.flogE("openProxyChooser", e.message ?: "?", e)
                                result.error("LAUNCH_FAILED", e.message, null)
                            }
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                    // Доверие: SHA-256 сертификата, которым подписан установленный APK.
                    // Позволяет юзеру сверить, что приложение подписано прод-ключом.
                    // ═════════════════════════════════════════════════════════

                    "getSigningCertSha256" -> {
                        try {
                            result.success(signingCertSha256())
                        } catch (t: Throwable) {
                            result.error("CERT_ERR", t.message, null)
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                    // In-app self-update: чтение версии и установка скачанного APK
                    // ═════════════════════════════════════════════════════════

                    "getAppVersionCode" -> {
                        try {
                            val info: PackageInfo = packageInfoCompat()
                            val code: Long =
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                                    info.longVersionCode
                                else
                                    @Suppress("DEPRECATION") info.versionCode.toLong()
                            // MethodChannel умеет передавать Int (32-битный); пока versionCode
                            // < 2 млрд (а это всегда), укладываемся. Бросаем как Int,
                            // чтобы на Dart-стороне получить int без сюрпризов.
                            result.success(code.toInt())
                        } catch (t: Throwable) {
                            result.error("VERSION_ERR", t.message, null)
                        }
                    }

                    "getAppVersionName" -> {
                        try {
                            result.success(packageInfoCompat().versionName ?: "")
                        } catch (t: Throwable) {
                            result.error("VERSION_ERR", t.message, null)
                        }
                    }

                    // Открыть системный диалог удаления НАШЕГО приложения.
                    // Нужен при конфликте подписи (смена keystore): юзер удаляет
                    // старую версию, затем ставит новую заново.
                    "uninstallSelf" -> {
                        try {
                            @Suppress("DEPRECATION")
                            val intent = Intent(
                                Intent.ACTION_DELETE,
                                Uri.parse("package:$packageName")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("UNINSTALL_ERR", t.message, null)
                        }
                    }

                    "installApk" -> {
                        try {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error(
                                    "ARG", "path required", null)
                            val file = File(path)
                            if (!file.exists()) {
                                return@setMethodCallHandler result.error(
                                    "NOFILE", "APK не найден: $path", null)
                            }

                            // Android 8+: нужно отдельное разрешение на установку
                            // из этого источника. Если его нет — открываем системный
                            // экран настроек именно для нашего пакета (одна галочка),
                            // и просим юзера повторить «Обновить» после согласия.
                            val canInstall =
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                                    packageManager.canRequestPackageInstalls()
                                else true

                            if (!canInstall) {
                                val settings = Intent(
                                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                try { startActivity(settings) } catch (_: Throwable) {}
                                return@setMethodCallHandler result.error(
                                    "NEED_PERMISSION",
                                    "Разрешите установку из этого источника и нажмите «Обновить» ещё раз",
                                    null
                                )
                            }

                            // Если уже идёт установка — не запускаем вторую.
                            if (pendingInstallResult != null) {
                                return@setMethodCallHandler result.error(
                                    "BUSY", "Установка уже выполняется", null)
                            }
                            // result разрешим позже — в installResultReceiver,
                            // когда система вернёт реальный итог установки.
                            pendingInstallResult = result
                            installViaPackageInstaller(file)
                        } catch (t: Throwable) {
                            HysteriaTunVpnService.flogE("installApk", t.message ?: "?", t)
                            finishInstall(false, "INSTALL_ERR", t.message)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Совместимый getPackageInfo для разных Android. */
    private fun packageInfoCompat(): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        else
            @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0)
    }

    /**
     * SHA-256 (hex, lowercase) сертификата, которым подписан установленный APK.
     * На API 28+ читаем через GET_SIGNING_CERTIFICATES (apkContentsSigners),
     * на старых — через устаревший GET_SIGNATURES.
     */
    /**
     * LOW-3: allowlist схем для deep-link прокси. url приходит из Dart и идёт в
     * ACTION_VIEW — без проверки можно было бы попросить открыть произвольную
     * intent-схему. Разрешаем только то, что реально нужно для прокси-ссылок.
     */
    private fun isAllowedProxyScheme(url: String): Boolean {
        val scheme = (Uri.parse(url).scheme ?: "").lowercase()
        return scheme in setOf(
            "tg", "https", "http",
            "socks", "socks5", "ss", "vless", "vmess", "trojan",
        )
    }

    private fun signingCertSha256(): String {
        val sig: ByteArray = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = packageManager.getPackageInfo(
                packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val signers = info.signingInfo?.apkContentsSigners
                ?: throw IllegalStateException("no signingInfo")
            if (signers.isEmpty()) throw IllegalStateException("no signers")
            signers[0].toByteArray()
        } else {
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageInfo(
                packageName, PackageManager.GET_SIGNATURES)
            @Suppress("DEPRECATION")
            val sigs = info.signatures ?: throw IllegalStateException("no signatures")
            if (sigs.isEmpty()) throw IllegalStateException("no signatures")
            sigs[0].toByteArray()
        }
        val digest = MessageDigest.getInstance("SHA-256").digest(sig)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun requestPermissionAndStart(
        result: MethodChannel.Result,
        action: String,
        remark: String = "",
        config: String = "",
        port: Int = 10900,
        perAppEnabled: Boolean = false,
        allowedPackages: List<String> = emptyList(),
        killSwitch: Boolean = false
    ) {
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            pendingResult = result
            pendingAction = action
            pendingRemark = remark
            pendingConfig = config
            pendingPort   = port
            pendingPerAppEnabled = perAppEnabled
            pendingAllowedPackages = allowedPackages
            pendingKillSwitch = killSwitch
            @Suppress("DEPRECATION")
            startActivityForResult(prepare, VPN_PERMISSION_REQUEST)
        } else {
            doStart(action, remark, config, port, perAppEnabled, allowedPackages, killSwitch)
            result.success("ok")
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            VPN_PERMISSION_REQUEST -> {
                val pending = pendingResult
                pendingResult = null
                if (resultCode == RESULT_OK) {
                    doStart(pendingAction, pendingRemark, pendingConfig, pendingPort,
                        pendingPerAppEnabled, pendingAllowedPackages, pendingKillSwitch)
                    pending?.success("ok")
                } else {
                    pending?.error("VPN_PERMISSION_DENIED", "Пользователь отказал", null)
                }
            }
            GEO_FILE_PICK_REQUEST -> {
                val pending = pendingGeoResult
                val kind = pendingGeoKind
                pendingGeoResult = null
                pendingGeoKind = ""
                if (resultCode == Activity.RESULT_OK && data?.data != null) {
                    val uri: Uri = data.data!!
                    Thread {
                        val savedPath = try {
                            NativeExtensions.copyGeoFile(this, uri, kind)
                        } catch (e: Throwable) {
                            HysteriaTunVpnService.flogE("geoImport", e.message ?: "?", e)
                            null
                        }
                        runOnUiThread { pending?.success(savedPath) }
                    }.start()
                } else {
                    pending?.success(null)
                }
            }
        }
    }

    private fun doStart(
        action: String, remark: String, config: String, port: Int,
        perAppEnabled: Boolean = false,
        allowedPackages: List<String> = emptyList(),
        killSwitch: Boolean = false
    ) {
        startService(Intent(this, HysteriaTunVpnService::class.java).apply {
            this.action = action
            putExtra(HysteriaTunVpnService.EXTRA_REMARK, remark)
            if (config.isNotEmpty()) putExtra(HysteriaTunVpnService.EXTRA_CONFIG, config)
            putExtra(HysteriaTunVpnService.EXTRA_SOCKS5_PORT, port)
            putExtra(HysteriaTunVpnService.EXTRA_PERAPP_ENABLED, perAppEnabled)
            putExtra(HysteriaTunVpnService.EXTRA_KILL_SWITCH, killSwitch)
            putStringArrayListExtra(
                HysteriaTunVpnService.EXTRA_ALLOWED_PACKAGES,
                ArrayList(allowedPackages)
            )
        })
    }

    override fun onDestroy() {
        if (installReceiverRegistered) {
            try { unregisterReceiver(installResultReceiver) } catch (_: Throwable) {}
            installReceiverRegistered = false
        }
        super.onDestroy()
    }
}
