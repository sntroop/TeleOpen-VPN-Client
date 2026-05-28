import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class GeoPoint {
  final double lat;
  final double lng;
  final String country;
  final String city;
  GeoPoint(this.lat, this.lng, this.country, this.city);
}

class Geolocation {
  static final Map<String, GeoPoint> _cache = {};

  
  static Future<String?> _resolveDns(String host) async {
    
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return host;
    try {
      final list = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (list.isEmpty) return null;
      
      for (final addr in list) {
        if (addr.type == InternetAddressType.IPv4) return addr.address;
      }
      return list.first.address;
    } catch (_) {
      return null;
    }
  }

  
  static bool _isUselessAddress(String host) {
    if (host.isEmpty) return true;
    if (host == '0.0.0.0' || host == '127.0.0.1' || host == 'localhost') return true;
    if (host.startsWith('192.168.')) return true;
    if (host.startsWith('10.')) return true;
    if (host.startsWith('172.16.') || host.startsWith('172.17.') ||
        host.startsWith('172.18.') || host.startsWith('172.19.') ||
        host.startsWith('172.20.') || host.startsWith('172.21.') ||
        host.startsWith('172.22.') || host.startsWith('172.23.') ||
        host.startsWith('172.24.') || host.startsWith('172.25.') ||
        host.startsWith('172.26.') || host.startsWith('172.27.') ||
        host.startsWith('172.28.') || host.startsWith('172.29.') ||
        host.startsWith('172.30.') || host.startsWith('172.31.')) return true;
    return false;
  }

  static Future<GeoPoint?> resolve(String host) async {
    if (_cache.containsKey(host)) return _cache[host];
    if (_isUselessAddress(host)) return null;

    
    final ip = await _resolveDns(host);
    if (ip == null || _isUselessAddress(ip)) return null;

    
    try {
      final r = await http.get(
        Uri.parse('http://ip-api.com/json/$ip?fields=lat,lon,country,city,status'),
      ).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      if (j['status'] != 'success') return null;

      final lat = (j['lat'] as num?)?.toDouble();
      final lng = (j['lon'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      
      if (lat == 0.0 && lng == 0.0) return null;

      final p = GeoPoint(lat, lng, j['country'] ?? '', j['city'] ?? '');
      _cache[host] = p;
      return p;
    } catch (_) {
      return null;
    }
  }
}
