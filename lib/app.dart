import 'package:flutter/material.dart';

import 'screens/home_page.dart';

class AndroidLogCenterApp extends StatelessWidget {
  const AndroidLogCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Android Log Center',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6AE0)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
