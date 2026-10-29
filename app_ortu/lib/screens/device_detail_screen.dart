import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import 'live_view_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final Device device;
  const DeviceDetailScreen({super.key, required this.device});
  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.name),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.map), text: 'Lokasi'),
            Tab(icon: Icon(Icons.apps), text: 'Aplikasi'),
            Tab(icon: Icon(Icons.settings_remote), text: 'Kendali'),
          ]),
        ),
        body: TabBarView(children: [
          _LocationTab(deviceId: widget.device.id),
          _UsageTab(deviceId: widget.device.id),
          _ControlTab(deviceId: widget.device.id, deviceName: widget.device.name),
        ]),
      ),
    );
  }
}

// ---------------- Tab Lokasi ----------------
class _LocationTab extends StatefulWidget {
  final String deviceId;
  const _LocationTab({required this.deviceId});
  @override
  State<_LocationTab> createState() => _LocationTabState();
}

class _LocationTabState extends State<_LocationTab> {
  List<LocationPoint> _points = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.locations(widget.deviceId, limit: 300);
      if (!mounted) return;
      setState(() { _points = p; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Gagal: $_error'));
    if (_points.isEmpty) {
      return const Center(child: Text('Belum ada data lokasi dari HP anak.'));
    }
    final latest = _points.first; // API urut terbaru dulu
    final center = LatLng(latest.lat, latest.lng);
    final line = _points.reversed.map((p) => LatLng(p.lat, p.lng)).toList();
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 16),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.wiraproject.app_ortu',
        ),
        if (line.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: line, strokeWidth: 4, color: Colors.blue.withValues(alpha: 0.6)),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: center,
            width: 44,
            height: 44,
            child: const Icon(Icons.location_on, color: Colors.red, size: 44),
          ),
        ]),
        Align(
          alignment: Alignment.bottomCenter,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Terakhir: ${DateFormat('dd MMM HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(latest.recordedAt))}'
                '${latest.battery != null ? '  •  🔋 ${latest.battery}%' : ''}'
                '${latest.accuracy != null ? '  •  ±${latest.accuracy!.round()}m' : ''}',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- Tab Aplikasi ----------------
class _UsageTab extends StatefulWidget {
  final String deviceId;
  const _UsageTab({required this.deviceId});
  @override
  State<_UsageTab> createState() => _UsageTabState();
}

class _UsageTabState extends State<_UsageTab> {
  List<AppUsage> _apps = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await Api.usage(widget.deviceId);
      if (!mounted) return;
      setState(() { _apps = a; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmt(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}j ${m}m';
    if (m > 0) return '${m}m';
    return '${s}d';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Gagal: $_error'));
    if (_apps.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 160),
          Center(child: Text('Belum ada data pemakaian hari ini.')),
          SizedBox(height: 8),
          Center(child: Text('Butuh izin Usage Access di HP anak.',
              style: TextStyle(color: Colors.grey))),
        ]),
      );
    }
    final maxSec = _apps.first.seconds.clamp(1, 1 << 30);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _apps.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final a = _apps[i];
          return ListTile(
            title: Text(a.label ?? a.package),
            subtitle: LinearProgressIndicator(
              value: a.seconds / maxSec,
              backgroundColor: Colors.grey.shade200,
            ),
            trailing: Text(_fmt(a.seconds),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
      ),
    );
  }
}

// ---------------- Tab Kendali ----------------
class _ControlTab extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  const _ControlTab({required this.deviceId, required this.deviceName});
  @override
  State<_ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<_ControlTab> {
  bool _busy = false;

  Future<void> _send(String type, {Map<String, dynamic>? params}) async {
    setState(() => _busy = true);
    try {
      final r = await Api.command(widget.deviceId, type, params: params);
      if (!mounted) return;
      final delivered = r['delivered'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(delivered
            ? 'Perintah terkirim ke HP anak.'
            : 'HP anak sedang offline. Perintah akan dijalankan saat online.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CmdCard(
          icon: Icons.videocam,
          color: Colors.purple,
          title: 'Nonton Live (kamera + suara)',
          subtitle: 'Lihat kamera HP anak secara langsung. HP anak menampilkan '
              'layar "sedang berbagi" & indikator hijau.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LiveViewScreen(
                deviceId: widget.deviceId,
                deviceName: widget.deviceName,
              ),
            ),
          ),
        ),
        _CmdCard(
          icon: Icons.lock,
          color: Colors.orange,
          title: 'Kunci HP',
          subtitle: 'Mengunci layar HP anak dari jarak jauh.',
          onTap: _busy ? null : () => _send('lock'),
        ),
        _CmdCard(
          icon: Icons.lock_open,
          color: Colors.green,
          title: 'Buka Kunci',
          subtitle: 'Membatalkan penguncian.',
          onTap: _busy ? null : () => _send('unlock'),
        ),
        _CmdCard(
          icon: Icons.photo_camera,
          color: Colors.blue,
          title: 'Minta Check-in',
          subtitle: 'HP anak ambil foto depan+belakang & klip suara '
              '(anak melihat notifikasi saat ini terjadi).',
          onTap: _busy
              ? null
              : () => _send('checkin', params: {'photo': true, 'audio': true}),
        ),
        const SizedBox(height: 24),
        const Card(
          color: Color(0xFFFFF4E5),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                    'Semua aktivitas kamera/mikrofon ditampilkan sebagai notifikasi '
                    'di HP anak dan ada indikator hijau Android. Tidak ada pemantauan diam-diam.'),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _CmdCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _CmdCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}
