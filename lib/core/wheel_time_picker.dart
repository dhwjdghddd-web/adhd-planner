import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'screen_mode.dart';

/// Shared time-of-day picker used wherever a minute-of-day is chosen (block
/// start/end, check-in reminder time). Always the [CupertinoDatePicker] wheel
/// (never Material's dial/keyboard picker -- a deliberate project convention),
/// in a bottom sheet with a 확인 button. Returns the picked minute-of-day, or
/// null if dismissed.
///
/// `isScrollControlled` so a short (cover) screen isn't capped at the default
/// 9/16 height, which the wheel + button would overflow.
Future<int?> pickWheelMinute(BuildContext context, int initialMinute) async {
  var pickedMinute = initialMinute;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: isCompactLayout(sheetContext) ? 150 : 216,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              initialDateTime: DateTime(
                2000,
                1,
                1,
                initialMinute ~/ 60,
                initialMinute % 60,
              ),
              onDateTimeChanged: (dt) => pickedMinute = dt.hour * 60 + dt.minute,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('확인'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return confirmed == true ? pickedMinute : null;
}
