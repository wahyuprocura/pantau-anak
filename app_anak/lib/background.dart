import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

const notifChannelId = 'pantau_anak_service';
const notifId = 8787;
const _lockChannel = MethodChannel('pantau/admin');

final _fln = FlutterLocalNotificationsPlugin();

/// Setup service. Dipanggil dari main().
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await _fln.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  const channel = AndroidNotificationChannel(
    notifChannelId,
    'Pantau Anak',
    description: 'Berbagi lokasi ke orang tua',
    importance: Importance.low,
  );
  await _fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notifChannelId,
      initialNotificationTitle: 'Pantau Anak aktif',
      initialNotificationContent: 'Lokasi dibagikan ke orang tua',
      foregroundServiceNotificationId: notifId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Api.load();

  service.on('stopService').listen((_) => service.stopSelf());

  if (!Api.paired) return;

  final battery = Battery();
  WebSocketChannel? ws;
  DateTime lastUsagePush = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- Terima perintah realtime dari orang tua ----
  void connectWs() {
    try {
      ws = WebSocketChannel.connect(Api.wsUri());
      ws!.stream.listen((raw) async {
        await _handleCommand(raw.toString(), service);
      }, onDone: () => ws = null, onError: (_) => ws = null);
    } catch (_) {
      ws = null;
    }
  }

  connectWs();

  // ---- Loop kirim lokasi + baterai tiap 60 detik ----
  Timer.periodic(const Duration(seconds: 60), (t) async {
    await Api.load();
    if (!Api.paired) { t.cancel(); return; }
    if (ws == null) connectWs();

    try {
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 30));
      } catch (_) {}

      if (pos != null) {
        await Api.sendLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
          battery: level,
          charging: charging,
        );
      }

      // Update isi notifikasi (transparan)
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Pantau Anak aktif',
          content: 'Lokasi dibagikan • 🔋$level%',
        );
      }
    } catch (_) {}

    // ---- Push ringkasan usage tiap 15 menit ----
    if (DateTime.now().difference(lastUsagePush).inMinutes >= 15) {
      lastUsagePush = DateTime.now();
      await _pushUsage();
    }
  });
}

/// Ambil ringkasan pemakaian app hari ini + app yang sedang dibuka, kirim ke server.
Future<void> _pushUsage() async {
  try {
    final granted = await UsageStats.checkUsagePermission() ?? false;
    if (!granted) return;
    final now = DateTime.now();
    final startDay = DateTime(now.year, now.month, now.day);
    final stats = await UsageStats.queryUsageStats(startDay, now);
    final apps = <Map<String, dynamic>>[];
    for (final s in stats) {
      final sec = (int.tryParse(s.totalTimeInForeground ?? '0') ?? 0) ~/ 1000;
      if (sec <= 0 || s.packageName == null) continue;
      apps.add({'package': s.packageName, 'label': s.packageName, 'seconds': sec});
    }
    if (apps.isNotEmpty) {
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await Api.sendUsage(day, apps);
    }

    // App foreground sekarang (dari event terakhir)
    final events = await UsageStats.queryEvents(
        now.subtract(const Duration(minutes: 10)), now);
    if (events.isNotEmpty) {
      final last = events.last;
      await Api.sendForeground(last.packageName, last.packageName);
    }
  } catch (_) {}
}

/// Tangani perintah dari orang tua.
Future<void> _handleCommand(String raw, ServiceInstance service) async {
  Map<String, dynamic> msg;
  try {
    msg = Map<String, dynamic>.from(jsonDecode(raw));
  } catch (_) {
    return;
  }
  if (msg['kind'] != 'command') return;
  final id = msg['id']?.toString();
  final type = msg['type'];

  try {
    switch (type) {
      case 'live':
        final cam = (msg['params']?['camera'] ?? 'front').toString();
        final p = await SharedPreferences.getInstance();
        await p.setString('pendingLiveCamera', cam);
        // Beri tahu isolate UI (jika app hidup) untuk buka layar berbagi.
        service.invoke('open_live', {'camera': cam});
        await _notify('Orang tua ingin melihat live',
            'Buka aplikasi Pantau Anak untuk mulai berbagi kamera & suara.');
        break;
      case 'live_stop':
        service.invoke('close_live', {});
        break;
      case 'lock':
        try {
          await _lockChannel.invokeMethod('lock');
        } catch (_) {
          // Device admin belum aktif/belum tersedia
        }
        await _notify('HP dikunci oleh orang tua',
            'Orang tua mengunci perangkat ini dari jarak jauh.');
        break;
      case 'unlock':
        // Demi keamanan, layar tidak bisa dibuka otomatis dari jauh.
        await _notify('Kunci dibatalkan', 'Orang tua membatalkan penguncian.');
        break;
      case 'checkin':
        // Transparan: beri tahu anak bahwa check-in diminta.
        await _notify('Permintaan check-in',
            'Orang tua meminta foto & suara singkat untuk memastikan kondisimu.');
        await Api.sendEvent('checkin_requested', {'commandId': id});
        // Penangkapan kamera/mic ditangani modul capture (tahap berikutnya).
        break;
    }
    if (id != null) await Api.commandStatus(id, 'done');
  } catch (_) {
    if (id != null) await Api.commandStatus(id, 'failed');
  }
}

Future<void> _notify(String title, String body) async {
  await _fln.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'pantau_anak_alerts',
        'Pemberitahuan',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}
