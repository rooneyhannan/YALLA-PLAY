import 'package:flutter/material.dart';
import 'features/game/presentation/splash_screen.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const YallaPlayApp());
}

class YallaPlayApp extends StatelessWidget {
  const YallaPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yalla Play',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
