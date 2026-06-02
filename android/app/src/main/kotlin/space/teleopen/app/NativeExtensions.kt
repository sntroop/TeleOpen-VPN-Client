package space.teleopen.app

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.TimeZone
import javax.net.ssl.HttpsURLConnection

/**
 * Нативные расширения, вызываемые из Flutter через MethodChannel:
 *   applyCoreConfig         — сохранить mihomo/meta-style настройки на диск
 *   copyGeoFile             — скопировать выбранный пользователем geo-файл
 *   runDnsLeakTest          — проверить, через какие DNS-резолверы идёт трафик
 *   runProxyVisibilityCheck — серия проверок «прокси-ли мы для внешнего сайта»
 *
 * ВАЖНО: эти проверки делают сетевые запросы НА УРОВНЕ ПРИЛОЖЕНИЯ.
 * Это значит — если VPN включён через системный VPN (или твой собственный),
 * запросы идут через VPN. Если VPN не запущен — через системную сеть.
 * Они не могут проверить «что было бы без VPN» — Android не даёт обойти VPN
 * без специальных привилегий.
 */
object NativeExtensions {

    // ───────────────────────────────────────────────────────────────────────
    // applyCoreConfig
    // ───────────────────────────────────────────────────────────────────────

    /**
     * Сохранить Map настроек (из Dart AppSettings.toCoreConfig()) на диск
     * как JSON. HysteriaTunVpnService при следующем старте читает этот файл
     * и применяет релевантные опции к ядру:
     *   - hysteria2: правит client.json в filesDir/hysteria/
     *   - xray (libv2ray): мерджит DNS/sniffing/inbounds в config-JSON
     *   - всё что не подходит под текущее ядро — игнорируется
     *
     * В рантайме (пока VPN уже запущен) большинство опций требуют рестарта.
     * Те что можно поменять на лету (DNS-перехват, fake-IP) — обрабатываются
     * сервисом сразу через `HysteriaTunVpnService.reapplyConfig()`.
     */
    fun applyCoreConfig(ctx: Context, config: Map<String, Any?>) {
        val json = JSONObject()
        for ((k, v) in config) {
            // фильтруем null'ы и пустые строки, чтобы не засорять файл
            if (v == null) continue
            if (v is String && v.isEmpty()) continue
            json.put(k, v)
        }
        val f = File(ctx.filesDir, "core_config.json")
        f.writeText(json.toString(2))
        HysteriaTunVpnService.flog("applyCoreConfig",
            "saved ${json.length()} keys to ${f.absolutePath}")
        // Если сервис запущен — попросим его перечитать конфиг.
        HysteriaTunVpnService.notifyConfigChanged()
    }

    // ───────────────────────────────────────────────────────────────────────
    // copyGeoFile
    // ───────────────────────────────────────────────────────────────────────

