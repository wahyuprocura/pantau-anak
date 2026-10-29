import 'package:flutter/material.dart';
import '../api.dart';
import 'status_screen.dart';
import 'permissions_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _server = TextEditingController(text: Api.baseUrl);
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (_server.text.trim().isEmpty) throw Exception('Alamat server wajib diisi');
      if (_code.text.trim().length != 6) throw Exception('Kode pairing harus 6 digit');
      await Api.pair(_server.text, _code.text.trim(),
          _name.text.trim().isEmpty ? 'HP Anak' : _name.text.trim());
      if (!mounted) return;
      // Lanjut ke layar izin, lalu status.
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => const PermissionsScreen(next: StatusScreen())));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.link, size: 64, color: Color(0xFF16A34A)),
                  const SizedBox(height: 8),
                  Text('Hubungkan ke Orang Tua',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text(
                    'Minta kode pairing 6 digit dari aplikasi orang tua, '
                    'lalu masukkan di sini.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _server,
                    decoration: const InputDecoration(
                      labelText: 'Alamat server',
                      hintText: 'https://pantau.wiraproject.my.id',
                      prefixIcon: Icon(Icons.dns),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Nama HP (mis. HP Budi)',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 28, letterSpacing: 8),
                    decoration: const InputDecoration(
                      labelText: 'Kode Pairing',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _pair,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Hubungkan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
