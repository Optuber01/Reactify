import 'package:flutter/material.dart';

import 'reactify/studio/studio_shell.dart';

class ReactifyGachaApp extends StatelessWidget {
  const ReactifyGachaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const cobalt = Color(0xFF6EA8FE);
    return MaterialApp(
      title: 'Reactify Reaction Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: cobalt,
          brightness: Brightness.dark,
          surface: const Color(0xFF141821),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1017),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF111620),
          indicatorColor: Color(0xFF273B5A),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF111620),
          indicatorColor: Color(0xFF273B5A),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1B2230),
        ),
        useMaterial3: true,
      ),
      home: const ReactifyStudioShell(),
    );
  }
}
