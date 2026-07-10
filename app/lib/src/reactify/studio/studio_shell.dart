import 'package:flutter/material.dart';

import '../../gacha/ui/character_creator_screen.dart';
import '../text/reaction_text_editor.dart';

class ReactifyStudioShell extends StatefulWidget {
  const ReactifyStudioShell({super.key});

  @override
  State<ReactifyStudioShell> createState() => _ReactifyStudioShellState();
}

class _ReactifyStudioShellState extends State<ReactifyStudioShell> {
  var _selectedIndex = 0;
  final List<Widget?> _pages = [const _CharacterStudioPage(), null];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_motion_outlined),
      selectedIcon: Icon(Icons.auto_awesome_motion),
      label: 'Characters',
    ),
    NavigationDestination(
      icon: Icon(Icons.subtitles_outlined),
      selectedIcon: Icon(Icons.subtitles),
      label: 'Dialogue',
    ),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.auto_awesome_motion_outlined),
      selectedIcon: Icon(Icons.auto_awesome_motion),
      label: Text('Characters'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.subtitles_outlined),
      selectedIcon: Icon(Icons.subtitles),
      label: Text('Dialogue'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [for (final page in _pages) page ?? const SizedBox.shrink()];
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = IndexedStack(index: _selectedIndex, children: pages);
        if (constraints.maxWidth < 720) {
          return Scaffold(
            body: SafeArea(bottom: false, child: content),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              destinations: _destinations,
              onDestinationSelected: _select,
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                destinations: _railDestinations,
                onDestinationSelected: _select,
                labelType: constraints.maxWidth >= 1100
                    ? NavigationRailLabelType.all
                    : NavigationRailLabelType.selected,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: _ReactifyMark(),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  void _select(int index) {
    setState(() {
      _selectedIndex = index;
      _pages[index] ??= const ReactionTextEditor(
        initialText:
            'Cassie: Kill them all...\nKai: What do I even say to this...\nJet: This is what I expected.',
      );
    });
  }
}

class _CharacterStudioPage extends StatelessWidget {
  const _CharacterStudioPage();

  @override
  Widget build(BuildContext context) {
    const inkBlue = Color(0xFF254B73);
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: inkBlue,
          brightness: Brightness.light,
          primary: inkBlue,
          surface: const Color(0xFFF6F3EA),
        ),
        useMaterial3: true,
      ),
      child: const CharacterCreatorScreen(),
    );
  }
}

class _ReactifyMark extends StatelessWidget {
  const _ReactifyMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        'R',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
