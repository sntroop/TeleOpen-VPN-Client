<div align="center">

# TeleOpen VPN

**Полнофункциональный VPN-клиент на Flutter**
Hysteria2 · VLESS · VMess · Trojan · Shadowsocks · SOCKS · MTProto

`v1.0.13 (5011)` · Android (primary) · iOS/desktop targets present

</div>

---

## Что это

TeleOpen — VPN-клиент на Flutter, который поднимает реальный туннель
Hysteria2 / V2Ray (xray) через нативный Android `VpnService`. Поддерживает все
основные прокси-протоколы, подписки, и community-маркетплейс серверов
(бэкенд — [teleopen.space](https://teleopen.space)), где конфиги публикуются и
устанавливаются в один тап.

Сверх базового VPN: AI-«починить сервер» (диагностика проблемного соединения и
автоприменение фиксов по белому списку), движок кастомных тем с публичной
галереей, MTProto-прокси для Telegram, in-app самообновление с проверкой
sha256, и набор сетевых инструментов (DNS leak test, проверка заметности
прокси, спид-тест, диагностика).

---

## Возможности

- **Протоколы**: VLESS (reality/tls/vision), VMess, Trojan, Shadowsocks(R),
  SOCKS, Hysteria2, MTProto.
- **Подписки**: импорт по URL, авто-обновление, парсинг user-info (трафик/срок).
- **Маркетплейс**: каталог с авторизацией через Telegram (JWT), отзывы,
  health-репорты нод, публикация и модерация.
- **AI-фиксер** (`logic/ai_fixer.dart`): снимает диагностику (пинги до
  таргет-доменов, DNS, хвост логов), шлёт на `/ai/fix`, применяет план
  пошагово — только через белый список безопасных полей.
- **Сеть**: per-app proxy, kill-switch, тонкие DNS/Meta/External-Controller
  настройки (mihomo/clash.meta), импорт geoip/geosite.
- **Темы**: полностью кастомный iOS-движок (`ios_theme.dart`) + галерея.
- **Self-update** (`logic/updater.dart`): фоновая проверка, скачивание APK,
  проверка sha256, передача системному установщику (sideload-сборки).

---

## Стек и архитектура

- **Flutter** (Dart SDK ≥ 3.0), Material + кастомная iOS-дизайн-система.
- **Состояние**: `ChangeNotifier` + собственный `InheritedWidget`
  (`AppStateScope` в `lib/main.dart`) — без сторонних DI/state-пакетов.
- **Натив**: общение через `MethodChannel`/`EventChannel`
  (`space.teleopen.app/native`, `.../vpn_status`) — см. `lib/vpn_bridge.dart`.
- **Хранилище**: `shared_preferences` для настроек/групп; JWT и секреты —
  в `flutter_secure_storage` (Keystore/Keychain), см. `logic/secure_store.dart`.
- **Ядра**: xray (через `flutter_v2ray_local`) и Hysteria2 (`assets/hysteria2`).

### Структура `lib/`

```
lib/
├── main.dart            # точка входа, AppState, AppSettings, корневой scope
├── ios_theme.dart       # дизайн-система (цвета, типографика, виджеты)
├── vpn_bridge.dart      # мост к нативному VpnService (Method/EventChannel)
├── models/              # VpnNode, market, mtproto, theme, per_app_proxy
├── logic/               # парсеры, подписки, updater, ai_fixer, ping, api…
├── screens/             # экраны (home, market, settings, diagnostics…)
└── widgets/             # переиспользуемые виджеты (update_banner, color_picker…)
```

---

## Сборка

```bash
flutter pub get          # зависимости
flutter analyze          # статанализ (должен быть без error/warning)
flutter test             # юнит-тесты (парсеры URI)
flutter run              # запуск на подключённом устройстве

# Релизный APK:
flutter build apk --release
```

Для self-update и маркета нужен поднятый бэкенд — базовый URL задаётся в
`lib/logic/market_api.dart` (`kApiBase`, по умолчанию `https://teleopen.space`).

---

## Безопасность

- Чувствительные токены (JWT) — только в защищённом хранилище, не в prefs.
- Скачанные APK обновлений проверяются по sha256 поверх TLS.
- AI-фиксер физически не может трогать критичные поля (kill-switch, удаление
  серверов, регион) — только узкий белый список в `ai_fixer.dart`.
- Глобальный перехват ошибок (`runZonedGuarded` + `FlutterError.onError` +
  `PlatformDispatcher.onError`) — краши логируются, а не убивают процесс

---

## Лицензия

[GPL-3.0](LICENSE). Форки и производные работы должны оставаться открытыми
под той же лицензией.
