import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'background.dart';
import 'screens/pairing_screen.dart';
import 'screens/status_screen.dart';
import 'screens/live_share_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();
bool _liveOpen = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  await initBackgroundService();
  if (Api.paired) {
    FlutterBackgroundService().startService();
  }
  _wireLiveEvents();
  runApp(const PantauAnakApp());
  WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingLive());
}

/// Dengarkan sinyal dari background service untuk buka/tutup layar live.
void _wireLiveEvents() {
  final service = FlutterBackgroundService();
  service.on('open_live').listen((data) => _openLive(data?['camera']?.toString() ?? 'front'));
  service.on('close_live').listen((_) {
    if (_liveOpen) {
      navigatorKey.currentState?.maybePop();
      _liveOpen = false;
    }
  });
}

Future<void> _checkPendingLive() async {
  final p = await SharedPreferences.getInstance();
  final cam = p.getString('pendingLiveCamera');
  if (cam != null) {
    await p.remove('pendingLiveCamera');
    if (Api.paired) _openLive(cam);
  }
}

void _openLive(String camera) {
  if (_liveOpen || !Api.paired) return;
  _liveOpen = true;
  navigatorKey.currentState
      ?.push(MaterialPageRoute(builder: (_) => LiveShareScreen(camera: camera)))
      .then((_) => _liveOpen = false);
}

class PantauAnakApp extends StatelessWidget {
  const PantauAnakApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pantau Anak',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16A34A)),
        useMaterial3: true,
      ),
      home: Api.paired ? const StatusScreen() : const PairingScreen(),
    );
  }
}
