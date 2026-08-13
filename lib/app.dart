import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';

class DriverFocusApp extends StatelessWidget {
  const DriverFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Focus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF286C63)),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
