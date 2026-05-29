import 'package:flutter/material.dart';

import 'gacha/ui/character_creator_screen.dart';

class ReactifyGachaApp extends StatelessWidget {
  const ReactifyGachaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ivory = Color(0xFFF6F3EA);
    const inkBlue = Color(0xFF254B73);
    return MaterialApp(
      title: 'Reactify Gacha Renderer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: inkBlue,
          brightness: Brightness.light,
          primary: inkBlue,
          surface: ivory,
        ),
        scaffoldBackgroundColor: ivory,
        useMaterial3: true,
      ),
      home: const CharacterCreatorScreen(),
    );
  }
}
