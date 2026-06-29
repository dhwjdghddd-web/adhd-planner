import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'focus_timer_controller.dart';

/// Picker (idle) or progress card (running/paused) for the Focus screen's
/// optional timer -- 포모도로(25+5)/15분/사용자정의, plus a "2분만 시작"
/// shortcut for the lowest-effort possible start. Purely a thin view over
/// [focusTimerControllerProvider]; all the actual state lives there so it
/// survives leaving this screen (and its end notification still fires) --
/// see that file's class doc.
class FocusTimerSection extends ConsumerWidget {
  const FocusTimerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(focusTimerControllerProvider);
    final controller = ref.read(focusTimerControllerProvider.notifier);

    if (state.isIdle) {
      return _TimerPicker(controller: controller);
    }
    return _RunningTimerCard(state: state, controller: controller);
  }
}

class _TimerPicker extends StatelessWidget {
  const _TimerPicker({required this.controller});

  final FocusTimerController controller;

  Future<void> _pickCustomDuration(BuildContext context) async {
    const presets = [10, 20, 30, 45, 60];
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('몇 분으로 할까요?'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in presets)
                    ActionChip(
                      label: Text('$m분'),
                      onPressed: () => Navigator.pop(sheetContext, m),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (minutes != null) controller.startFixed(Duration(minutes: minutes));
  }

  // Compact (not Material's default button sizing) -- this picker sits right
  // under the dial-sized icon ring above it, and at default button text size
  // it visually competed with that for attention instead of reading as a
  // secondary, optional action.
  static final _chipStyle = OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    textStyle: const TextStyle(fontSize: 13),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              style: _chipStyle,
              onPressed: controller.startPomodoro,
              child: const Text('포모도로 25+5'),
            ),
            OutlinedButton(
              style: _chipStyle,
              onPressed: () =>
                  controller.startFixed(FocusTimerController.fifteenMinutes),
              child: const Text('15분'),
            ),
            OutlinedButton(
              style: _chipStyle,
              onPressed: () => _pickCustomDuration(context),
              child: const Text('사용자 설정'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: theme.textTheme.bodySmall,
          ),
          onPressed: controller.startTwoMinutes,
          child: const Text('2분만 시작'),
        ),
      ],
    );
  }
}

class _RunningTimerCard extends StatelessWidget {
  const _RunningTimerCard({required this.state, required this.controller});

  final FocusTimerState state;
  final FocusTimerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final remaining = state.remainingAt(now);
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    final label = state.phase == FocusTimerPhase.focus ? '집중 중' : '휴식 중';
    final timeText =
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: CircularProgressIndicator(
                      value: state.progressAt(now),
                      strokeWidth: 5,
                    ),
                  ),
                  Semantics(
                    label: '$label, 남은 시간 $timeText',
                    child: Text(timeText, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.isRunning)
                  OutlinedButton(
                    style: _TimerPicker._chipStyle,
                    onPressed: controller.pause,
                    child: const Text('일시정지'),
                  )
                else
                  OutlinedButton(
                    style: _TimerPicker._chipStyle,
                    onPressed: controller.resume,
                    child: const Text('계속'),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: controller.cancel,
                  child: const Text('취소'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
