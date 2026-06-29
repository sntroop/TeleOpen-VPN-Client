<div align="center">

# TeleOpen VPN

### Полнофункциональный мультипротокольный VPN-клиент на Flutter

Настоящий туннель через нативный `VpnService`, все ходовые прокси-протоколы,
локальный обход DPI, маркетплейс серверов, тонкая маршрутизация уровня
clash.meta, MTProto-прокси, кастомные темы и in-app самообновление.

**Hysteria2 · VLESS · VMess · Trojan · Shadowsocks · SOCKS · MTProto · ByeDPI**

[![Platform](https://img.shields.io/badge/platform-Android%20%C2%B7%20iOS%20%C2%B7%20Desktop-2b2b2b)](#-платформы)
[![Flutter](https://img.shields.io/badge/Flutter-Dart%20%E2%89%A53.0-2b2b2b)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-GPL--3.0-2b2b2b)](LICENSE)
[![Site](https://img.shields.io/badge/site-teleopen.space-2b2b2b)](https://teleopen.space)

</div>

---

## 📖 О проекте

**TeleOpen VPN** — это не «обёртка над одним протоколом», а полноценный сетевой
комбайн. Приложение поднимает **настоящий** системный туннель через нативный
Android `VpnService` и заворачивает трафик в одно из ядер — **Hysteria2** (QUIC)
или **xray/V2Ray** — в зависимости от протокола сервера. Поверх этого надстроены
подписки, community-маркетплейс конфигов, тонкая маршрутизация, локальный обход
блокировок без сервера, инструменты диагностики и полностью кастомная
дизайн-система с галереей тем.

Эта репозиторий — **клиентская** часть. Серверный бэкенд (каталог маркета,
авторизация через Telegram, AI-диагностика, раздача обновлений) — отдельная
инфраструктура на [teleopen.space](https://teleopen.space); базовый URL задаётся
в [`lib/logic/market_api.dart`](lib/logic/market_api.dart) (`kApiBase`).

---

## ✨ Полный функционал

### 🔌 Протоколы и ядра подключения
- **VLESS** — reality / TLS / XTLS-vision / ws / grpc / tcp.
- **VMess** — все стандартные транспорты и security.
- **Trojan**, **Shadowsocks** (+ShadowsocksR/SSR), **SOCKS5**.
- **Hysteria2** — нативное QUIC-ядро с обфускацией (`assets/hysteria2`,
  `libhysteria2.so`).
- **MTProto** — прокси для Telegram, включая **fake-TLS** секреты (`ee…`).
- **ByeDPI / ciadpi** — **локальная** десинхронизация DPI прямо на устройстве,
  **без** удалённого VPN-сервера (`libciadpi.so`).
- Универсальный парсер ссылок: `vless://`, `vmess://`, `trojan://`, `ss://`,
  `ssr://`, `socks://`, `hysteria2://`, `tg://proxy`, `https://t.me/proxy`.

### 📥 Серверы, импорт и подписки
- Импорт по **ссылке**, **QR-коду** (сканер камеры), **из файла**, вставкой из
  буфера и через **deep-link** `teleopen://s/<code>` (из браузера/Telegram,
  cold-start и warm).
- **Подписки**: добавление по URL, **авто-обновление** по расписанию, парсинг
  `Subscription-Userinfo` (остаток трафика, дата окончания).
- **Happ-импорт** — расшифровка закрытых ссылок `happ://crypt..crypt5` целиком
  на устройстве: RSA-PKCS1v15 + ChaCha20-Poly1305 на чистом Dart
  ([`logic/happ_decrypt.dart`](lib/logic/happ_decrypt.dart)).
- **Группы** серверов, сворачивание, **сортировка** (по пингу / имени / типу),
  выбор **типа пинга** (TCP-коннект или реальный HTTP).
- **Failover** и health-чек: автопереключение на живой сервер при падении.
- Локальное хранилище нод и истории запусков (`node_store`, `launched_nodes`).

### 🛒 Маркетплейс серверов
- Каталог community-конфигов с авторизацией через **Telegram** (JWT в Keystore).
- **Отзывы**, рейтинги и health-репорты нод от пользователей.
- **Публикация** своих серверов и **модерация**.
- Ролевые кабинеты: панель **автора**, панель **админа/модератора**, кабинет
  **продавца** (seller cabinet + подключение панели продавца).
- Системные **анонсы** внутри приложения.

### 🧭 Маршрутизация и сеть
- **Правила маршрутизации** по geoip / geosite (proxy / direct / block),
  импорт баз `geoip.dat` / `geosite.dat`.
- **Исключения маршрутов** (bypass конкретных подсетей/доменов).
- **Per-app proxy** (split tunneling) с готовыми **пресетами** приложений.
- **DNS**: кастомные резолверы, DoH/DoT, **DNS-leak тест**.
- **External Controller** (clash.meta / mihomo API) — управление из
  Yacd / MetaCubeX / Razord, общий secret-токен.
- **Локальные порты** (SOCKS/HTTP inbound), **прокси-авторизация**.
- Создание **локального inbound** для раздачи на другие устройства.
- **TLS-tricks**, режим **WARP**, **kill-switch**, проверка **заметности**
  прокси (censorship-resistance probe).
- Тонкие **meta-features** (фичи ядра clash.meta).

### 🔧 Диагностика и инструменты
- **AI-«починить сервер»** — снимает безопасную телеметрию (пинги до
  таргет-доменов, DNS, хвост логов) и применяет план фиксов **только по белому
  списку** полей ([`logic/ai_fixer.dart`](lib/logic/ai_fixer.dart)).
- **Спид-тест** — самописный на `dart:io` через Cloudflare (надёжнее
  заброшенных нативных плагинов).
- **Статистика** трафика в реальном времени (вверх/вниз, сессии).
- **Диагностика** соединения и **просмотр логов** ядра прямо в приложении.
- **Карта мира** с расположением серверов, **геолокация** выходного узла.
- Probe-проверки связности и доверия к ноде (`connectivity_probe`, `trust`).

### 📤 Шаринг и Telegram
- Генерация **QR-кодов** и ссылок на свои конфиги.
- Создание и шаринг **MTProto-прокси** (валидация hex/fake-TLS секрета).
- Вкладки шаринга: конфиг-ссылка, inbound, MTProto.

### 🎨 Темы и кастомизация
- Полностью **собственная iOS-дизайн-система** (`lib/ios_theme/`): токены,
  типографика, компоненты (кнопки, поля, списки) — без сторонних UI-китов.
- **Галерея тем** с публикацией и установкой чужих тем в один тап.
- **Сменные иконки** приложения.
- Тонкая настройка цветов через color-picker.

### 🔄 Обновления и платформенные интеграции
- **Self-update**: фоновая проверка версии, скачивание APK, сверка **sha256**
  поверх TLS, передача системному установщику (для sideload-сборок).
- **Виджет рабочего стола** (быстрое подключение к серверу).
- **Плитка в быстрых настройках** (Quick Settings Tile) для вкл/выкл VPN.
- **Автозапуск** по загрузке устройства (опционально).
- Уведомления о статусе туннеля.

---

## 🖥 Обзор экранов

| Раздел | Экраны |
|--------|--------|
| **Главное** | список серверов, группы, статус подключения, MTProto-тайлы |
| **Маркет** | каталог, карточка сервера, публикация, панели автора/админа/продавца, анонсы |
| **Подписки** | добавление, авто-обновление, импорт из файла/happ:// |
| **Сеть** | маршрутизация, исключения, per-app proxy, DNS, DNS-leak, external controller, локальные порты, прокси-авторизация, TLS-tricks, WARP, meta-features |
| **Инструменты** | спид-тест, статистика, диагностика, логи, «починить сервер», заметность прокси, карта мира |
| **Шаринг** | QR/ссылки, создание inbound, MTProto-прокси |
| **Оформление** | темы, галерея тем, сменные иконки |
| **Прочее** | настройки, вход через Telegram, приватность |

---

## 🧱 Стек и архитектура

| Слой | Технологии |
|------|-----------|
| **UI** | Flutter, Material + собственная iOS-дизайн-система (`lib/ios_theme/`) |
| **Состояние** | `ChangeNotifier` + кастомный `InheritedWidget`-scope (`lib/app/`), доменно разбитый `AppState` — без сторонних DI/state-пакетов |
| **Натив** | `MethodChannel` / `EventChannel` (`lib/vpn_bridge.dart` ↔ Kotlin `VpnService`) |
| **Хранилище** | `shared_preferences` (настройки) + `flutter_secure_storage` (JWT/секреты в Keystore/Keychain) |
| **Крипто** | `pointycastle` (RSA + ChaCha20-Poly1305 для happ://), `crypto` (sha256) |
| **Ядра** | xray через `flutter_v2ray_local`, Hysteria2 (нативное `.so`), ciadpi (ByeDPI) |
| **Прочее** | `mobile_scanner` (QR), `app_links` (deep links), `flutter_local_notifications`, `installed_apps` (per-app) |

### Структура проекта

```
lib/
├── app/         # точка входа, корневой AppState-scope, тема приложения
├── state/       # AppState по доменам: connection, groups, mtproto, ping,
│                #   subscriptions, user, failover, vpn_status + AppSettings
├── vpn_bridge.dart   # мост к нативному VpnService (Method/EventChannel)
├── ios_theme/   # дизайн-система: токены + компоненты (button, field, list…)
├── models/      # VpnNode, market, mtproto_proxy, routing_rule, theme,
│                #   per_app_proxy, per_app_preset, announcement
├── logic/       # парсеры, подписки, updater, ai_fixer, ping, happ_decrypt,
│                #   hysteria2, market_api, failover, diagnostics, trust,
│                #   geolocation, telegram_proxy, secure_store, crash_log…
├── screens/     # все экраны (home, market, settings, routing_rules, byedpi,
│                #   dns_leak_test, mtproto, themes, statistics, share, warp…)
└── widgets/     # переиспользуемые виджеты

android/app/src/main/kotlin/space/teleopen/app/
├── HysteriaTunVpnService.kt   # нативный VpnService (туннель)
├── MainActivity.kt            # хост Method/EventChannel
├── ServerWidgetProvider.kt    # виджет рабочего стола
├── VpnTileService.kt          # плитка в быстрых настройках
├── BootReceiver.kt            # автозапуск по загрузке
└── ServerWidgetService.kt     # рендер виджета
```

---

## 🚀 Сборка

```bash
flutter pub get          # зависимости
flutter analyze          # статанализ (цель — без error/warning)
flutter test             # юнит-тесты (парсеры URI, happ-decrypt)
flutter run              # запуск на подключённом устройстве

# Релизный APK (универсальный):
flutter build apk --release

# Либо по ABI (меньше размер):
flutter build apk --release --split-per-abi
```

**Требования:** Flutter c Dart SDK ≥ 3.0, Android SDK/NDK.

**Бэкенд:** функции маркета, AI-диагностики и self-update требуют поднятого
сервера — базовый URL в
[`lib/logic/market_api.dart`](lib/logic/market_api.dart) (`kApiBase`,
по умолчанию `https://teleopen.space`).

**Подпись релиза:** секреты не в репозитории. Создайте `android/key.properties`
по образцу `android/key.properties.example` (`*.jks` / `*.keystore` —
в `.gitignore`).

---

## 🔒 Безопасность

- Чувствительные токены (JWT) — **только** в защищённом хранилище
  (Keystore/Keychain), не в `shared_preferences` открытым текстом.
- Скачанные APK обновлений проверяются по **sha256** поверх TLS перед установкой.
- **AI-фиксер** физически не может трогать критичные поля (kill-switch, удаление
  серверов, регион) — допускается только **узкий белый список**.
- Глобальный перехват ошибок (`runZonedGuarded` + `FlutterError.onError` +
  `PlatformDispatcher.onError`): краши логируются, а не убивают процесс.
- Расшифровка happ:// — целиком на устройстве; ключи реверс-инжиниринга **не**
  публикуются, в репозиторий едут только собранные `assets/happ/*.json`.

---

## 📱 Платформы

| Платформа | Статус |
|-----------|--------|
| **Android** | ✅ основная (нативный `VpnService`, виджет, плитка QS, автозапуск) |
| iOS | 🟡 таргет присутствует (`ios/`), tun-расширение требует доработки |
| Linux / macOS / Windows | 🟡 desktop-таргеты подключены |

---

## 📄 Лицензия

Распространяется под [**GPL-3.0**](LICENSE). Форки и производные работы должны
оставаться открытыми под той же лицензией. См. также
[PRIVACY_POLICY.txt](PRIVACY_POLICY.txt).

---

<div align="center">

**TeleOpen VPN** — © TeleOpen · [teleopen.space](https://teleopen.space) · Сделано на Flutter.

</div>
