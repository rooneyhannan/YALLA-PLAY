import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/main_screen.dart';

void main() => runApp(const YallaGuitarApp());

class YallaGuitarApp extends StatelessWidget {
  const YallaGuitarApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Yalla Guitar', debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme, locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const MainScreen(),
  );
}
