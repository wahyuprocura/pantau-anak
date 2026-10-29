import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import '../api.dart';
import 'pairing_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});
  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _running = false;
  bool _sosBusy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final r = await FlutterBackgroundService().isRunning();
    if (!mounted) return;
    setState(() => _running = r);
  }

  Future<void> _sos() async {
    setState(() => _sosBusy = true);
    try {
      double? lat, lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 15));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
      await Api.sendEvent('sos', {'lat': lat, 'lng': lng});
      if (lat != null && lng != null) {
        await Api.sendLocation(lat: lat, lng: lng);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS terkirim ke orang tua.'), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal kirim SOS: $e')));
    } finally {
      if (mounted) setState(() => _sosBusy = false);
    }
  }

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Putuskan hubungan?'),
        content: const Text(
            'HP ini akan berhenti berbagi lokasi dan terputus dari akun orang tua.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Putuskan')),
        ],
      ),
    );
    if (ok != true) return;
    FlutterBackgroundService().invoke('stopService');
    await Api.unpair();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const PairingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pantau Anak'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _check),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _running ? const Color(0xFFE7F6E7) : const Color(0xFFFDECEC),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_running ? Icons.check_circle : Icons.error,
                      color: _running ? Colors.green : Colors.red, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_running ? 'Aktif & terhubung' : 'Tidak aktif',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(_running
                            ? 'Lokasi sedang dibagikan ke orang tua.'
                            : 'Layanan berhenti. Tekan mulai di bawah.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: _sosBusy ? null : _sos,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                  boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 24)],
                ),
                child: Center(
                  child: _sosBusy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sos, color: Colors.white, size: 64),
                            Text('Tekan untuk\nkirim SOS',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white)),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          if (!_running)
            FilledButton.icon(
              onPressed: () async {
                await FlutterBackgroundService().startService();
                _check();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Mulai layanan'),
            ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Server'),
            subtitle: Text(Api.baseUrl),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link_off, color: Colors.red),
            title: const Text('Putuskan hubungan',
                style: TextStyle(color: Colors.red)),
            onTap: _unpair,
          ),
        ],
      ),
    );
  }
}
