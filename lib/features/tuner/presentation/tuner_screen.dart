import 'package:flutter/material.dart';

class TunerScreen extends StatelessWidget {
  const TunerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFF00),
      body: Center(
        child: Text(
          'DIESER TUNER\nWURDE GELÖSCHT',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black,
            fontSize: 48,
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
