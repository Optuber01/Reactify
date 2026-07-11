import 'package:flutter/material.dart';

import 'reactify/ui/reactify_studio_screen.dart';

class ReactifyGachaApp extends StatelessWidget {
  const ReactifyGachaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFECE9DF);
    const ink = Color(0xFF171A19);
    const signal = Color(0xFFD4FF32);
    return MaterialApp(
      title: 'Reactify Gacha Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: signal,
          brightness: Brightness.light,
          primary: ink,
          surface: paper,
        ),
        scaffoldBackgroundColor: paper,
        fontFamily: 'Bahnschrift',
        useMaterial3: true,
      ),
      home: const ReactifyStudioScreen(),
    );
  }
}
