import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<EventItem> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await Api.events();
      if (!mounted) return;
      setState(() { _events = e; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  ({IconData icon, Color color, String label}) _style(EventItem e) {
    switch (e.type) {
      case 'sos':
        return (icon: Icons.sos, color: Colors.red, label: 'SOS DARURAT');
      case 'low_battery':
        return (
          icon: Icons.battery_alert,
          color: Colors.orange,
          label: 'Baterai lemah (${e.payload?['battery'] ?? '?'}%)'
        );
      case 'checkin_media':
        return (icon: Icons.photo_camera, color: Colors.blue, label: 'Check-in media masuk');
      default:
        return (icon: Icons.notifications, color: Colors.grey, label: e.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Gagal: $_error'))
              : _events.isEmpty
                  ? const Center(child: Text('Belum ada notifikasi.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _events.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = _events[i];
                          final s = _style(e);
                          return ListTile(
                            leading: Icon(s.icon, color: s.color),
                            title: Text(s.label,
                                style: TextStyle(
                                    fontWeight:
                                        e.seen ? FontWeight.normal : FontWeight.bold)),
                            subtitle: Text(
                                '${e.deviceName ?? e.deviceId} • '
                                '${DateFormat('dd MMM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.createdAt))}'),
                            trailing: e.seen
                                ? null
                                : const Icon(Icons.circle, size: 10, color: Colors.blue),
                            onTap: () async {
                              if (!e.seen) {
                                await Api.markSeen(e.id);
                                _load();
                              }
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
