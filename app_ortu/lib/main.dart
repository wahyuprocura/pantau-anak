import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/login_screen.dart';
import 'screens/devices_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const PantauOrtuApp());
}

class PantauOrtuApp extends StatelessWidget {
  const PantauOrtuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pantau Anak',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: Api.loggedIn && Api.baseUrl.isNotEmpty
          ? const DevicesScreen()
          : const LoginScreen(),
    );
  }
}
