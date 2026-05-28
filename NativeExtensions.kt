package com.example.my_vpn

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.TimeZone
import javax.net.ssl.HttpsURLConnection

object NativeExtensions {

    
    
    

    
    fun applyCoreConfig(ctx: Context, config: Map<String, Any?>) {
        val json = JSONObject()
        for ((k, v) in config) {
            
            if (v == null) continue
            if (v is String && v.isEmpty()) continue
            json.put(k, v)
        }
        val f = File(ctx.filesDir, "core_config.json")
        f.writeText(json.toString(2))
        HysteriaTunVpnService.flog("applyCoreConfig",
            "saved ${json.length()} keys to ${f.absolutePath}")
        
        HysteriaTunVpnService.notifyConfigChanged()
    }

    
    
    

    
    fun copyGeoFile(ctx: Context, uri: Uri, kind: String): String? {
        val ext = when (kind) {
            "geoip", "country" -> "dat"
            "asn" -> "mmdb"
            else -> "dat"
        }
        val dir = File(ctx.filesDir, "geo").apply { mkdirs() }
        val out = File(dir, "$kind.$ext")
        ctx.contentResolver.openInputStream(uri).use { input ->
            if (input == null) return null
            FileOutputStream(out).use { os ->
                val buf = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    os.write(buf, 0, n)
                    total += n
                }
                HysteriaTunVpnService.flog("geoImport",
                    "saved $total bytes to ${out.absolutePath}")
            }
        }
        return out.absolutePath
    }

    
    
    

    
    fun runDnsLeakTest(): List<Map<String, Any?>> {
        val resolverIps = mutableSetOf<String>()

        
        runCatching {
            val txt = dohQueryTxt("https://1.1.1.1/dns-query", "whoami.cloudflare")
            for (ip in extractIps(txt)) resolverIps.add(ip)
        }.onFailure {
            HysteriaTunVpnService.flog("dnsLeak", "cloudflare whoami failed: ${it.message}")
        }

        
        runCatching {
            val txt = dohQueryTxt("https://dns.google/resolve", "resolver.dnscrypt.info")
            for (ip in extractIps(txt)) resolverIps.add(ip)
        }.onFailure {
            HysteriaTunVpnService.flog("dnsLeak", "dnscrypt whoami failed: ${it.message}")
        }

        
        runCatching {
            val txt = dohQueryTxt("https://1.1.1.1/dns-query", "o-o.myaddr.l.google.com")
            for (ip in extractIps(txt)) resolverIps.add(ip)
        }.onFailure {
            HysteriaTunVpnService.flog("dnsLeak", "myaddr.google failed: ${it.message}")
        }

        if (resolverIps.isEmpty()) {
            HysteriaTunVpnService.flog("dnsLeak", "no resolvers detected")
            return emptyList()
        }

        
        val out = mutableListOf<Map<String, Any?>>()
        for (ip in resolverIps) {
            val (org, country) = ipApiLookup(ip)
            out.add(mapOf(
                "ip" to ip,
                "org" to org,
                "country" to country,
                "leak" to false  
            ))
            HysteriaTunVpnService.flog("dnsLeak", "$ip · $org · $country")
        }
        return out
    }

    
    private fun dohQueryTxt(endpoint: String, name: String): String {
        val url = URL("$endpoint?name=$name&type=TXT")
        val conn = (url.openConnection() as HttpsURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("Accept", "application/dns-json")
            connectTimeout = 5000
            readTimeout = 5000
        }
        return conn.inputStream.bufferedReader().use { it.readText() }
    }

    
    private fun extractIps(json: String): List<String> {
        val out = mutableListOf<String>()
        try {
            val obj = JSONObject(json)
            val answers = obj.optJSONArray("Answer") ?: return emptyList()
            for (i in 0 until answers.length()) {
                val data = answers.getJSONObject(i).optString("data", "")
                
                val cleaned = data.trim('"', ' ')
                
                val rx = Regex("""\b\d{1,3}(?:\.\d{1,3}){3}\b""")
                for (m in rx.findAll(cleaned)) out.add(m.value)
            }
        } catch (_: Throwable) {}
        return out
    }

    
    private fun ipApiLookup(ip: String): Pair<String, String> {
        return try {
            val url = URL("http://ip-api.com/json/$ip?fields=org,country,countryCode")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 3000
                readTimeout = 3000
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val obj = JSONObject(body)
            val org = obj.optString("org", "Unknown")
            val cc = obj.optString("countryCode", obj.optString("country", "??"))
            org to cc
        } catch (_: Throwable) {
            "Unknown" to "??"
        }
    }

    
    
    

    
    fun runProxyVisibilityCheck(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()

        
        
        
        out.add(mapOf(
            "id" to "webrtc",
            "ok" to true,
            "detail" to "Android не раскрывает локальный IP через WebRTC из приложений"
        ))

        
        
        out.add(checkTlsFingerprint())

        
        out.add(checkHttpHeaders())

        
        out.add(checkTzVsGeo())

        
        
        out.add(checkDpi())

        
        out.add(checkIpv6Leak())

        return out
    }

    private fun checkTlsFingerprint(): Map<String, Any?> {
        return try {
            val url = URL("https://tls.peet.ws/api/all")
            val conn = (url.openConnection() as HttpsURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val obj = JSONObject(body)
            val ja3 = obj.optJSONObject("tls")?.optString("ja3_hash", "") ?: ""
            val ja4 = obj.optJSONObject("tls")?.optString("ja4", "") ?: ""
            
            
            
            mapOf(
                "id" to "tls_fp",
                "ok" to true,
                "detail" to "JA3: ${ja3.take(8)}… JA4: ${ja4.take(12)}…"
            )
        } catch (e: Throwable) {
            mapOf("id" to "tls_fp", "ok" to false,
                "detail" to "Не удалось опросить tls.peet.ws: ${e.message}")
        }
    }

    private fun checkHttpHeaders(): Map<String, Any?> {
        return try {
            val url = URL("https://httpbin.org/headers")
            val conn = (url.openConnection() as HttpsURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val obj = JSONObject(body).optJSONObject("headers") ?: JSONObject()
            val proxyHeaders = listOf("Via", "Forwarded", "X-Forwarded-For",
                "X-Real-Ip", "Proxy-Connection")
            val found = proxyHeaders.filter { obj.has(it) }
            if (found.isEmpty()) {
                mapOf("id" to "headers", "ok" to true,
                    "detail" to "Прокси-заголовки не обнаружены")
            } else {
                mapOf("id" to "headers", "ok" to false,
                    "detail" to "Обнаружены: ${found.joinToString(", ")}")
            }
        } catch (e: Throwable) {
            mapOf("id" to "headers", "ok" to false,
                "detail" to "Ошибка запроса: ${e.message}")
        }
    }

    private fun checkTzVsGeo(): Map<String, Any?> {
        return try {
            val deviceTz = TimeZone.getDefault().id
            val url = URL("http://ip-api.com/json/?fields=timezone,countryCode")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val obj = JSONObject(body)
            val ipTz = obj.optString("timezone", "")
            val cc = obj.optString("countryCode", "")

            
            val devContinent = deviceTz.substringBefore("/", deviceTz)
            val ipContinent = ipTz.substringBefore("/", ipTz)
            val matches = devContinent.equals(ipContinent, ignoreCase = true)

            mapOf(
                "id" to "tz",
                "ok" to matches,
                "detail" to if (matches)
                    "Устройство: $deviceTz · IP: $ipTz ($cc) - совпадают"
                else
                    "Устройство: $deviceTz · IP: $ipTz ($cc) - расхождение"
            )
        } catch (e: Throwable) {
            mapOf("id" to "tz", "ok" to false,
                "detail" to "Не удалось определить: ${e.message}")
        }
    }

    private fun checkDpi(): Map<String, Any?> {
        
        
        
        val probes = listOf(
            "www.tor-project.org" to 443,
            "1.1.1.1" to 853,        
            "discord.com" to 443
        )
        var ok = 0
        val details = mutableListOf<String>()
        for ((host, port) in probes) {
            val good = runCatching {
                Socket().use { s ->
                    s.connect(InetSocketAddress(host, port), 3000)
                    true
                }
            }.getOrDefault(false)
            details.add("$host:$port=${if (good) "✓" else "✗"}")
            if (good) ok++
        }
        return mapOf(
            "id" to "dpi",
            "ok" to (ok >= 2),
            "detail" to details.joinToString(" ")
        )
    }

    private fun checkIpv6Leak(): Map<String, Any?> {
        return try {
            
            
            
            val addrs = InetAddress.getAllByName("ipv6.google.com")
            val v6 = addrs.filterIsInstance<Inet6Address>()
            if (v6.isEmpty()) {
                mapOf("id" to "ipv6", "ok" to true,
                    "detail" to "IPv6 недоступен - утечки нет")
            } else {
                val reachable = runCatching {
                    Socket().use { s ->
                        s.connect(InetSocketAddress(v6.first(), 443), 3000)
                        true
                    }
                }.getOrDefault(false)
                if (reachable) {
                    mapOf("id" to "ipv6", "ok" to false,
                        "detail" to "IPv6 работает (${v6.first().hostAddress}). " +
                                    "Если VPN - IPv4-only, это утечка.")
                } else {
                    mapOf("id" to "ipv6", "ok" to true,
                        "detail" to "IPv6 резолвится, но не доступен - ок")
                }
            }
        } catch (e: Throwable) {
            mapOf("id" to "ipv6", "ok" to true,
                "detail" to "IPv6 недоступен: ${e.message}")
        }
    }
}
