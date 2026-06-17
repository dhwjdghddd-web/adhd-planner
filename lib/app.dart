import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/segments/segment_editor_page.dart';

/// Root widget. Navigation to the real feature screens (planner home,
/// segments, routines, focus, memos, rewards, settings) is wired in as each
/// STEP lands; the home is temporarily the segments editor until STEP 5
/// (circular planner home) replaces it.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADHD Planner',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const SegmentEditorPage(),
    );
  }
}
