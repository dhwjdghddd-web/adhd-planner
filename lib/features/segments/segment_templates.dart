import '../../core/constants.dart';

/// A starter block offered on the empty home dial — plain data (not a
/// [Segment]) since the real thing needs a fresh id/order at insert time.
/// One tap on its chip (see planner_page.dart's empty-state) adds exactly
/// this one block with a reasonable default time, so a brand-new user's dial
/// fills in immediately instead of staring at an empty ring with no idea
/// what to do first.
class SegmentTemplate {
  const SegmentTemplate({
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.startMinute,
    required this.endMinute,
  });

  final String name;
  final String iconKey;
  final int colorValue;
  final int startMinute;
  final int endMinute;
}

/// Seven common ADHD-daily-routine blocks covering a typical day, in time
/// order. Times are deliberately ordinary defaults -- the user edits them
/// (or the whole block) afterward the same way as any other block.
final List<SegmentTemplate> kSegmentTemplates = [
  SegmentTemplate(
    name: '기상',
    iconKey: 'wb_sunny',
    colorValue: kSegmentPalette[4].toARGB32(), // amber
    startMinute: 7 * 60,
    endMinute: 7 * 60 + 30,
  ),
  SegmentTemplate(
    name: '약',
    iconKey: 'event',
    colorValue: kSegmentPalette[5].toARGB32(), // rose
    startMinute: 7 * 60 + 30,
    endMinute: 7 * 60 + 40,
  ),
  SegmentTemplate(
    name: '아침',
    iconKey: 'coffee',
    colorValue: kSegmentPalette[1].toARGB32(), // coral
    startMinute: 7 * 60 + 40,
    endMinute: 8 * 60 + 10,
  ),
  SegmentTemplate(
    name: '집중',
    iconKey: 'work',
    colorValue: kSegmentPalette[6].toARGB32(), // blue
    startMinute: 9 * 60,
    endMinute: 11 * 60,
  ),
  SegmentTemplate(
    name: '점심',
    iconKey: 'restaurant',
    colorValue: kSegmentPalette[0].toARGB32(), // teal
    startMinute: 12 * 60,
    endMinute: 13 * 60,
  ),
  SegmentTemplate(
    name: '휴식',
    iconKey: 'directions_walk',
    colorValue: kSegmentPalette[3].toARGB32(), // sage
    startMinute: 15 * 60,
    endMinute: 15 * 60 + 30,
  ),
  SegmentTemplate(
    name: '수면',
    iconKey: 'bedtime',
    colorValue: kSegmentPalette[7].toARGB32(), // slate
    startMinute: 23 * 60,
    endMinute: 1439,
  ),
];
