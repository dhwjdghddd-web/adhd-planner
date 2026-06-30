import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/error_view.dart';

void main() {
  testWidgets('shows a friendly message, not the raw exception', (
    tester,
  ) async {
    final error = Exception('FirebaseException: PERMISSION_DENIED secret/path');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: errorView(error))),
    );

    expect(find.text('잠시 문제가 생겼어요.\n잠시 후 다시 시도해 주세요.'), findsOneWidget);
    // The raw exception text must never reach the screen.
    expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('matches the AsyncValue.error callback shape (error, stack)', (
    tester,
  ) async {
    // errorView is passed directly as `error: errorView` in the widgets, so it
    // must be callable as a (Object, StackTrace) => Widget.
    final Widget Function(Object, StackTrace) cb = errorView;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: cb('boom', StackTrace.current))),
    );
    expect(find.textContaining('잠시 문제가 생겼어요'), findsOneWidget);
  });
}
