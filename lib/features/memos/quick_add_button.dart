import 'package:flutter/material.dart';

import 'quick_add_sheet.dart';

/// The app's [Navigator] key (set on `MaterialApp.navigatorKey` in
/// app.dart). [GlobalQuickAddButton] lives in `MaterialApp.builder`,
/// *outside* the Navigator/Overlay it builds, so its own [BuildContext]
/// can't be used to open a bottom sheet — it has to reach back in via this
/// key instead.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// How many currently-mounted screens want the global FAB hidden (see
/// [SuppressGlobalFab]) — a count rather than a bool so two such screens
/// stacked in the Navigator don't let each other's dispose() re-show it.
final ValueNotifier<int> fabSuppressionCount = ValueNotifier<int>(0);

/// Wrap a full-screen page's [Scaffold] in this when it has its own
/// full-width button pinned near the bottom (onboarding's "다음", Focus's
/// 완료/스누즈/다음 할 일) — otherwise the global FAB sits right on top of
/// it. Screens with their own bottom-*right* FAB (segments/routines
/// editors) don't need this; there's no overlap to begin with.
class SuppressGlobalFab extends StatefulWidget {
  const SuppressGlobalFab({super.key, required this.child});

  final Widget child;

  @override
  State<SuppressGlobalFab> createState() => _SuppressGlobalFabState();
}

class _SuppressGlobalFabState extends State<SuppressGlobalFab> {
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    // Deferred: initState runs mid-build, and dispose can run while the
    // element tree is locked for unmounting — bumping the notifier
    // synchronously in either spot would try to rebuild
    // GlobalQuickAddButton's ValueListenableBuilder at a point the
    // framework forbids. A microtask runs after the current synchronous
    // build/unmount pass fully unwinds, which is always safe.
    Future.microtask(() {
      _counted = true;
      fabSuppressionCount.value++;
    });
  }

  @override
  void dispose() {
    if (_counted) {
      Future.microtask(() => fabSuppressionCount.value--);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Floating button mounted once at the app root (see app.dart's
/// `MaterialApp.builder`) so a memo can be captured from any screen in one
/// tap. Bottom-left, since the segments/routines editors already have their
/// own extended FAB at the bottom-right. Hides itself while the quick-add
/// sheet is open, or while a [SuppressGlobalFab]-wrapped screen is showing,
/// instead of floating on top of either.
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
        return ValueListenableBuilder<int>(
          valueListenable: fabSuppressionCount,
          builder: (context, suppressed, _) {
            if (isOpen || suppressed > 0) return const SizedBox.shrink();
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
      },
    );
  }
}
