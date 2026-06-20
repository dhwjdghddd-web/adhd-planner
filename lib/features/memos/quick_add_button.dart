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

/// 스낵바가 현재 화면에 보이는지 여부.
///
/// [showAppSnackBar]가 스낵바를 띄울 때 true로, 닫힐 때 false로 설정한다.
/// [app.dart]의 builder에서 [GlobalQuickAddButton]을 스낵바 높이만큼
/// 위로 밀어올리는 데 사용한다.
final ValueNotifier<bool> snackBarVisible = ValueNotifier<bool>(false);

/// Bottom inset a screen's body should reserve (e.g. as a `Padding` around
/// its scrollable content) so nothing ever ends up underneath the global
/// bottom-left quick-add FAB drawn in app.dart: that FAB itself is 56px
/// plus 16px padding on every side (88px total), sitting inside a
/// [SafeArea] — so on top of that 88px, the screen also needs to clear
/// whatever the device's own bottom system inset is (gesture nav bar,
/// etc), or this undershoots on exactly the devices where it matters most.
double fabAvoidingBottomInset(BuildContext context) =>
    88 + MediaQuery.of(context).padding.bottom;

/// 앱 전역 스낵바 표시 헬퍼.
///
/// 일반 [ScaffoldMessenger.showSnackBar] 대신 이 함수를 사용하면
/// 스낵바가 뜨는 동안 Scaffold 내 루틴추가 FAB와 전역 메모 FAB이
/// 함께 위로 밀려 올라갔다가 스낵바가 사라지면 내려온다.
///
/// 동작 원리:
/// - [SnackBarBehavior.fixed] 모드: Scaffold가 내부 FAB을 자동으로 위로 밀어줌.
/// - [snackBarVisible] 노티파이어: [GlobalQuickAddButton]이 이 값을 보고
///   [AnimatedPadding]으로 동일 높이(58 dp)만큼 함께 올라감.
/// - 스낵바가 닫히면 [snackBarVisible]을 false로 돌려 두 FAB이 함께 내려옴.
void showAppSnackBar(
  BuildContext context,
  Widget content, {
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
  Color? backgroundColor,
}) {
  snackBarVisible.value = true;
  final controller = ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: content,
      duration: duration,
      action: action,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.fixed,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
    ),
  );
  controller.closed.then((_) => snackBarVisible.value = false);
}

/// Wrap a full-screen page's [Scaffold] in this when it has its own
/// full-width button pinned near the bottom (onboarding's \"다음\", Focus's
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
