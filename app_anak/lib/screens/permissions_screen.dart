import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';

/// Layar meminta izin yang diperlukan, lalu memulai layanan latar.
class PermissionsScreen extends StatefulWidget {
  final Widget next;
  const PermissionsScreen({super.key, required this.next});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _loc = false, _locBg = false, _notif = false, _usage = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final loc = await Permission.locationWhenInUse.isGranted;
    final locBg = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final usage = (await UsageStats.checkUsagePermission()) ?? false;
    if (!mounted) return;
    setState(() {
      _loc = loc; _locBg = locBg; _notif = notif; _usage = usage;
      _checking = false;
    });
  }

  Future<void> _reqLocation() async {
    await Permission.locationWhenInUse.request();
    await Permission.locationAlways.request();
    _refresh();
  }

  Future<void> _reqNotif() async {
    await Permission.notification.request();
    _refresh();
  }

  Future<void> _reqUsage() async {
    await UsageStats.grantUsagePermission();
    // Kembali dari Settings -> refresh saat resume
  }

  Future<void> _finish() async {
    await FlutterBackgroundService().startService();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => widget.next));
  }

  @override
  Widget build(BuildContext context) {
    final canFinish = _loc && _notif;
    return Scaffold(
      appBar: AppBar(title: const Text('Izin yang Diperlukan')),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Agar orang tua bisa memantau, aplikasi butuh izin berikut. '
                  'Semua aktivitas ditampilkan secara terbuka di HP ini.',
                ),
                const SizedBox(height: 16),
                _PermTile(
                  icon: Icons.location_on,
                  title: 'Lokasi (termasuk latar belakang)',
                  subtitle: 'Mengirim posisi GPS ke orang tua.',
                  granted: _loc && _locBg,
                  onTap: _reqLocation,
                ),
                _PermTile(
                  icon: Icons.notifications,
                  title: 'Notifikasi',
                  subtitle: 'Menampilkan status & permintaan check-in.',
                  granted: _notif,
                  onTap: _reqNotif,
                ),
                _PermTile(
                  icon: Icons.bar_chart,
                  title: 'Akses Penggunaan (Usage Access)',
                  subtitle: 'Ringkasan aplikasi yang dipakai. Opsional tapi disarankan.',
                  granted: _usage,
                  onTap: _reqUsage,
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Perbarui status izin'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: canFinish ? _finish : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Selesai & Mulai'),
                  ),
                ),
                if (!canFinish)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Izin lokasi & notifikasi wajib untuk melanjutkan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
    );
  }
}

class _PermTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool granted;
  final VoidCallback onTap;
  const _PermTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: granted ? Colors.green : Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : FilledButton.tonal(onPressed: onTap, child: const Text('Izinkan')),
      ),
    );
  }
}
