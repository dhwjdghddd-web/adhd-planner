import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/planner/planner_page.dart';

/// Root widget. Navigation to the real feature screens (routines, focus,
/// memos, rewards, settings) is wired in as each STEP lands; the home is the
/// circular planner dial, with the segments editor reachable from its
/// app bar.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADHD Planner',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const PlannerPage(),
    );
  }
}
