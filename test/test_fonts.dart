import 'package:flutter/services.dart';

Future<void> loadDesignFonts() async {
  final loader = FontLoader('IBM Plex Sans Arabic');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      rootBundle.load('assets/fonts/IBMPlexSansArabic-$weight.ttf'),
    );
  }
  await loader.load();
}
