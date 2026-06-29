import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/features/help/help_page.dart';

void main() {
  Widget wrap() => const MaterialApp(home: HelpPage());

  testWidgets('shows every section title, collapsed by default except FAQ', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    for (final title in const [
      '오늘 화면 (다이얼)',
      '구간 관리',
      "'지금' 화면 (Focus)",
      '메모',
      '체크인',
      '알람·알림',
      '스트릭과 완료 효과',
      '설정',
      '자주 묻는 질문',
    ]) {
      expect(find.text(title), findsOneWidget);
    }

    // FAQ starts expanded (most useful at a glance); the rest don't, so a
    // bullet from one of the others shouldn't be on screen yet.
    expect(find.textContaining('구간은 몇 개까지'), findsOneWidget);
    expect(find.textContaining('색깔 호 하나가 구간 하나'), findsNothing);
  });

  testWidgets('expanding a section reveals its bullets', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('오늘 화면 (다이얼)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('색깔 호 하나가 구간 하나'), findsOneWidget);
  });
}
