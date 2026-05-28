package com.example.my_vpn

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL         = "com.example.my_vpn/native"
        const val EVENT_CHANNEL          = "com.example.my_vpn/vpn_status"
        const val VPN_PERMISSION_REQUEST = 1001
        const val GEO_FILE_PICK_REQUEST  = 1002
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingAction: String = ""
    private var pendingConfig: String = ""
    private var pendingRemark: String = ""
    private var pendingPort: Int = 10900
    private var pendingPerAppEnabled: Boolean = false
    private var pendingAllowedPackages: List<String> = emptyList()

    
    private var pendingGeoResult: MethodChannel.Result? = null
    private var pendingGeoKind: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

                    
                    "startVpn" -> {
                        val port    = call.argument<Int>("socks5Port") ?: 10900
                        val remark  = call.argument<String>("remark") ?: "TeleOpen"
                        val perApp  = call.argument<Boolean>("perAppEnabled") ?: false
                        val allowed = call.argument<List<String>>("allowedPackages") ?: emptyList()
                        requestPermissionAndStart(result,
                            HysteriaTunVpnService.ACTION_START_HYSTERIA,
                            remark = remark, port = port,
                            perAppEnabled = perApp, allowedPackages = allowed)
                    }

                    
                    "startV2RayVpn" -> {
                        val config  = call.argument<String>("config") ?: ""
                        val remark  = call.argument<String>("remark") ?: "TeleOpen"
                        val perApp  = call.argument<Boolean>("perAppEnabled") ?: false
                        val allowed = call.argument<List<String>>("allowedPackages") ?: emptyList()
                        requestPermissionAndStart(result,
                            HysteriaTunVpnService.ACTION_START_V2RAY,
                            remark = remark, config = config,
                            perAppEnabled = perApp, allowedPackages = allowed)
                    }

                    "stopVpn" -> {
                        startService(Intent(this, HysteriaTunVpnService::class.java).apply {
                            action = HysteriaTunVpnService.ACTION_STOP
                        })
                        result.success("ok")
                    }

                    
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

                    
                    
                    

                    
                    
                    "openProxyInApp" -> {
                        val url = call.argument<String>("url") ?: ""
                        val pkg = call.argument<String>("package") ?: ""
                        if (url.isEmpty() || pkg.isEmpty()) {
                            result.error("BAD_ARGS", "url и package обязательны", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                    setPackage(pkg)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success("ok")
                            } catch (e: android.content.ActivityNotFoundException) {
                                
                                result.error("NO_ACTIVITY",
                                    "Приложение не смогло открыть ссылку", null)
                            } catch (e: Throwable) {
                                HysteriaTunVpnService.flogE("openProxyInApp", e.message ?: "?", e)
                                result.error("LAUNCH_FAILED", e.message, null)
                            }
                        }
                    }

                    
                    
                    
                    "openProxyChooser" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (url.isEmpty()) {
                            result.error("BAD_ARGS", "url обязателен", null)
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

                    else -> result.notImplemented()
                }
            }
    }

    private fun requestPermissionAndStart(
        result: MethodChannel.Result,
        action: String,
        remark: String = "",
        config: String = "",
        port: Int = 10900,
        perAppEnabled: Boolean = false,
        allowedPackages: List<String> = emptyList()
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
            @Suppress("DEPRECATION")
            startActivityForResult(prepare, VPN_PERMISSION_REQUEST)
        } else {
            doStart(action, remark, config, port, perAppEnabled, allowedPackages)
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
                        pendingPerAppEnabled, pendingAllowedPackages)
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
        allowedPackages: List<String> = emptyList()
    ) {
        startService(Intent(this, HysteriaTunVpnService::class.java).apply {
            this.action = action
            putExtra(HysteriaTunVpnService.EXTRA_REMARK, remark)
            if (config.isNotEmpty()) putExtra(HysteriaTunVpnService.EXTRA_CONFIG, config)
            putExtra(HysteriaTunVpnService.EXTRA_SOCKS5_PORT, port)
            putExtra(HysteriaTunVpnService.EXTRA_PERAPP_ENABLED, perAppEnabled)
            putStringArrayListExtra(
                HysteriaTunVpnService.EXTRA_ALLOWED_PACKAGES,
                ArrayList(allowedPackages)
            )
        })
    }
}
