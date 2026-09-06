import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';

class DriverAttuneApp extends StatelessWidget {
  const DriverAttuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Attune',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF286C63)),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
