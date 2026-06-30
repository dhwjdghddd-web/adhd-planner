import 'package:flutter/material.dart';

/// Below this usable logical height (dp), the app switches to its compact
/// layout (cover-screen dashboard, no 24h dial). Chosen so a foldable cover
/// screen (Galaxy Z Flip7 cover ≈ 399dp tall) and genuinely small phones fall
/// under it, while ordinary phones (≈840dp tall on a Z Flip7's main screen)
/// stay on the full layout. dp (not raw pixels) so it's density-independent
/// and generalises across makes.
const double kCompactHeightDp = 560;

/// Set true while the app is showing on a non-primary built-in display -- a
/// foldable cover screen (precise, OS-reported, size-independent signal; see
/// [coverDisplayActive] / the native getDisplayInfo channel). Combined with
/// the height-dp heuristic below so cover screens are caught even if a future
/// one were taller than [kCompactHeightDp], while small ordinary phones (on
/// the primary display) are still caught by height alone.
final ValueNotifier<bool> coverDisplayActive = ValueNotifier<bool>(false);

/// Pure decision used everywhere: compact when the OS says we're on a cover
/// display, OR the usable height is below the compact breakpoint.
bool computeCompactLayout({
  required double heightDp,
  required bool onCoverDisplay,
}) {
  return onCoverDisplay || heightDp < kCompactHeightDp;
}

/// Whether the current screen should use the compact (cover/small-screen)
/// layout. Reads [MediaQuery] height (rebuilds on fold/unfold and any metrics
/// change) and the live [coverDisplayActive] flag.
bool isCompactLayout(BuildContext context) {
  return computeCompactLayout(
    heightDp: MediaQuery.sizeOf(context).height,
    onCoverDisplay: coverDisplayActive.value,
  );
}

/// Pins the FAB hard into the bottom-left corner -- deliberately ignoring the
/// bottom safe-area inset so it sits at the very edge, beside the foldable
/// cover screen's camera cutout, instead of floating well above the bottom
/// like the standard locations. Used on compact screens to free the most room.
class CompactCornerFabLocation extends FloatingActionButtonLocation {
  const CompactCornerFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    const margin = 12.0;
    final x = margin;
    final y =
        geometry.scaffoldSize.height -
        geometry.floatingActionButtonSize.height -
        margin;
    return Offset(x, y);
  }
}
