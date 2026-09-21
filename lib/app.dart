import 'package:flutter/material.dart';

import 'screens/home_page.dart';

class Log4App extends StatelessWidget {
  const Log4App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Log4App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6AE0)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
