import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/checkin.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/checkin/checkin_page.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  // CheckinPage's history section can add several ListTiles -- on the
  // default 800x600 test surface, ones past the fold aren't even inflated
  // into elements (Sliver virtualization), the same class of issue
  // segment_form_page_test.dart's 저장 button hit. A tall surface keeps
  // everything built and findable without scrolling.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CheckinPage()),
    );
  }

  testWidgets('최근 기록 is always visible, with a placeholder when empty', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('최근 기록'), findsOneWidget);
    expect(find.text('아직 체크인 기록이 없어요.'), findsOneWidget);
    expect(find.bySemanticsLabel('기분 추가'), findsOneWidget);
    // No 메모 FAB to handle here -- the global one is already covered by
    // other screens' tests; just confirm it's mounted at all.
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
  });

  testWidgets('기분 추가 opens a dialog; 저장 is disabled until both mood and energy '
      'are picked', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('기분 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('🙂'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byIcon(Icons.bolt).at(2)); // 3rd bolt -- energy 3
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'picking mood/energy and saving in the dialog closes it and shows 오늘 in '
    '최근 기록',
    (tester) async {
      final repo = FakePlannerRepository();
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('기분 추가'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('😄')); // mood 5
      await tester.tap(find.byIcon(Icons.bolt).at(3)); // energy 4
      await tester.enterText(find.byType(TextField), '오늘은 꽤 괜찮았다');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();

      final saved = await repo.watchCheckins().first;
      expect(saved.single.mood, 5);
      expect(saved.single.energy, 4);
      expect(saved.single.note, '오늘은 꽤 괜찮았다');

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('아직 체크인 기록이 없어요.'), findsNothing);
      expect(find.text('오늘'), findsOneWidget);
      expect(find.text('기분 5/5'), findsOneWidget);
      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('오늘은 꽤 괜찮았다'), findsOneWidget);
      // The FAB now offers to edit, not add, today's already-saved entry.
      expect(find.bySemanticsLabel('기분 수정'), findsOneWidget);
      expect(find.bySemanticsLabel('기분 추가'), findsNothing);
    },
  );

  testWidgets(
    "tapping today's row opens the dialog pre-filled, and saving updates it",
    (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveCheckin(Checkin.today(mood: 2, energy: 1, note: '힘든 하루'));

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('오늘'), findsOneWidget);
      expect(find.text('기분 2/5'), findsOneWidget);
      expect(find.bySemanticsLabel('기분 수정'), findsOneWidget);

      await tester.tap(find.text('오늘'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.widgetWithText(TextField, '힘든 하루'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '수정하기'), findsOneWidget);

      await tester.tap(find.text('😄')); // change mood to 5
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '수정하기'));
      await tester.pumpAndSettle();

      final saved = await repo.watchCheckins().first;
      expect(saved.single.mood, 5);
      expect(saved.single.energy, 1);
      expect(saved.single.note, '힘든 하루');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('기분 5/5'), findsOneWidget);
    },
  );

  testWidgets("기분 수정 FAB also opens the dialog pre-filled with today's entry", (
    tester,
  ) async {
    final repo = FakePlannerRepository();
    await repo.saveCheckin(Checkin.today(mood: 4, energy: 4, note: '괜찮은 날'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('기분 수정'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(TextField, '괜찮은 날'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '수정하기'), findsOneWidget);
  });

  testWidgets(
    'autoOpenMoodDialog opens the dialog as soon as the page is built '
    '(daily reminder notification tap)',
    (tester) async {
      final repo = FakePlannerRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: CheckinPage(autoOpenMoodDialog: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '저장'), findsOneWidget);
    },
  );

  testWidgets(
    'past entries show mood/energy as emoji+score and a one-line note preview',
    (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveCheckin(
        Checkin.today(mood: 3, energy: 3, at: DateTime(2026, 6, 27)),
      );
      await repo.saveCheckin(
        Checkin.today(
          mood: 5,
          energy: 5,
          note: '최고의 날',
          at: DateTime(2026, 6, 28),
        ),
      );

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('최근 기록'), findsOneWidget);
      expect(find.text('😄'), findsOneWidget); // mood 5 emoji for 6/28
      expect(find.text('😐'), findsOneWidget); // mood 3 emoji for 6/27
      expect(find.text('기분 5/5'), findsOneWidget);
      expect(find.text('기분 3/5'), findsOneWidget);
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('3/5'), findsOneWidget);
      expect(find.text('최고의 날'), findsOneWidget);

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(tiles.length, 2);
      // Newest (6/28) listed before the older (6/27) entry, and not tappable.
      expect((tiles.first.title as Text).data, '6월 28일');
      expect((tiles.last.title as Text).data, '6월 27일');
      expect(tiles.first.onTap, isNull);
      expect(tiles.last.onTap, isNull);
    },
  );

  testWidgets('swiping a past entry away and confirming deletes it', (
    tester,
  ) async {
    final repo = FakePlannerRepository();
    await repo.saveCheckin(
      Checkin.today(
        mood: 3,
        energy: 3,
        note: '지울 기록',
        at: DateTime(2026, 6, 27),
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('지울 기록'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved, isEmpty);
    expect(find.text('아직 체크인 기록이 없어요.'), findsOneWidget);
  });

  testWidgets('swiping a past entry away and cancelling keeps it', (
    tester,
  ) async {
    final repo = FakePlannerRepository();
    await repo.saveCheckin(
      Checkin.today(
        mood: 3,
        energy: 3,
        note: '남길 기록',
        at: DateTime(2026, 6, 27),
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('남길 기록'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved.single.note, '남길 기록');
    expect(find.text('남길 기록'), findsOneWidget);
  });

  testWidgets("swiping today's entry away and confirming deletes it too "
      '(brings back the create form)', (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveCheckin(Checkin.today(mood: 4, energy: 4, note: '오늘 기록'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('오늘 기록'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved, isEmpty);
    expect(find.bySemanticsLabel('기분 추가'), findsOneWidget);
    expect(find.text('아직 체크인 기록이 없어요.'), findsOneWidget);
  });
}
