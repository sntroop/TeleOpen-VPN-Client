// lib/state/vpn_status.dart
//
// Статус VPN-туннеля. Вынесено из main.dart при разбиении монолита.

enum VpnStatus { stopped, connecting, connected, error }
