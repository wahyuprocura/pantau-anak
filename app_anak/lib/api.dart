import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client API sisi HP anak. Autentikasi pakai device token (x-device-token).
class Api {
  static String baseUrl = '';
  static String? deviceToken;
  static String? deviceId;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? '';
    deviceToken = p.getString('deviceToken');
    deviceId = p.getString('deviceId');
  }

  static bool get paired => deviceToken != null && deviceToken!.isNotEmpty;

  static Future<void> _save(String url, String id, String token) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    deviceId = id;
    deviceToken = token;
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
    await p.setString('deviceId', id);
    await p.setString('deviceToken', token);
  }

  static Future<void> unpair() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('deviceToken');
    await p.remove('deviceId');
    deviceToken = null;
    deviceId = null;
  }

  static Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (deviceToken != null) 'x-device-token': deviceToken!,
      };

  static Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// Tukar kode pairing 6 digit jadi device token.
  static Future<void> pair(String url, String code, String name) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final r = await http.post(Uri.parse('$base/api/device/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code, 'name': name, 'platform': 'android'}));
    final body = r.body.isEmpty ? {} : jsonDecode(r.body);
    if (r.statusCode != 200) {
      throw Exception(body['error'] ?? 'Pairing gagal (HTTP ${r.statusCode})');
    }
    await _save(base, body['deviceId'], body['token']);
  }

  static Future<void> sendLocation({
    required double lat,
    required double lng,
    double? accuracy,
    int? battery,
    bool charging = false,
  }) async {
    await http.post(_u('/api/device/location'),
        headers: _h,
        body: jsonEncode({
          'lat': lat,
          'lng': lng,
          'accuracy': accuracy,
          'battery': battery,
          'charging': charging,
          'recordedAt': DateTime.now().millisecondsSinceEpoch,
        }));
  }

  static Future<void> sendUsage(String day, List<Map<String, dynamic>> apps) async {
    await http.post(_u('/api/device/usage'),
        headers: _h, body: jsonEncode({'day': day, 'apps': apps}));
  }

  static Future<void> sendForeground(String? pkg, String? label) async {
    await http.post(_u('/api/device/foreground'),
        headers: _h, body: jsonEncode({'package': pkg, 'label': label}));
  }

  static Future<void> sendEvent(String type, [Map<String, dynamic>? payload]) async {
    await http.post(_u('/api/device/event'),
        headers: _h, body: jsonEncode({'type': type, 'payload': payload}));
  }

  static Future<void> commandStatus(String commandId, String status) async {
    await http.post(_u('/api/device/command-status'),
        headers: _h, body: jsonEncode({'commandId': commandId, 'status': status}));
  }

  /// Upload file media (foto/audio) hasil check-in.
  static Future<void> uploadMedia({
    required String kind,
    required File file,
    String? commandId,
  }) async {
    final req = http.MultipartRequest('POST', _u('/api/device/media'));
    req.headers['x-device-token'] = deviceToken ?? '';
    req.fields['kind'] = kind;
    if (commandId != null) req.fields['commandId'] = commandId;
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final r = await req.send();
    if (r.statusCode != 200) {
      throw Exception('Upload media gagal (HTTP ${r.statusCode})');
    }
  }

  /// URL WebSocket untuk terima perintah realtime.
  static Uri wsUri() {
    final ws = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    return Uri.parse('$ws/ws?role=device&token=$deviceToken');
  }
}
