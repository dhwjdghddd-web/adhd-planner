import 'package:flutter/material.dart';

import 'error_reporting.dart';

/// User-facing placeholder for a failed async load (an `AsyncValue.error`).
///
/// Shows a calm, friendly message instead of dumping the raw exception/stack
/// onto the screen (which leaked internals and read as a crash). The real
/// error is still logged for diagnosis -- and, once crash reporting is wired
/// up, [reportError] forwards it there too.
Widget errorView(Object error, [StackTrace? stackTrace]) {
  reportError(error, stackTrace, where: '화면 로드 실패');
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        '잠시 문제가 생겼어요.\n잠시 후 다시 시도해 주세요.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
