import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/app_settings.dart';
import '../../data/providers.dart';
import '../../services/alarm_sound_picker.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../help/help_page.dart';
import '../memos/quick_add_button.dart';
import 'settings_controller.dart';

/// Permission status, theme/font/motion controls, and an anonymous-account
/// placeholder. Every control here writes straight through to [AppSettings]
/// via [SettingsController] so changes (dark mode, font size) are reflected
/// app-wide immediately — see app.dart, which watches the same provider.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  PermissionStatus? _notification;
  PermissionStatus? _exactAlarm;
  PermissionStatus? _microphone;

  /// 스크롤 위치를 State에서 관리: 계정 전환으로 화면이 리빌드돼도 위치 유지.
  final ScrollController _scrollController = ScrollController();

  /// 마지막으로 성공적으로 받은 설정값. 계정 전환 중 loading 구간에
  /// 이 값을 그대로 표시해 깜빡임(loading → data)을 막는다.
  AppSettings? _lastKnownSettings;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Defensive: on a real device a failed platform call here would just be
  // an unusual permission plugin hiccup, but it's also exactly what happens
  // under `flutter test` (no platform channel at all) — either way, missing
  // status should degrade to "확인 중..." rather than crash the page.
  Future<PermissionStatus?> _safeStatus(Permission permission) async {
    try {
      return await permission.status;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshPermissions() async {
    final notification = await _safeStatus(Permission.notification);
    final exactAlarm = await _safeStatus(Permission.scheduleExactAlarm);
    final microphone = await _safeStatus(Permission.microphone);
    if (!mounted) return;
    setState(() {
      _notification = notification;
      _exactAlarm = exactAlarm;
      _microphone = microphone;
    });

    if (exactAlarm == null) return;
    final settings = ref.read(settingsProvider).value;
    if (settings != null &&
        settings.exactAlarmGranted != exactAlarm.isGranted) {
      await ref
          .read(settingsControllerProvider)
          .save(settings.copyWith(exactAlarmGranted: exactAlarm.isGranted));
    }
  }

  Future<void> _requestOrOpenSettings(Permission permission) async {
    try {
      final current = await permission.status;
      if (current.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await permission.request();
      }
    } catch (_) {
      // No platform channel available — nothing to request.
    }
    await _refreshPermissions();
  }

  // Alarm channels are immutable once created, so a sound/vibration change
  // only takes effect once everything gets rescheduled under the new
  // channel id (see notification_service.dart) — without this, the choice
  // here would silently do nothing until the next full app restart.
  Future<void> _rescheduleAlarms(AppSettings settings) async {
    try {
      final segments = ref.read(segmentsProvider).value ?? const [];
      await ref
          .read(notificationServiceProvider)
          .rescheduleAll(segments, settings);
    } catch (_) {
      // No platform channel available (e.g. under flutter test) — the
      // setting itself is already saved and will still apply next launch.
    }
  }

  Future<void> _pickAlarmSound(AppSettings settings) async {
    final picked = await pickAlarmSound(currentUri: settings.alarmSoundUri);
    if (picked == null) return;
    final updated = settings.copyWith(
      alarmSoundUri: picked.uri,
      alarmSoundLabel: picked.label,
    );
    await ref.read(settingsControllerProvider).save(updated);
    await _rescheduleAlarms(updated);
  }

  Future<void> _resetAlarmSound(AppSettings settings) async {
    final updated = settings.copyWith(clearAlarmSound: true);
    await ref.read(settingsControllerProvider).save(updated);
    await _rescheduleAlarms(updated);
  }

  Future<void> _setVibrationPattern(
    AppSettings settings,
    AlarmVibrationPattern pattern,
  ) async {
    unawaited(previewVibration(vibrationPatternFor(pattern)));
    final updated = settings.copyWith(vibrationPattern: pattern);
    await ref.read(settingsControllerProvider).save(updated);
    await _rescheduleAlarms(updated);
  }

  // No reschedule needed: snoozeMinutes is only read at the moment "N분 뒤
  // 다시" is actually pressed on AlarmScreen, not baked into any already-armed
  // schedule the way sound/vibration are.
  Future<void> _setSnoozeMinutes(AppSettings settings, int minutes) {
    return ref
        .read(settingsControllerProvider)
        .save(settings.copyWith(snoozeMinutes: minutes));
  }

  Future<void> _setCheckinAlarmEnabled(
    AppSettings settings,
    bool enabled,
  ) async {
    final updated = settings.copyWith(checkinAlarmEnabled: enabled);
    await ref.read(settingsControllerProvider).save(updated);
    await _rescheduleAlarms(updated);
  }

  // A scrollable 24h wheel (no AM/PM, no separate keyboard-entry mode)
  // instead of the standard dial/keyboard showTimePicker -- same picker
  // segment_form_page.dart's block start/end time uses, for the same time-
  // of-day input everywhere in this app.
  Future<int?> _pickWheelMinute(int initialMinute) async {
    var pickedMinute = initialMinute;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 216,
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
                onDateTimeChanged: (dt) =>
                    pickedMinute = dt.hour * 60 + dt.minute,
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

  Future<void> _pickCheckinAlarmTime(AppSettings settings) async {
    final picked = await _pickWheelMinute(settings.checkinAlarmMinuteOfDay);
    if (picked == null || !mounted) return;
    final updated = settings.copyWith(checkinAlarmMinuteOfDay: picked);
    await ref.read(settingsControllerProvider).save(updated);
    await _rescheduleAlarms(updated);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    // 새 값이 도착하면 캐시를 갱신한다.
    final incoming = settingsAsync.valueOrNull;
    if (incoming != null) _lastKnownSettings = incoming;

    // 표시할 설정값: 캐시(이전 값)를 우선 사용 → loading 구간에도 화면이
    // 그대로 유지되어 깜빡임이 없다.
    final settings = _lastKnownSettings;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      // Shrinks the visible body area itself (rather than padding inside
      // the ListView, which only shows up once scrolled all the way down)
      // so content never reaches the global bottom-left quick-add FAB even
      // before scrolling.
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: settings == null
            // 최초 로드 시에만 스피너 표시 (캐시가 없을 때)
            ? settingsAsync.when(
                data: (s) {
                  _lastKnownSettings = s;
                  return _buildBody(s);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('오류: $e')),
              )
            // 캐시가 있으면 에러가 아닌 한 항상 본문을 표시
            : settingsAsync.hasError
            ? Center(child: Text('오류: ${settingsAsync.error}'))
            : _buildBody(settings),
      ),
      floatingActionButton: const MultiFabRow(left: GlobalQuickAddButton()),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _linkGoogle() async {
    final outcome = await ref.read(authServiceProvider).linkGoogle();
    if (!mounted) return;
    switch (outcome) {
      case AuthOutcome.linked:
        showAppSnackBar(context, const Text('구글 계정이 연결됐어요.'));
      case AuthOutcome.signedIn:
        showAppSnackBar(
          context,
          const Text('기존 구글 계정으로 로그인했어요. 그 계정의 데이터를 불러옵니다.'),
        );
      case AuthOutcome.cancelled:
        break; // 조용히 무시
      case AuthOutcome.failed:
        showAppSnackBar(context, const Text('연결에 실패했어요. 다시 시도해 주세요.'));
    }
  }

  // 로그아웃하면 이 기기는 빈 익명 계정으로 돌아갑니다(데이터는 계정에 남아
  // 있고 다시 로그인하면 복구). 확인 다이얼로그로 실수로 누른 경우를 막는다.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text(
          '로그아웃하면 이 기기는 빈 익명 계정으로 시작해요.\n'
          '같은 구글 계정으로 다시 연결하면 데이터가 복구돼요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Cancel this device's alarms *before* signing out, while the logging-out
    // account's blocks are still readable. Relying only on _AccountAlarmSync
    // (app.dart) to notice the uid change isn't enough: the new anonymous
    // account starts empty, so by the time it reschedules there's no block list
    // left to cancel the previous account's still-armed native Vibrator alarms
    // from -- which is how a logged-out device could still ring a block the old
    // account had set.
    final knownIds = (ref.read(segmentsProvider).value ?? const [])
        .expand((s) => s.notificationIds)
        .toList();
    try {
      await ref
          .read(notificationServiceProvider)
          .cancelEverything(knownIds: knownIds);
    } catch (_) {
      // No platform channel (e.g. flutter test) — nothing scheduled to clear.
    }
    // Drop any alarm alert that was queued for the account we're leaving, so it
    // can't pop a stale "구간 not found" dialog against the new empty one.
    pendingAlarmAlert.value = null;

    await ref.read(authServiceProvider).signOutToAnonymous();
    if (!mounted) return;
    showAppSnackBar(context, const Text('로그아웃했어요.'));
  }

  Widget _buildBody(AppSettings settings) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final isSignedIn = user != null && !user.isAnonymous;
    final controller = ref.read(settingsControllerProvider);

    // ScrollController를 State에서 유지하여 리빌드 시 스크롤 위치 보존.
    return ListView(
      controller: _scrollController,
      children: [
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('도움말'),
          subtitle: const Text('구간·메모·체크인 등 기능을 다시 찾아볼 수 있어요.'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HelpPage())),
        ),
        const Divider(),
        const _SectionHeader('권한'),
        _PermissionRow(
          icon: Icons.notifications_outlined,
          label: '알림',
          status: _notification,
          onTap: () => _requestOrOpenSettings(Permission.notification),
        ),
        _PermissionRow(
          icon: Icons.alarm,
          label: '정확한 알람',
          status: _exactAlarm,
          onTap: () => _requestOrOpenSettings(Permission.scheduleExactAlarm),
        ),
        _PermissionRow(
          icon: Icons.mic_none,
          label: '마이크',
          status: _microphone,
          onTap: () => _requestOrOpenSettings(Permission.microphone),
        ),
        const Divider(),
        const _SectionHeader('알람 소리·진동'),
        ListTile(
          leading: const Icon(Icons.music_note_outlined),
          title: const Text('알람음'),
          subtitle: Text(settings.alarmSoundLabel ?? '기본 알람음'),
          trailing: settings.alarmSoundUri == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '기본 알람음으로',
                  onPressed: () => _resetAlarmSound(settings),
                ),
          onTap: () => _pickAlarmSound(settings),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('진동 패턴', style: Theme.of(context).textTheme.bodyMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pattern in AlarmVibrationPattern.values)
                ChoiceChip(
                  label: Text(pattern.label),
                  selected: settings.vibrationPattern == pattern,
                  onSelected: (_) => _setVibrationPattern(settings, pattern),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '스누즈 시간 (알람에서 "다시" 눌렀을 때)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in const [5, 10, 15])
                ChoiceChip(
                  label: Text('$minutes분'),
                  selected: settings.snoozeMinutes == minutes,
                  onSelected: (_) => _setSnoozeMinutes(settings, minutes),
                ),
            ],
          ),
        ),
        const Divider(),
        const _SectionHeader('체크인 알림'),
        SwitchListTile(
          title: const Text('하루 체크인 알림'),
          subtitle: const Text('지정한 시간에 기분/에너지를 기록하라고 알려드려요.'),
          value: settings.checkinAlarmEnabled,
          onChanged: (value) => _setCheckinAlarmEnabled(settings, value),
        ),
        ListTile(
          enabled: settings.checkinAlarmEnabled,
          leading: const Icon(Icons.access_time),
          title: const Text('알림 시간'),
          subtitle: Text(
            TimeOfDay(
              hour: settings.checkinAlarmMinuteOfDay ~/ 60,
              minute: settings.checkinAlarmMinuteOfDay % 60,
            ).format(context),
          ),
          onTap: settings.checkinAlarmEnabled
              ? () => _pickCheckinAlarmTime(settings)
              : null,
        ),
        const Divider(),
        const _SectionHeader('알림 채널'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '소리·진동·중요도를 더 세밀하게 바꾸려면 시스템 설정으로 이동하세요.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _ChannelSettingsRow(
          icon: Icons.alarm,
          label: '구간 알람',
          onTap: () => ref
              .read(notificationServiceProvider)
              .openChannelSettings(alarmChannelId(settings)),
        ),
        _ChannelSettingsRow(
          icon: Icons.notifications_active_outlined,
          label: '구간 전환 예고',
          onTap: () => ref
              .read(notificationServiceProvider)
              .openChannelSettings(leadWarningChannelId),
        ),
        _ChannelSettingsRow(
          icon: Icons.timer_outlined,
          label: '집중 타이머',
          onTap: () => ref
              .read(notificationServiceProvider)
              .openChannelSettings(focusTimerChannelId),
        ),
        _ChannelSettingsRow(
          icon: Icons.mood_outlined,
          label: '체크인 알림 채널',
          onTap: () => ref
              .read(notificationServiceProvider)
              .openChannelSettings(checkinChannelId),
        ),
        const Divider(),
        const _SectionHeader('화면'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(
                value: AppThemeMode.system,
                label: Text('시스템'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: AppThemeMode.light,
                label: Text('라이트'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                label: Text('다크'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) =>
                controller.save(settings.copyWith(themeMode: selection.first)),
          ),
        ),
        ListTile(
          title: Text('글자 크기 ${(settings.fontScale * 100).round()}%'),
          subtitle: Slider(
            value: settings.fontScale,
            min: 0.8,
            max: 2.0,
            divisions: 12,
            label: '${(settings.fontScale * 100).round()}%',
            onChanged: (value) =>
                controller.save(settings.copyWith(fontScale: value)),
          ),
        ),
        SwitchListTile(
          title: const Text('동작 줄이기'),
          subtitle: const Text('완료 효과의 컨페티·확대 애니메이션을 줄이고 정적인 표시로 대체해요.'),
          value: settings.reduceMotion,
          onChanged: (value) =>
              controller.save(settings.copyWith(reduceMotion: value)),
        ),
        SwitchListTile(
          title: const Text('화면 항상 켜두기'),
          subtitle: const Text('앱을 보고 있는 동안 화면이 꺼지지 않아요.'),
          value: settings.keepScreenOn,
          onChanged: (value) =>
              controller.save(settings.copyWith(keepScreenOn: value)),
        ),
        const Divider(),
        const _SectionHeader('계정'),
        // 계정 전환 중에는 AnimatedSwitcher로 자연스럽게 전환
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: ListTile(
            key: ValueKey(isSignedIn),
            leading: const Icon(Icons.person_outline),
            title: Text(isSignedIn ? (user.email ?? '로그인됨') : '익명으로 사용 중'),
            subtitle: Text(
              isSignedIn
                  ? '다른 기기에서 같은 구글 계정으로 로그인하면 이 데이터가 따라와요.'
                  : 'Google 계정을 연결하면 기기를 바꿔도 데이터가 유지돼요.',
            ),
            trailing: isSignedIn
                ? OutlinedButton(onPressed: _signOut, child: const Text('로그아웃'))
                : OutlinedButton(
                    onPressed: _linkGoogle,
                    child: const Text('Google 연결'),
                  ),
          ),
        ),
      ],
    );
  }
}

/// T10: one row per notification channel, deep-linking to Android's own
/// per-channel settings (sound/importance/vibration override) -- this app's
/// settings screen only ever exposes the broad app-level choices that feed
/// into a channel, never a per-channel override.
class _ChannelSettingsRow extends StatelessWidget {
  const _ChannelSettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final PermissionStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted ?? false;
    final permanentlyDenied = status?.isPermanentlyDenied ?? false;
    final statusText = status == null
        ? '확인 중...'
        : granted
        ? '허용됨'
        : permanentlyDenied
        ? '거부됨 (설정에서 변경)'
        : '거부됨';
    final statusIcon = granted ? Icons.check_circle : Icons.cancel_outlined;
    final statusColor = granted
        ? Colors.green
        : Theme.of(context).colorScheme.error;

    return Semantics(
      label: '$label 권한, $statusText',
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 16, color: statusColor),
            const SizedBox(width: 4),
            Text(statusText),
          ],
        ),
        trailing: granted
            ? null
            : TextButton(
                onPressed: onTap,
                child: Text(permanentlyDenied ? '설정 열기' : '요청'),
              ),
      ),
    );
  }
}
