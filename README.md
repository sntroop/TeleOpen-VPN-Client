<div align="center">

# TeleOpen

**Open-source Flutter VPN client for Android**  
Hysteria2 · VLESS · VMess · Trojan · ShadowSocks · MTProto

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-green?logo=android)](https://android.com)
[![Backend](https://img.shields.io/badge/Marketplace-teleopen.space-black)](https://teleopen.space)

</div>

---

## What is TeleOpen

TeleOpen is a full-featured Android VPN client built with Flutter. It runs a real Hysteria2/V2Ray tunnel via a native Android VPN service, supports every major proxy protocol, and ships with a community-driven subscription marketplace where users can publish and install server configs with one tap.

On top of the core VPN, there's an AI-powered connection fixer that diagnoses broken connections and applies fixes automatically, a full custom theme engine with a public gallery, Telegram proxy support, and deep network tools for power users.

---

## Screenshots

> _Coming soon — contributions welcome_

---

## Features

### Protocols

| Protocol | Import format |
|---|---|
| Hysteria2 | `hysteria2://` · `hy2://` |
| VLESS | `vless://` |
| VMess | `vmess://` (JSON & URI) |
| Trojan | `trojan://` |
| ShadowSocks | `ss://` |
| ShadowSocksR | `ssr://` |
| SOCKS5 | `socks://` · `socks5://` |
| MTProto | `tg://proxy` · `t.me/proxy` · direct input |

Transports: WebSocket, gRPC, TCP, HTTP/2. Import from URI, QR code, clipboard, or subscription URL.

---

### Subscription Marketplace

A community platform built into the app. Browse, search by tags, and install server configs published by other users. Rate subscriptions, leave reviews, track your own publications via the author panel.

- Tag-based search and filtering
- Server count, ratings, and last-update timestamp per subscription
- One-tap install from marketplace to your server list
- Publish your own subscription with icon, description, and tags
- JWT auth via Telegram login (no passwords)
- Admin moderation panel (for marketplace maintainers)

Backend: [teleopen.space](https://teleopen.space) (FastAPI). Self-hostable — just change `kApiBase` in `lib/logic/market_api.dart`.

---

### AI Connection Fixer

Broken connection? The fixer collects a diagnostic snapshot — current node, active settings, recent log lines — and sends it to the backend AI. The AI returns a structured fix plan. The app applies each action one by one with animated UI feedback.

Possible actions the AI can take:
- `switch_setting` — toggle a specific setting (DNS, mux, sniffing, etc.)
- `switch_dns` — change DNS resolver
- `switch_server` — switch to a different server by country

The AI **cannot** turn off the kill switch, delete servers, or change the balancer region. The allowed action set is a strict whitelist enforced on the client.

---

### TLS Tricks (anti-censorship)

For regions with deep packet inspection:

- **Fragmentation** — splits TLS ClientHello into small packets to bypass DPI. Configurable packet target, fragment size, and inter-fragment delay.
- **Mixed-case SNI** — randomizes the case of the SNI field (`ExAmPlE.CoM`) to confuse fingerprinting.
- **TLS padding** — adds random-length padding to TLS records to break size-based fingerprinting.

---

### Cloudflare WARP Integration

Three routing modes:
- Route WARP through the proxy
- Route the proxy through WARP
- WARP only

Supports custom license keys, clean IP selection, and noise configuration (count, mode, size, delay) to mask WARP traffic patterns.

---

### Telegram Proxies (MTProto)

Full MTProto proxy support independent of the VPN tunnel:

- Parse `tg://`, `t.me/proxy`, and raw `host:port:secret` strings
- Secret validation (plain, dd-prefixed, ee-prefixed)
- One-tap "Add to Telegram" — works with any installed Telegram fork (TelegramX, Nekogram, etc.) via deep link with `setPackage()`
- Proxy diagnostics, share via QR code or link
- Group proxies into named collections and share entire groups

---

### Network Tools

**Diagnostics** — runs a multi-step check on any server in your list: TCP reachability, handshake, latency, and gives a score out of 100 with a plain-language verdict.

**DNS Leak Test** — checks whether DNS queries are leaking outside the tunnel.

**Proxy Visibility** — checks WebRTC leaks, JA3 fingerprint, and HTTP headers that could reveal proxy usage to websites.

**Speed Test** — in-app speed test (Fast.com / Ookla) that runs through the active VPN tunnel.

**World Map** — visualizes your server list geographically.

---

### Per-App Proxy

Choose exactly which apps route through the VPN and which connect directly. Integrates with `QUERY_ALL_PACKAGES` for a full app list with icons.

---

### Custom Themes

Full theme engine: background color, accent color, blur intensity, opacity, font scale, and more. Themes are serialized to JSON and can be shared.

**Theme Gallery** — browse and install themes published by the community via the marketplace API. Publish your own theme with a name and preview.

---

### Statistics

Per-session traffic tracking: bytes sent/received, duration, protocol, server. Top servers by usage. Persistent across restarts via local storage.

---

### Advanced Settings

| Category | Options |
|---|---|
| Routing | Region, balancer strategy, IPv6 route, LAN bypass, ad blocking |
| DNS | Remote DNS, outbound DNS, DNS intercept |
| Network | HTTP/SOCKS/TProxy/Mixed local ports, LAN binding |
| Meta features | Sniffing (HTTP/TLS), MPTCP, GeoIP/GeoSite/Country/ASN database import |
| External Controller | REST API for Clash/Meta dashboards |
| TLS Tricks | Fragmentation, SNI randomization, padding |
| WARP | Cloudflare WARP with noise |
| VPN | Kill switch, auto-connect on boot, mux, packet sniffing |

---

## Architecture

```
lib/
├── main.dart                     # App entry point, AppState, global settings model
├── ios_theme.dart                # Design system — colors, typography, all UI components
├── vpn_bridge.dart               # MethodChannel bridge to native VPN service
│
├── screens/                      # One file per screen
│   ├── home_screen.dart          # Server list, connect button, traffic widget
│   ├── market_screen.dart        # Subscription marketplace
│   ├── market_detail_screen.dart # Subscription detail, reviews, install
│   ├── fix_server_screen.dart    # AI fixer — diagnose and apply fix plan
│   ├── settings_screen.dart      # All settings
│   ├── themes_screen.dart        # Theme editor
│   ├── theme_gallery_screen.dart # Community theme gallery
│   ├── statistics_screen.dart    # Session history and traffic stats
│   ├── diagnostics_screen.dart   # Per-server health check
│   ├── dns_leak_test_screen.dart # DNS leak check
│   ├── proxy_visibility_screen.dart # WebRTC / JA3 / header leaks
│   ├── speed_test_screen.dart    # In-tunnel speed test
│   ├── world_map_screen.dart     # Server geography map
│   ├── warp_screen.dart          # Cloudflare WARP settings
│   ├── tls_tricks_screen.dart    # Fragmentation, SNI, padding
│   ├── mtproto_proxy_screen.dart # MTProto proxy manager
│   ├── per_app_proxy_screen.dart # Per-app routing
│   ├── local_ports_screen.dart   # Local HTTP/SOCKS/TProxy ports
│   ├── meta_features_screen.dart # Sniffing, Geo databases
│   ├── dns_screen.dart           # DNS configuration
│   ├── share_screen.dart         # Share / export server configs
│   ├── add_subscription_screen.dart # Add subscription by URL/QR
│   ├── publish_screen.dart       # Publish subscription to marketplace
│   ├── login_screen.dart         # Telegram login
│   ├── author_panel_screen.dart  # Author's own publications
│   ├── admin_panel_screen.dart   # Marketplace moderation
│   ├── log_screen.dart           # VPN engine log viewer
│   └── network_screen.dart       # Routing and network settings
│
├── logic/                        # Business logic, no UI
│   ├── market_api.dart           # HTTP client for teleopen.space API
│   ├── ai_fixer.dart             # Fetch fix plan, parse actions, apply them
│   ├── parsers.dart              # Parse all VPN URI formats
│   ├── subscriptions.dart        # Fetch and refresh subscription URLs
│   ├── diagnostics.dart          # Multi-step server health check
│   ├── telegram_proxy.dart       # MTProto proxy parse and launch
│   ├── hysteria2.dart            # Hysteria2 config generation
│   ├── speed_benchmark.dart      # Speed test logic
│   ├── geolocation.dart          # IP geolocation for server cards
│   ├── crash_log.dart            # Crash capture and storage
│   ├── ping.dart                 # Latency measurement
│   └── theme_storage.dart        # Custom theme persistence
│
├── models/                       # Pure data models
│   ├── vpn_node.dart             # Server node (all protocols)
│   ├── market.dart               # Marketplace items, reviews, user
│   ├── mtproto_proxy.dart        # MTProto proxy model + parsing
│   ├── theme.dart                # Custom theme model
│   └── per_app_proxy.dart        # Per-app proxy entry
│
├── widgets/
│   ├── telegram_proxy_sheet.dart # Bottom sheet for MTProto proxy details
│   ├── traffic_stats_widget.dart # Real-time rx/tx traffic display
│   └── color_picker.dart         # HSV color picker for theme editor
│
├── MainActivity.kt               # Android activity, MethodChannels
├── HysteriaTunVpnService.kt      # Hysteria2 TUN VPN service (Android 14+ compatible)
└── NativeExtensions.kt           # Native helpers (notifications, system queries)
```

---

## Building

**Requirements**
- Flutter 3.x
- Android SDK 36
- NDK 28.2.13676358
- Java 17

```bash
# Install dependencies
flutter pub get

# Debug build
flutter run

# Release APK
flutter build apk --release

# Release AAB (for Play Store)
flutter build appbundle --release
```

**Note:** The app uses a local `flutter_v2ray` package. Add it to `pubspec.yaml`:

```yaml
flutter_v2ray:
  git:
    url: https://github.com/blueboy-tm/flutter_v2ray
    ref: main
```

Or pin to the pub.dev version:

```yaml
flutter_v2ray: ^1.0.10
```

---

## Self-hosting the Backend

The marketplace, AI fixer, theme gallery, and Telegram auth all hit `https://teleopen.space`. To run your own instance, change the base URL in `lib/logic/market_api.dart`:

```dart
const String kApiBase = 'https://your-domain.com';
```

The backend is a FastAPI application. It is not open-sourced at this time.

---

## Contributing

Issues and pull requests are welcome.

For significant changes, open an issue first to discuss what you'd like to change.

Please do not submit PRs that hardcode credentials, add tracking, or modify the AGPL license terms.

---

## License

```
Copyright (C) 2026 TeleOpen Contributors

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

Full terms: [LICENSE](LICENSE) · [gnu.org/licenses/agpl-3.0](https://www.gnu.org/licenses/agpl-3.0.txt)

Any modified version that is run as a network service must publish its source code under the same license.
