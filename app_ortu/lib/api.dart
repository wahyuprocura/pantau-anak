import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client API untuk server Pantau Anak (self-hosted).
/// Base URL & token disimpan di SharedPreferences.
class Api {
  static String baseUrl = '';
  static String? token;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? '';
    token = p.getString('token');
  }

  static Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
  }

  static Future<void> _setToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('token');
    } else {
      await p.setString('token', t);
    }
  }

  static bool get loggedIn => token != null && token!.isNotEmpty;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Uri _u(String path) => Uri.parse('$baseUrl$path');

  static dynamic _parse(http.Response r) {
    final body = r.body.isEmpty ? {} : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    throw ApiError(body is Map && body['error'] != null
        ? body['error'].toString()
        : 'HTTP ${r.statusCode}');
  }

  static Future<void> register(String email, String password, String name) async {
    final r = await http.post(_u('/api/parent/register'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password, 'name': name}));
    final d = _parse(r);
    await _setToken(d['token']);
  }

  static Future<void> login(String email, String password) async {
    final r = await http.post(_u('/api/parent/login'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password}));
    final d = _parse(r);
    await _setToken(d['token']);
  }

  static Future<void> logout() => _setToken(null);

  static Future<Map<String, dynamic>> pairingCode() async {
    final r = await http.post(_u('/api/parent/pairing-code'), headers: _headers);
    return Map<String, dynamic>.from(_parse(r));
  }

  static Future<List<Device>> devices() async {
    final r = await http.get(_u('/api/parent/devices'), headers: _headers);
    final d = _parse(r);
    return (d['devices'] as List).map((e) => Device.fromJson(e)).toList();
  }

  static Future<List<LocationPoint>> locations(String deviceId, {int limit = 200}) async {
    final r = await http.get(_u('/api/parent/devices/$deviceId/locations?limit=$limit'),
        headers: _headers);
    final d = _parse(r);
    return (d['locations'] as List).map((e) => LocationPoint.fromJson(e)).toList();
  }

  static Future<List<AppUsage>> usage(String deviceId, {String? day}) async {
    final q = day != null ? '?day=$day' : '';
    final r = await http.get(_u('/api/parent/devices/$deviceId/usage$q'), headers: _headers);
    final d = _parse(r);
    return (d['apps'] as List).map((e) => AppUsage.fromJson(e)).toList();
  }

  static Future<List<EventItem>> events() async {
    final r = await http.get(_u('/api/parent/events'), headers: _headers);
    final d = _parse(r);
    return (d['events'] as List).map((e) => EventItem.fromJson(e)).toList();
  }

  static Future<void> markSeen(int id) async {
    await http.post(_u('/api/parent/events/$id/seen'), headers: _headers);
  }

  /// type: lock | unlock | checkin
  static Future<Map<String, dynamic>> command(String deviceId, String type,
      {Map<String, dynamic>? params}) async {
    final r = await http.post(_u('/api/parent/devices/$deviceId/command'),
        headers: _headers, body: jsonEncode({'type': type, 'params': params ?? {}}));
    return Map<String, dynamic>.from(_parse(r));
  }

  static String mediaUrl(String mediaId) => '$baseUrl/api/parent/media/$mediaId';

  /// URL WebSocket untuk terima event & signaling WebRTC (role parent).
  static Uri wsUri() {
    final ws = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    return Uri.parse('$ws/ws?role=parent&token=$token');
  }
}

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Device {
  final String id, name;
  final String? platform;
  final int? lastSeen;
  final bool online;
  final LocationPoint? lastLocation;
  final ForegroundApp? foreground;
  Device({
    required this.id,
    required this.name,
    this.platform,
    this.lastSeen,
    this.online = false,
    this.lastLocation,
    this.foreground,
  });
  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'],
        name: j['name'],
        platform: j['platform'],
        lastSeen: j['last_seen'],
        online: j['online'] == true,
        lastLocation:
            j['lastLocation'] != null ? LocationPoint.fromJson(j['lastLocation']) : null,
        foreground:
            j['foreground'] != null ? ForegroundApp.fromJson(j['foreground']) : null,
      );
}

class LocationPoint {
  final double lat, lng;
  final double? accuracy;
  final int? battery;
  final bool charging;
  final int recordedAt;
  LocationPoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.battery,
    this.charging = false,
    required this.recordedAt,
  });
  factory LocationPoint.fromJson(Map<String, dynamic> j) => LocationPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracy: j['accuracy'] != null ? (j['accuracy'] as num).toDouble() : null,
        battery: j['battery'],
        charging: j['charging'] == 1 || j['charging'] == true,
        recordedAt: j['recorded_at'],
      );
}

class AppUsage {
  final String package;
  final String? label;
  final int seconds;
  AppUsage({required this.package, this.label, required this.seconds});
  factory AppUsage.fromJson(Map<String, dynamic> j) =>
      AppUsage(package: j['package'], label: j['label'], seconds: j['seconds']);
}

class ForegroundApp {
  final String? package, label;
  final int? since;
  ForegroundApp({this.package, this.label, this.since});
  factory ForegroundApp.fromJson(Map<String, dynamic> j) =>
      ForegroundApp(package: j['package'], label: j['label'], since: j['since']);
}

class EventItem {
  final int id;
  final String deviceId, type;
  final String? deviceName;
  final Map<String, dynamic>? payload;
  final int createdAt;
  final bool seen;
  EventItem({
    required this.id,
    required this.deviceId,
    required this.type,
    this.deviceName,
    this.payload,
    required this.createdAt,
    this.seen = false,
  });
  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
        id: j['id'],
        deviceId: j['device_id'],
        type: j['type'],
        deviceName: j['device_name'],
        payload: j['payload'] != null ? Map<String, dynamic>.from(j['payload']) : null,
        createdAt: j['created_at'],
        seen: j['seen'] == 1 || j['seen'] == true,
      );
}
