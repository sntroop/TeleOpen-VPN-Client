package com.example.my_vpn

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

        const val ACTION_START_HYSTERIA = "com.example.my_vpn.START_HYSTERIA"
        const val ACTION_START_V2RAY    = "com.example.my_vpn.START_V2RAY"
        const val ACTION_STOP           = "com.example.my_vpn.STOP_VPN"

        const val EXTRA_CONFIG      = "config"
        const val EXTRA_REMARK      = "remark"
        const val EXTRA_SOCKS5_PORT = "socks5_port"
        const val EXTRA_PERAPP_ENABLED  = "perapp_enabled"
        const val EXTRA_ALLOWED_PACKAGES = "allowed_packages"

        const val NOTIF_CHANNEL = "vpn_tun_channel"
        const val NOTIF_ID      = 7777

        @Volatile var eventSink: EventChannel.EventSink? = null

        fun pushStatus(status: String) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(status)
            }
        }

        
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

        
        fun notifyConfigChanged() {
            flog("config", "core_config.json changed - will be picked up on next start")
        }

        
        fun loadCoreConfig(ctx: android.content.Context): JSONObject {
            return try {
                val f = File(ctx.filesDir, "core_config.json")
                if (f.exists()) JSONObject(f.readText()) else JSONObject()
            } catch (e: Throwable) {
                flogE("config", "loadCoreConfig failed: ${e.message}", e)
                JSONObject()
            }
        }

        
        fun extractDnsIp(raw: String): String? {
            if (raw.isEmpty()) return null
            
            val noScheme = raw.replace(Regex("""^[a-z]+://"""), "")
            
            val host = noScheme.substringBefore("/").substringBefore(":")
            return if (host.matches(Regex("""^\d{1,3}(\.\d{1,3}){3}$"""))) host else null
        }

        
        
        @Volatile private var logFile: File? = null
        private val logLock = Any()

        fun initFileLog(ctx: android.content.Context) {
            try {
                val f = File(ctx.filesDir, "vpn_debug.log")
                
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

    
    private var tunInterface: ParcelFileDescriptor? = null
    
    private var v2rayDetachedFd: Int = -1

    private var tun2socksProcess: Process? = null
    private var coreController: CoreController? = null
    private var isRunning = false
    
    
    
    @Volatile private var starting = false
    private var mode: String = ""  

    
    private var perAppEnabled: Boolean = false
    private var allowedPackages: List<String> = emptyList()

    
    private var statsThread: Thread? = null
    @Volatile private var statsRunning: Boolean = false
    private var statsBaselineRx: Long = -1L
    private var statsBaselineTx: Long = -1L
    private var statsLastRx: Long = 0L
    private var statsLastTx: Long = 0L
    private var statsLastTickMs: Long = 0L

    

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        initFileLog(this)
        flog(TAG, "=== onStartCommand action=${intent?.action} flags=$flags startId=$startId ===")
        flog(TAG, "log file: ${File(filesDir, "vpn_debug.log").absolutePath}")

        
        
        
        
        if (intent?.action == null ||
            (intent.action != ACTION_STOP &&
             intent.action != ACTION_START_V2RAY &&
             intent.action != ACTION_START_HYSTERIA)) {
            flog(TAG, "no usable action - satisfying FGS contract then stopping")
            try { startVpnForeground("TeleOpen") } catch (t: Throwable) {
                flogE(TAG, "fallback startForeground failed: ${t.message}", t)
            }
            stopVpn()
            return START_NOT_STICKY
        }

        if (intent.action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }

        
        
        
        
        if (starting) {
            flog(TAG, "start already in progress - ignoring duplicate onStartCommand")
            return START_NOT_STICKY
        }
        starting = true

        perAppEnabled = intent.getBooleanExtra(EXTRA_PERAPP_ENABLED, false)
        allowedPackages = intent.getStringArrayListExtra(EXTRA_ALLOWED_PACKAGES) ?: emptyList()
        flog(TAG, "perApp enabled=$perAppEnabled pkgs=${allowedPackages.size}")

        
        
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

        
        
        
        
        
        val action = intent.action!!
        val config = intent.getStringExtra(EXTRA_CONFIG) ?: ""
        val port   = intent.getIntExtra(EXTRA_SOCKS5_PORT, 10900)
        Thread({
            try {
                when (action) {
                    ACTION_START_V2RAY    -> startV2Ray(config, remark)
                    ACTION_START_HYSTERIA -> startHysteria(port, remark)
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

    

    private fun startHysteria(socks5Port: Int, remark: String) {
        Log.i(TAG, "startHysteria port=$socks5Port")
        stopInternals()
        
        try { Thread.sleep(600) } catch (_: InterruptedException) {}
        mode = "hysteria"

        
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

    

    private fun startV2Ray(rawConfig: String, remark: String) {
        flog(TAG, "startV2Ray BEGIN remark=$remark configLen=${rawConfig.length}")
        stopInternals()
        
        
        
        try { Thread.sleep(600) } catch (_: InterruptedException) {}
        flog(TAG, "stopInternals settle done, proceeding with new start")
        mode = "v2ray"

        if (rawConfig.isBlank()) {
            flogE(TAG, "empty config")
            pushStatus("STOPPED"); stopSelf(); return
        }

        var pfd: ParcelFileDescriptor? = null
        try {
            
            val config = ensureTunInbound(rawConfig)
            flog(TAG, "config after ensureTunInbound, len=${config.length}")
            
            flog(TAG, "=== CONFIG START ===")
            config.chunked(500).forEach { flog(TAG, it) }
            flog(TAG, "=== CONFIG END ===")

            
            flog(TAG, "CHECKPOINT: buildTunInterface start")
            pfd = buildTunInterface(remark) ?: run {
                flogE(TAG, "buildTunInterface returned null (no VPN permission?)")
                pushStatus("STOPPED"); stopSelf(); return
            }
            flog(TAG, "VpnService.Builder.establish() OK, pfd=$pfd")

            flog(TAG, "CHECKPOINT: detachFd start")
            val fd = pfd.detachFd()
            pfd = null
            v2rayDetachedFd = fd
            flog(TAG, "TUN detachedFd=$fd")

            
            flog(TAG, "CHECKPOINT: initCoreEnv start")
            try {
                val assetsDir = filesDir.absolutePath
                flog(TAG, "calling initCoreEnv(env=$assetsDir, key=$assetsDir)")
                Libv2ray.initCoreEnv(assetsDir, assetsDir)
                flog(TAG, "initCoreEnv OK")
            } catch (t: Throwable) {
                flogE(TAG, "initCoreEnv threw: ${t.javaClass.simpleName}", t)
            }

            
            flog(TAG, "CHECKPOINT: checkVersionX start")
            try {
                val v = Libv2ray.checkVersionX()
                flog(TAG, "xray version: $v")
            } catch (t: Throwable) {
                flogE(TAG, "checkVersionX threw", t)
            }

            
            flog(TAG, "CHECKPOINT: newCoreController start")
            val ctrl = Libv2ray.newCoreController(object : CoreCallbackHandler {
                override fun startup(): Long {
                    flog(TAG, "callback.startup()")
                    return 0L
                }

                override fun shutdown(): Long {
                    flog(TAG, "callback.shutdown() - xray просит выключения")
                    if (isRunning) {
                        pushStatus("STOPPED")
                        stopSelf()
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

            
            flog(TAG, "CHECKPOINT: startLoop fd=$fd config_len=${config.length}")
            ctrl.startLoop(config, fd)
            flog(TAG, "ctrl.startLoop returned, isRunning=${ctrl.isRunning}")

            if (!ctrl.isRunning) {
                flogE(TAG, "ctrl.isRunning=false after startLoop - xray не стартанул")
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
            flog(TAG, "closeDetachedFd: сбрасываем fd=$v2rayDetachedFd (xray закроет сам)")
            v2rayDetachedFd = -1
        }
    }

    
    private fun ensureTunInbound(raw: String): String {
        return try {
            val root = JSONObject(raw)
            val cfg = loadCoreConfig(this)

            
            val destOverride = JSONArray()
            val httpOver = cfg.optString("meta_sniff_http_override", "")
            val tlsOver  = cfg.optString("meta_sniff_tls_override", "")
            val quicOver = cfg.optString("meta_sniff_quic_override", "")
            
            
            if (httpOver != "Выключить") destOverride.put("http")
            if (tlsOver  != "Выключить") destOverride.put("tls")
            if (quicOver == "Включить")  destOverride.put("quic")
            if (cfg.optBoolean("packet_analysis", true) && destOverride.length() == 0) {
                destOverride.put("http").put("tls")
            }

            val sniffingObj = JSONObject()
                .put("enabled", destOverride.length() > 0)
                .put("destOverride", destOverride)
            
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

            
            val inbounds = root.optJSONArray("inbounds") ?: JSONArray().also { root.put("inbounds", it) }
            var hasTun = false
            for (i in 0 until inbounds.length()) {
                val inb = inbounds.optJSONObject(i) ?: continue
                if (inb.optString("protocol").equals("tun", ignoreCase = true)) {
                    hasTun = true
                    
                    inb.put("sniffing", sniffingObj)
                    break
                }
                
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

            
            val dnsRemote = cfg.optString("dns_remote", "")
            val dnsDirect = cfg.optString("dns_direct", "")
            if (dnsRemote.isNotEmpty() || dnsDirect.isNotEmpty()) {
                val dns = root.optJSONObject("dns") ?: JSONObject()
                val servers = JSONArray()
                if (dnsRemote.isNotEmpty()) servers.put(dnsRemote)
                if (dnsDirect.isNotEmpty()) servers.put(dnsDirect)
                dns.put("servers", servers)
                
                if (cfg.optBoolean("dns_fake", false)) {
                    dns.put("queryStrategy", "UseIP")
                }
                root.put("dns", dns)
                flog(TAG, "DNS block merged: remote=$dnsRemote direct=$dnsDirect")
            }

            
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

    

    private fun stopVpn() {
        Log.i(TAG, "stopVpn")
        starting = false
        stopStatsReporter()
        stopInternals()
        pushStatus("STOPPED")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopInternals() {
        isRunning = false

        
        try { coreController?.stopLoop() } catch (e: Exception) { Log.w(TAG, "stopLoop: $e") }
        coreController = null

        
        try { tun2socksProcess?.destroy() } catch (_: Exception) {}
        tun2socksProcess = null

        
        closeDetachedFd()
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null

        mode = ""
    }

    

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
                
                .setBlocking(mode == "v2ray")
                .setConfigureIntent(stopPi)

            
            
            
            
            
            
            if (perAppEnabled && allowedPackages.isNotEmpty()) {
                var added = 0
                for (pkg in allowedPackages) {
                    if (pkg == packageName) continue  
                    try {
                        builder.addAllowedApplication(pkg)
                        added++
                    } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                        flog(TAG, "perApp: package not found, skip: $pkg")
                    }
                }
                flog(TAG, "perApp: allowed apps added=$added (of ${allowedPackages.size})")
            } else {
                
                
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                    flog(TAG, "self disallow failed: ${e.message}")
                }
            }

            
            
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

            
            val routeSystem = cfg.optBoolean("net_route_system", true)
            val bypassPrivate = cfg.optBoolean("net_bypass_private", false)

            if (routeSystem) {
                if (bypassPrivate && android.os.Build.VERSION.SDK_INT >= 33) {
                    builder.addRoute("0.0.0.0", 0)
                    try {
                        
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
                flog(TAG, "TUN: route_system=false - only allowed apps go through VPN")
            }

            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "buildTun error: $e"); null
        }
    }

    

    
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
}
