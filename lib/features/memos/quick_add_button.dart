import 'package:flutter/material.dart';

import '../../core/screen_mode.dart';
import 'quick_add_sheet.dart';

/// The app's [Navigator] key (set on `MaterialApp.navigatorKey` in
/// app.dart).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Bottom inset a screen's body should reserve (e.g. as a `Padding` around
/// its scrollable content) so nothing ever ends up underneath the global
/// bottom-left quick-add FAB: that FAB itself is 56px
/// plus 16px padding on every side (88px total), sitting inside a
/// [SafeArea] — so on top of that 88px, the screen also needs to clear
/// whatever the device's own bottom system inset is (gesture nav bar,
/// etc), or this undershoots on exactly the devices where it matters most.
///
/// Uses `viewPadding` (not `padding`): `padding` collapses to 0 at the bottom
/// when the keyboard opens (viewInsets subsumes it), which would shrink this
/// reservation mid-keyboard and visibly shift a height-centred body (the home
/// dial "흔들림" when the quick-add sheet rose). `viewPadding` is the raw
/// system inset, constant whether or not the keyboard is up.
///
/// On a compact (cover/small) screen the FABs are a small left-corner row, so
/// only a small clearance is reserved -- the body then uses nearly the whole
/// short screen down to just above the camera, instead of a tall FAB band.
double fabAvoidingBottomInset(BuildContext context) => isCompactLayout(context)
    ? 56
    : 88 + MediaQuery.viewPaddingOf(context).bottom;

/// 앱 전역 스낵바 표시 헬퍼.
///
/// 일반 [ScaffoldMessenger.showSnackBar] 대신 이 함수를 사용하면
/// 스낵바가 뜨는 동안 Scaffold 내의 FAB들이 스낵바 높이에 반응하여
/// 자동으로 위로 밀려 올라갔다가 스낵바가 사라지면 내려온다.
void showAppSnackBar(
  BuildContext context,
  Widget content, {
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: content,
      duration: duration,
      action: action,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.fixed,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
    ),
  );
}

/// 좌하단 메모 버튼(left)과 우하단 페이지별 액션 버튼(right)을
/// 하나의 행으로 정렬하여 Scaffold의 floatingActionButton으로 배치할 때 사용합니다.
///
/// Scaffold의 floatingActionButtonLocation을 centerFloat으로 설정하면
/// 이 Row가 화면 가로 너비를 꽉 채우며 두 버튼이 양옆에 깔끔하게 정렬됩니다.
/// 스낵바가 뜰 때 두 버튼이 완벽한 단일 유닛으로 함께 올라갔다 내려옵니다.
class MultiFabRow extends StatelessWidget {
  final Widget? left;
  final Widget? right;

  const MultiFabRow({super.key, this.left, this.right});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          left ?? const SizedBox.shrink(),
          right ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// The Scaffold `floatingActionButtonLocation` a screen should use: a tight
/// bottom-left corner (beside the cover camera) on a compact screen, the usual
/// centre-float row otherwise. Pair with [compactCornerFabs] / [MultiFabRow].
FloatingActionButtonLocation screenFabLocation(BuildContext context) =>
    isCompactLayout(context)
    ? const CompactCornerFabLocation()
    : FloatingActionButtonLocation.centerFloat;

/// Compact (cover/small) screens' bottom FABs: the quick-add memo button plus
/// any [actions] (small FABs), clustered into one short horizontal row in the
/// bottom-left corner so they take a single FAB's height and free the screen.
Widget compactCornerFabs({List<Widget> actions = const []}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const GlobalQuickAddButton(small: true),
      for (final a in actions) ...[const SizedBox(width: 12), a],
    ],
  );
}

/// Floating button mounted on pages so a memo can be captured from the screen
/// in one tap. Bottom-left, since the segments/routines editors already have
/// their own extended FAB at the bottom-right. Hides itself while the quick-add
/// sheet is open.
class GlobalQuickAddButton extends StatefulWidget {
  const GlobalQuickAddButton({super.key, this.small = false});

  /// Compact (cover/small) screens use the smaller FAB so the bottom buttons
  /// take up less of the limited screen.
  final bool small;

  @override
  State<GlobalQuickAddButton> createState() => _GlobalQuickAddButtonState();
}

class _GlobalQuickAddButtonState extends State<GlobalQuickAddButton> {
  // A heroTag unique per mounted instance (not a constant shared by every
  // screen's memo FAB) so the button never runs a cross-screen Hero flight.
  // Sharing one tag made the FAB "fly" between screens on navigation, which
  // briefly rendered the .small FAB at the default (larger) size before
  // snapping back -- the "버튼이 커졌다 작아지는" bug. A unique tag = no flight.
  final Object _heroTag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: quickAddSheetOpen,
      builder: (context, isOpen, _) {
        if (isOpen) return const SizedBox.shrink();
        const icon = Icon(Icons.edit_note);
        return Semantics(
          label: '빠른 메모 추가',
          child: widget.small
              ? FloatingActionButton.small(
                  heroTag: _heroTag,
                  onPressed: () => showQuickAddSheet(context),
                  child: icon,
                )
              : FloatingActionButton(
                  heroTag: _heroTag,
                  onPressed: () => showQuickAddSheet(context),
                  child: icon,
                ),
        );
      },
    );
  }
}
