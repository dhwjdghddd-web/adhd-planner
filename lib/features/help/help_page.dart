import 'package:flutter/material.dart';

/// 앱 사용법을 언제든 다시 찾아볼 수 있는 도움말 페이지. 처음 한 번만 보여주는
/// 온보딩과는 별개로, 설정에서 항상 들어올 수 있다. 아코디언(ExpansionTile)
/// 섹션으로 나눠 필요한 부분만 펼쳐보게 한다.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도움말')),
      body: ListView(
        children: const [
          _HelpSection(
            title: '오늘 화면 (다이얼)',
            icon: Icons.donut_large,
            bullets: [
              '하루 24시간을 도는 원형 시계예요. 색깔 호 하나가 구간 하나를 나타내요.',
              '호를 탭하면 그 구간의 \'지금\' 화면으로 들어가요. 지난 구간도 들어가서 체크할 수 있어요.',
              '체크 표시는 오늘 완료한 구간, 별 표시는 \'오늘의 중요 항목\'으로 정한 구간이에요.',
              "AppBar의 번개 아이콘으로 '다음 한 행동'(지금/다음 구간만 크게 보여주는 단순한 화면)으로 바꿀 수 있어요.",
            ],
          ),
          _HelpSection(
            title: '구간 관리',
            icon: Icons.tune,
            bullets: [
              "구간(블록)은 시간 범위 + 체크리스트 + 알람을 한 번에 담는 단위예요. AppBar의 '구간 관리'에서 추가·수정·삭제해요.",
              '구간 개수에 제한은 없어요. 마음대로 추가해도 괜찮아요.',
              '시간이 겹쳐도 만들 수 있어요 — 경고만 보여주고 막지는 않아요. 다이얼에서는 안쪽 레인으로 겹쳐 보여줘요.',
              '구간 관리 화면에서 별 아이콘을 눌러 그 구간을 \'오늘의 중요 항목(MIT)\'으로 표시할 수 있어요.',
              '구간 알람은 끄고 켤 수 있고, 시작 전에 미리 알려주는 \'전환 예고\'도 따로 켤 수 있어요.',
            ],
          ),
          _HelpSection(
            title: "'지금' 화면 (Focus)",
            icon: Icons.center_focus_strong,
            bullets: [
              '지금 시각에 해당하는 구간이 전체 화면으로 떠요. 체크리스트 항목을 하나씩 체크하거나 \'모두 완료\'를 눌러요.',
              '구간이 끝나기까지 남은 시간이 위쪽 원형 그래픽에 표시돼요.',
              "원하면 짧은 집중 타이머(포모도로 등)를 따로 시작할 수 있어요.",
              "이름에 '수면'이 들어간 구간(또는 침대 아이콘 구간)은 화면이 어두워지고 천천히 숨쉬기 가이드가 나와요 — 체크리스트 대신 폰을 내려놓도록 도와줘요.",
            ],
          ),
          _HelpSection(
            title: '메모',
            icon: Icons.edit_note,
            bullets: [
              '어느 화면에서든 좌하단 연필 아이콘으로 생각난 걸 바로 적을 수 있어요.',
              '적어둔 메모는 메모함에서 모아보고, 확인했으면 체크 표시를 해요.',
              '오래 방치된 메모는 앱이 한 번씩 \'이 메모, 아직이에요\'라고 알려줘요.',
              '메모를 길게 누르면 구간의 체크리스트 항목으로 바로 옮길 수 있어요.',
            ],
          ),
          _HelpSection(
            title: '체크인',
            icon: Icons.mood_outlined,
            bullets: [
              '하루 한 번, 기분(이모지 5단계)과 에너지(번개 5단계), 메모를 남겨요.',
              "AppBar의 웃는 얼굴 아이콘으로 들어가고, 우하단 버튼으로 기록을 추가·수정해요.",
              '최근 기록은 화면에 쭉 나열되고, 옆으로 스와이프하면 지울 수 있어요.',
              '설정에서 매일 알림 받을 시간을 정해둘 수도 있어요.',
            ],
          ),
          _HelpSection(
            title: '알람·알림',
            icon: Icons.alarm,
            bullets: [
              '구간마다 알람 소리·진동 패턴을 고를 수 있고, 무음 모드에서도 진동이 울리도록 만들어져 있어요.',
              "알람을 못 들었을 때를 위한 '스누즈'(다시 알림) 시간도 정할 수 있어요.",
              "설정 맨 아래 '알림 채널'에서 각 알림 종류(구간 알람/전환 예고/타이머/체크인)별로 안드로이드 시스템 설정으로 바로 이동할 수 있어요.",
            ],
          ),
          _HelpSection(
            title: '스트릭과 완료 효과',
            icon: Icons.local_fire_department,
            bullets: [
              '오늘 할 일을 다 끝내면 축하 효과가 떠요. 절반 정도만 해도 작은 응원 메시지가 따로 떠요.',
              '한번 쌓인 스트릭(연속 달성일)은 나중에 구간을 바꿔도 줄어들지 않아요 — 그날 달성한 기록은 그대로 보존돼요.',
            ],
          ),
          _HelpSection(
            title: '설정',
            icon: Icons.settings_outlined,
            bullets: [
              '테마(라이트/다크/시스템), 글자 크기, \'동작 줄이기\'(애니메이션을 차분하게)를 바꿀 수 있어요.',
              'Google 계정을 연결하면 기기를 바꿔도 데이터가 그대로 따라와요. 연결은 로그인이 아니라 지금 쓰던 데이터에 계정을 붙이는 개념이에요.',
            ],
          ),
          _HelpSection(
            title: '자주 묻는 질문',
            icon: Icons.help_outline,
            initiallyExpanded: true,
            bullets: [
              'Q. 구간은 몇 개까지 만들 수 있나요?\nA. 제한 없어요. 원하는 만큼 추가해도 괜찮아요.',
              'Q. 구간 시간이 겹치면 안 되나요?\nA. 경고만 뜨고 저장은 막지 않아요. 다이얼에서 겹친 구간은 안쪽 레인에 따로 그려져요.',
              'Q. 오늘 할 일을 다 못해도 괜찮나요?\nA. 네. 절반만 해도 응원 메시지가 따로 뜨고, 이미 쌓인 스트릭은 줄어들지 않아요.',
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.title,
    required this.icon,
    required this.bullets,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<String> bullets;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      initiallyExpanded: initiallyExpanded,
      children: [
        for (final bullet in bullets)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(bullet, style: Theme.of(context).textTheme.bodyMedium),
          ),
      ],
    );
  }
}
