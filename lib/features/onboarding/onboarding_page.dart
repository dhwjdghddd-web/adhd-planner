import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../segments/segments_controller.dart';
import '../settings/settings_controller.dart';

const _uuid = Uuid();

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    icon: Icons.tune,
    title: '구간으로 하루 나누기',
    body: '오전·오후·퇴근 후처럼 하루를 구간으로 나눠서 시작해보세요.',
  ),
  _Slide(
    icon: Icons.checklist,
    title: '루틴으로 할 일 배치',
    body: '구간 안에 시간을 정해 루틴을 추가하면 원형 시계판에 바로 표시돼요.',
  ),
  _Slide(
    icon: Icons.notifications_active_outlined,
    title: '알림으로 안 놓치기',
    body: '알림 권한을 허용하면 루틴 시작 시각과 전환 예고를 알려드려요.',
  ),
  _Slide(
    icon: Icons.edit_note,
    title: '메모로 잡생각 정리',
    body: '화면 아무 곳에서나 빠른 메모 버튼으로 1탭에 캡처할 수 있어요.',
  ),
];

/// First-run guide shown once (gated by `AppSettings.onboardingComplete`,
/// see app.dart). The last slide offers an optional 오전/오후/저녁 segment
/// template so a brand-new user has something on the dial immediately.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool withDefaultSegments}) async {
    if (withDefaultSegments) {
      final segments = ref.read(segmentsControllerProvider);
      await segments.upsert(Segment(
        id: _uuid.v4(),
        name: '오전',
        colorValue: kSegmentPalette[0].toARGB32(),
        iconKey: 'wb_sunny',
        startMinute: 6 * 60,
        endMinute: 12 * 60,
        order: 0,
      ));
      await segments.upsert(Segment(
        id: _uuid.v4(),
        name: '오후',
        colorValue: kSegmentPalette[1].toARGB32(),
        iconKey: 'wb_twilight',
        startMinute: 12 * 60,
        endMinute: 18 * 60,
        order: 1,
      ));
      await segments.upsert(Segment(
        id: _uuid.v4(),
        name: '저녁',
        colorValue: kSegmentPalette[2].toARGB32(),
        iconKey: 'nights_stay',
        startMinute: 18 * 60,
        endMinute: 22 * 60,
        order: 2,
      ));
    }

    final settings = ref.read(settingsProvider).value ?? const AppSettings.defaults();
    await ref.read(settingsControllerProvider).save(settings.copyWith(onboardingComplete: true));
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.ease);
    } else {
      _finish(withDefaultSegments: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _finish(withDefaultSegments: false),
                child: const Text('건너뛰기'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: [for (final slide in _slides) _SlideView(slide: slide)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  if (isLast) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _finish(withDefaultSegments: true),
                        child: const Text('기본 구간(오전·오후·저녁) 만들고 시작하기'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _finish(withDefaultSegments: false),
                        child: const Text('그냥 시작하기'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _next,
                        child: const Text('다음'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(slide.icon, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(slide.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(slide.body, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
