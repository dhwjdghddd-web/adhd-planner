import 'package:flutter/material.dart';

/// Below this usable logical height (dp), the app switches to its compact
/// layout (cover-screen dashboard, no 24h dial). Chosen so a foldable cover
/// screen (Galaxy Z Flip7 cover ≈ 399dp tall) and genuinely small phones fall
/// under it, while ordinary phones (≈840dp tall on a Z Flip7's main screen)
/// stay on the full layout. dp (not raw pixels) so it's density-independent
/// and generalises across makes.
const double kCompactHeightDp = 560;

/// A screen at least this tall (dp) is treated as a full/main display and is
/// never compact -- even if [coverDisplayActive] is momentarily stale. That
/// flag is refreshed from a native display query on fold/unfold, which can lag
/// the actual display migration; without this ceiling a stale "on cover" flag
/// kept the unfolded main screen stuck in the cover layout. No real cover
/// screen is this tall (a Z Flip7 cover is ≈399dp), so nothing is lost.
const double kMaxCoverHeightDp = 700;

/// Set true while the app is showing on a non-primary built-in display -- a
/// foldable cover screen (precise, OS-reported, size-independent signal; see
/// [coverDisplayActive] / the native getDisplayInfo channel). Combined with
/// the height-dp heuristic below so cover screens are caught even if a future
/// one were taller than [kCompactHeightDp], while small ordinary phones (on
/// the primary display) are still caught by height alone.
final ValueNotifier<bool> coverDisplayActive = ValueNotifier<bool>(false);

/// Pure decision used everywhere. Height is the authoritative signal (it tracks
/// fold/unfold instantly via MediaQuery); the OS "on a cover display" flag only
/// breaks ties in the ambiguous mid-band, and is deliberately ignored for a
/// clearly-large screen so a stale flag can't keep the unfolded main screen
/// stuck compact.
bool computeCompactLayout({
  required double heightDp,
  required bool onCoverDisplay,
}) {
  if (heightDp < kCompactHeightDp) return true; // cover-sized or small phone
  if (heightDp >= kMaxCoverHeightDp) return false; // clearly a main display
  return onCoverDisplay; // ambiguous band: trust the OS display signal
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
