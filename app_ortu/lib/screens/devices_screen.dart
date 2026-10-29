import 'package:flutter/material.dart';
import '../api.dart';
import 'login_screen.dart';
import 'device_detail_screen.dart';
import 'events_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Device> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _error = null; });
    try {
      final d = await Api.devices();
      if (!mounted) return;
      setState(() { _devices = d; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _showPairingCode() async {
    showDialog(
      context: context,
      builder: (_) => FutureBuilder<Map<String, dynamic>>(
        future: Api.pairingCode(),
        builder: (context, snap) {
          return AlertDialog(
            title: const Text('Kode Pairing'),
            content: snap.connectionState != ConnectionState.done
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : snap.hasError
                    ? Text('Gagal: ${snap.error}')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Masukkan kode ini di HP anak (menu Pairing):'),
                          const SizedBox(height: 16),
                          Text(
                            snap.data!['code'].toString(),
                            style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8),
                          ),
                          const SizedBox(height: 8),
                          Text('Berlaku ${snap.data!['ttl'] ?? 300} detik',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _logout() async {
    await Api.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perangkat Anak'),
        actions: [
          IconButton(
            tooltip: 'Notifikasi',
            icon: const Icon(Icons.notifications),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EventsScreen())),
          ),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'logout') _logout(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout', child: Text('Keluar')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPairingCode,
        icon: const Icon(Icons.add_link),
        label: const Text('Tambah HP Anak'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _refresh)
                : _devices.isEmpty
                    ? _EmptyView(onAdd: _showPairingCode)
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (_, i) => _DeviceTile(
                          device: _devices[i],
                          onTap: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        DeviceDetailScreen(device: _devices[i])));
                            _refresh();
                          },
                        ),
                      ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;
  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = device.lastLocation;
    final batt = loc?.battery;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.online ? Colors.green : Colors.grey,
          child: const Icon(Icons.phone_android, color: Colors.white),
        ),
        title: Text(device.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.online ? 'Online' : 'Offline'),
            if (batt != null)
              Row(children: [
                Icon(
                    loc!.charging
                        ? Icons.battery_charging_full
                        : batt <= 15
                            ? Icons.battery_alert
                            : Icons.battery_full,
                    size: 16,
                    color: batt <= 15 ? Colors.red : Colors.green),
                const SizedBox(width: 4),
                Text('$batt%'),
              ]),
            if (device.foreground?.label != null)
              Text('Sedang buka: ${device.foreground!.label}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyView({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.phonelink_erase, size: 72, color: Colors.grey),
        const SizedBox(height: 16),
        const Center(child: Text('Belum ada HP anak terhubung')),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_link),
            label: const Text('Tambah HP Anak'),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.cloud_off, size: 72, color: Colors.grey),
        const SizedBox(height: 16),
        Center(child: Text('Gagal memuat: $error', textAlign: TextAlign.center)),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ),
      ],
    );
  }
}
