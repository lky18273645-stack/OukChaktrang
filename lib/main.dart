// lib/main.dart
import 'package:flutter/material.dart';

import 'services/virtual_ecosystem.dart';
import 'ui/app_state.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  final eco = await VirtualEcosystem.load();
  await eco.onAppOpen();
  runApp(OukApp(eco));
}

class OukApp extends StatelessWidget {
  final VirtualEcosystem eco;
  const OukApp(this.eco, {super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AppSettings.km,
        builder: (context, _, __) => MaterialApp(
          title: 'OukChaktrang.com',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
          home: HomeScreen(eco),
        ),
      );
}
