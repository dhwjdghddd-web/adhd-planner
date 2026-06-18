import 'package:flutter/material.dart';

import 'quick_add_sheet.dart';

/// The app's [Navigator] key (set on `MaterialApp.navigatorKey` in
/// app.dart). [GlobalQuickAddButton] lives in `MaterialApp.builder`,
/// *outside* the Navigator/Overlay it builds, so its own [BuildContext]
/// can't be used to open a bottom sheet — it has to reach back in via this
/// key instead.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Floating button mounted once at the app root (see app.dart's
/// `MaterialApp.builder`) so a memo can be captured from any screen in one
/// tap. Bottom-left, since the segments/routines editors already have their
/// own extended FAB at the bottom-right. Hides itself while the quick-add
/// sheet is open instead of floating on top of it.
///
/// No `tooltip` here deliberately: [FloatingActionButton]'s tooltip needs an
/// `Overlay` ancestor to mount, which this widget — sitting outside the
/// Navigator — doesn't have. [Semantics] gives screen readers the same label
/// without that requirement.
class GlobalQuickAddButton extends StatelessWidget {
  const GlobalQuickAddButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: quickAddSheetOpen,
      builder: (context, isOpen, _) {
        if (isOpen) return const SizedBox.shrink();
        return Semantics(
          label: '빠른 메모 추가',
          child: FloatingActionButton(
            heroTag: 'global-quick-add',
            onPressed: () {
              final overlayContext = appNavigatorKey.currentState?.overlay?.context;
              if (overlayContext != null) showQuickAddSheet(overlayContext);
            },
            child: const Icon(Icons.edit_note),
          ),
        );
      },
    );
  }
}