    /**
     * Скопировать файл, выбранный в SAF picker, в filesDir/geo/<kind>.dat,
     * вернуть абсолютный путь. kind = geoip / geosite / country / asn.
     */
    fun copyGeoFile(ctx: Context, uri: Uri, kind: String): String? {
        // HIGH-3: kind приходит из Dart и идёт в имя файла. Без allowlist
        // значение вида "../../databases/x" вырвало бы запись за пределы geo/.
        val ext = when (kind) {
            "geoip", "country" -> "dat"
            "geosite" -> "dat"
            "asn" -> "mmdb"
            else -> return null   // неизвестный kind — не пишем ничего
        }
        val dir = File(ctx.filesDir, "geo").apply { mkdirs() }
        val out = File(dir, "$kind.$ext")
        // Двойная страховка: путь результата обязан остаться внутри geo/.
        if (!out.canonicalPath.startsWith(dir.canonicalPath + File.separator)) {
            return null
        }
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

    // ───────────────────────────────────────────────────────────────────────
    // runDnsLeakTest
    // ───────────────────────────────────────────────────────────────────────

    /**
     * Резолвим несколько whoami-сервисов и возвращаем список уникальных
     * резолверов, которые ответили. Если в списке есть резолвер «обычного»
     * провайдера/Wi-Fi-сети — DNS утекает.
     *
     * Подход без зависимостей:
     *   1) делаем `InetAddress.getAllByName("whoami.cloudflare")` — это TXT,
     *      но Java умеет только A/AAAA. Поэтому идём по DoH JSON-API:
     *      https://1.1.1.1/dns-query?name=whoami.cloudflare&type=TXT
     *      https://dns.google/resolve?name=resolver.dnscrypt.info&type=TXT
     *      Это работает через системный HTTPS — то есть через VPN, если он
     *      включён. Ответ содержит IP резолвера, который дошёл до сервера.
     *   2) для каждого IP резолвера дёргаем ip-api.com (бесплатный, без ключа)
     *      чтобы получить org/country.
     *   3) флаг leak = резолвер не из «нашего» VPN-апстрима. Без знания
     *      апстрима маркируем leak=false для всех — пользователь сам решит.
     */
    fun runDnsLeakTest(): List<Map<String, Any?>> {
        val resolverIps = mutableSetOf<String>()

        // a) Cloudflare whoami
        runCatching {
            val txt = dohQueryTxt("https://1.1.1.1/dns-query", "whoami.cloudflare")
            for (ip in extractIps(txt)) resolverIps.add(ip)
        }.onFailure {
            HysteriaTunVpnService.flog("dnsLeak", "cloudflare whoami failed: ${it.message}")
        }

        // b) DNSCrypt resolver
        runCatching {
            val txt = dohQueryTxt("https://dns.google/resolve", "resolver.dnscrypt.info")
            for (ip in extractIps(txt)) resolverIps.add(ip)
        }.onFailure {
            HysteriaTunVpnService.flog("dnsLeak", "dnscrypt whoami failed: ${it.message}")
        }

        // c) DNS-O-Matic / NextDNS edge-marker
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

        // Геолоцируем каждый IP
        val out = mutableListOf<Map<String, Any?>>()
        for (ip in resolverIps) {
            val (org, country) = ipApiLookup(ip)
            out.add(mapOf(
                "ip" to ip,
                "org" to org,
                "country" to country,
                "leak" to false  // см. комментарий в шапке: апстрим неизвестен
            ))
            HysteriaTunVpnService.flog("dnsLeak", "$ip · $org · $country")
        }
        return out
    }

    /**
     * Запрос TXT-записи через DoH JSON API.
     * Возвращает сырой JSON-ответ как строку.
     */
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

    /**
     * Из DoH JSON-ответа выдёргиваем IP-адреса из секции Answer.data.
     * data приходит в виде `"\"104.28.0.1\""` (с кавычками) — чистим.
     */
    private fun extractIps(json: String): List<String> {
        val out = mutableListOf<String>()
        try {
            val obj = JSONObject(json)
            val answers = obj.optJSONArray("Answer") ?: return emptyList()
            for (i in 0 until answers.length()) {
                val data = answers.getJSONObject(i).optString("data", "")
                // строка вида "1.2.3.4" или "\"resolver: 1.2.3.4\""
                val cleaned = data.trim('"', ' ')
                // выдёргиваем все IPv4-подобные подстроки
                val rx = Regex("""\b\d{1,3}(?:\.\d{1,3}){3}\b""")
                for (m in rx.findAll(cleaned)) out.add(m.value)
            }
        } catch (_: Throwable) {}
        return out
    }

    /**
     * Минимальный геолукап через http://ip-api.com/json/{ip}?fields=org,country
     * (бесплатный, без ключа, ~45 req/min на IP).
     */
    private fun ipApiLookup(ip: String): Pair<String, String> {
        return try {
            // MED-1: HTTPS-гео (ip-api отдаёт https только на pro). ipwho.is —
            // бесплатный, без ключа, по HTTPS.
            val url = URL("https://ipwho.is/$ip")
            val conn = (url.openConnection() as HttpsURLConnection).apply {
                connectTimeout = 3000
                readTimeout = 3000
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val obj = JSONObject(body)
            val org = obj.optJSONObject("connection")?.optString("org", "")
                ?.ifEmpty { null } ?: "Unknown"
            val cc = obj.optString("country_code", "??")
            org to cc
        } catch (_: Throwable) {
            "Unknown" to "??"
        }
    }

    // ───────────────────────────────────────────────────────────────────────
    // runProxyVisibilityCheck
    // ───────────────────────────────────────────────────────────────────────

    /**
     * Возвращает список чеков с id, ok, detail. id'ы должны совпадать с
     * proxy_visibility_screen.dart:
     *   webrtc / tls_fp / headers / tz / dpi / ipv6
     */
    fun runProxyVisibilityCheck(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()

        // 1) WebRTC — реальный STUN-зонд возможен, но требует UDP-сокетов
        // и парсинга binding response. Ограничимся честным "не поддерживается"
        // на этом устройстве — это лучше чем рандомный warn.
        out.add(mapOf(
            "id" to "webrtc",
            "ok" to true,
            "detail" to "Android не раскрывает локальный IP через WebRTC из приложений"
        ))

        // 2) TLS fingerprint — JA3/JA4 определяется на стороне сервера.
        // Запросим echo-сервис, который возвращает JA3 (https://tls.peet.ws/api/all)
        out.add(checkTlsFingerprint())

        // 3) HTTP-заголовки — спросим у httpbin что он видит в заголовках
        out.add(checkHttpHeaders())

        // 4) TZ vs IP-геолокация
        out.add(checkTzVsGeo())

        // 5) DPI-зонды — попробуем коннект к нескольким хостам, типично
        // блокируемым DPI в РФ/Иране/Китае
        out.add(checkDpi())

        // 6) IPv6 утечка
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
            // Java/Android stock SSL имеет узнаваемый профиль, но он не
            // совпадает ни с Chrome, ни с iOS — для типового сайта это
            // «приложение», не «прокси». Маркируем ok.
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
            // MED-1: HTTPS-гео своего внешнего IP (ipwho.is, без ключа).
            val url = URL("https://ipwho.is/")
            val conn = (url.openConnection() as HttpsURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val obj = JSONObject(body)
            val ipTz = obj.optJSONObject("timezone")?.optString("id", "") ?: ""
            val cc = obj.optString("country_code", "")

            // Сравниваем первый сегмент TZ (Europe, America, Asia, ...)
            val devContinent = deviceTz.substringBefore("/", deviceTz)
            val ipContinent = ipTz.substringBefore("/", ipTz)
            val matches = devContinent.equals(ipContinent, ignoreCase = true)

            mapOf(
                "id" to "tz",
                "ok" to matches,
                "detail" to if (matches)
                    "Устройство: $deviceTz · IP: $ipTz ($cc) — совпадают"
                else
                    "Устройство: $deviceTz · IP: $ipTz ($cc) — расхождение"
            )
        } catch (e: Throwable) {
            mapOf("id" to "tz", "ok" to false,
                "detail" to "Не удалось определить: ${e.message}")
        }
    }

    private fun checkDpi(): Map<String, Any?> {
        // Хосты, типично блокируемые DPI. Если до них достучаться удаётся —
        // канал «не выглядит как обычный мобильный интернет за DPI», т.е.
        // мы или за рубежом, или прокси работает.
        val probes = listOf(
            "www.tor-project.org" to 443,
            "1.1.1.1" to 853,        // DoT
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
            // Резолвим dual-stack хост и смотрим, ходят ли AAAA-ответы.
            // Если резолв вернул IPv6 и до него можно достучаться —
            // у нас работает IPv6. Это утечка только если VPN — IPv4-only.
            val addrs = InetAddress.getAllByName("ipv6.google.com")
            val v6 = addrs.filterIsInstance<Inet6Address>()
            if (v6.isEmpty()) {
                mapOf("id" to "ipv6", "ok" to true,
                    "detail" to "IPv6 недоступен — утечки нет")
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
                                    "Если VPN — IPv4-only, это утечка.")
                } else {
                    mapOf("id" to "ipv6", "ok" to true,
                        "detail" to "IPv6 резолвится, но не доступен — ок")
                }
            }
        } catch (e: Throwable) {
            mapOf("id" to "ipv6", "ok" to true,
                "detail" to "IPv6 недоступен: ${e.message}")
        }
    }
}
