-keep class com.clashsiing.** { *; }
-keep class io.flutter.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keep class io.nekohasekai.libbox.** { *; }
-keep class com.tecclub.flutter_singbox.** { *; }

# Please add these rules to your existing keep rules in order to suppress warnings.
-dontwarn io.nekohasekai.libbox.BoxService
-dontwarn io.nekohasekai.libbox.CommandClient
-dontwarn io.nekohasekai.libbox.CommandClientHandler
-dontwarn io.nekohasekai.libbox.CommandClientOptions
-dontwarn io.nekohasekai.libbox.CommandServer
-dontwarn io.nekohasekai.libbox.CommandServerHandler
-dontwarn io.nekohasekai.libbox.Connections
-dontwarn io.nekohasekai.libbox.ExchangeContext
-dontwarn io.nekohasekai.libbox.Func
-dontwarn io.nekohasekai.libbox.InterfaceUpdateListener
-dontwarn io.nekohasekai.libbox.Libbox
-dontwarn io.nekohasekai.libbox.LocalDNSTransport
-dontwarn io.nekohasekai.libbox.NetworkInterface
-dontwarn io.nekohasekai.libbox.NetworkInterfaceIterator
-dontwarn io.nekohasekai.libbox.Notification
-dontwarn io.nekohasekai.libbox.OutboundGroup
-dontwarn io.nekohasekai.libbox.OutboundGroupIterator
-dontwarn io.nekohasekai.libbox.PlatformInterface
-dontwarn io.nekohasekai.libbox.RoutePrefix
-dontwarn io.nekohasekai.libbox.RoutePrefixIterator
-dontwarn io.nekohasekai.libbox.SetupOptions
-dontwarn io.nekohasekai.libbox.StatusMessage
-dontwarn io.nekohasekai.libbox.StringBox
-dontwarn io.nekohasekai.libbox.StringIterator
-dontwarn io.nekohasekai.libbox.SystemProxyStatus
-dontwarn io.nekohasekai.libbox.TunOptions
-dontwarn io.nekohasekai.libbox.WIFIState

# ── libv2ray (AndroidLibXrayLite) ────────────────────────────────────
-keep class libv2ray.** { *; }
-keep interface libv2ray.** { *; }
-keepnames class libv2ray.** { *; }
-keepclasseswithmembernames class libv2ray.** {
    native <methods>;
}
-keep class * implements libv2ray.CoreCallbackHandler { *; }
-keep class * implements libv2ray.ProcessFinder { *; }
-keepclassmembers class * implements libv2ray.CoreCallbackHandler { *; }

# ── Go runtime (gomobile) ────────────────────────────────────────────
-keep class go.** { *; }
-keep interface go.** { *; }
-keepclasseswithmembernames class go.** {
    native <methods>;
}

# ── Наш VPN сервис ───────────────────────────────────────────────────
-keep class space.teleopen.app.HysteriaTunVpnService { *; }
-keep class space.teleopen.app.HysteriaTunVpnService$Companion { *; }
-keep class space.teleopen.app.MainActivity { *; }

-dontwarn libv2ray.**
-dontwarn go.**
