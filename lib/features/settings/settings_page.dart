import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/app_settings.dart';
import '../../data/providers.dart';
import '../../services/alarm_sound_picker.dart';
import '../../services/notification_service.dart';
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

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
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
      final routines = ref.read(routinesProvider).value ?? const [];
      await ref
          .read(notificationServiceProvider)
          .rescheduleAll(routines, settings);
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

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      // Shrinks the visible body area itself (rather than padding inside
      // the ListView, which only shows up once scrolled all the way down)
      // so content never reaches the global bottom-left quick-add FAB even
      // before scrolling.
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: settingsAsync.when(
          data: _buildBody,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('오류: $e')),
        ),
      ),
    );
  }

  // Defensive for the same reason as _safeStatus: under `flutter test` there
  // is no Firebase app at all, so FirebaseAuth.instance itself throws.
  User? _currentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  Widget _buildBody(AppSettings settings) {
    final user = _currentUser();
    final controller = ref.read(settingsControllerProvider);

    return ListView(
      children: [
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
        const Divider(),
        const _SectionHeader('계정'),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(user == null || user.isAnonymous ? '익명으로 사용 중' : '로그인됨'),
          subtitle: const Text('Google 계정으로 업그레이드하면 기기를 바꿔도 데이터가 유지돼요.'),
          trailing: OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google 로그인은 추후 지원될 예정입니다.')),
            ),
            child: const Text('업그레이드'),
          ),
        ),
      ],
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
