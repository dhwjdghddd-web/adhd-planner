import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen_mode.dart';
import '../../data/models/checkin.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../memos/quick_add_button.dart';
import 'checkin_controller.dart';

/// T8: a short daily mood/energy self-observation ritual -- not medical data,
/// just "오늘 기분/에너지가 어땠는지" plus an optional note. The page itself
/// is just 최근 기록 (today included, newest first); a dedicated FAB --
/// mirroring the 메모 FAB this app already mounts bottom-left on every
/// screen -- opens the mood/energy/note picker as a dialog, prefilled with
/// today's pick when there already is one.
class CheckinPage extends ConsumerStatefulWidget {
  const CheckinPage({super.key, this.autoOpenMoodDialog = false});

  /// True when pushed from the daily check-in reminder notification (see
  /// app.dart's _CheckinAlertLauncher) -- tapping it should land straight in
  /// the dialog rather than requiring an extra tap on the FAB once here.
  final bool autoOpenMoodDialog;

  @override
  ConsumerState<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends ConsumerState<CheckinPage> {
  bool _autoOpened = false;

  Future<void> _saveToday(int mood, int energy, String? note) {
    return ref
        .read(checkinControllerProvider)
        .save(mood: mood, energy: energy, note: note);
  }

  Future<void> _openMoodDialog(Checkin? today) {
    return showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: _CheckinForm(
              initialMood: today?.mood,
              initialEnergy: today?.energy,
              initialNote: today?.note,
              buttonLabel: today == null ? '저장' : '수정하기',
              onSubmit: (mood, energy, note) async {
                await _saveToday(mood, energy, note);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkins = ref.watch(checkinsProvider).value ?? const [];
    final todayKey = dayKeyFor();

    Checkin? today;
    for (final c in checkins) {
      if (c.dateKey == todayKey) {
        today = c;
        break;
      }
    }

    if (widget.autoOpenMoodDialog && !_autoOpened) {
      _autoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMoodDialog(today);
      });
    }

    final sorted = [...checkins]
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));

    return Scaffold(
      appBar: AppBar(title: const Text('체크인')),
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('최근 기록', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: sorted.isEmpty
                    // Centered in the remaining space below the header (not
                    // just another low-key inline line) -- a previous,
                    // muted-outline-colored version was reported as nearly
                    // invisible.
                    ? Center(
                        child: Text(
                          '아직 체크인 기록이 없어요.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final c in sorted)
                            _HistoryTile(
                              checkin: c,
                              isToday: c.dateKey == todayKey,
                              onTap: c.dateKey == todayKey
                                  ? () => _openMoodDialog(today)
                                  : null,
                              onDelete: () => ref
                                  .read(checkinControllerProvider)
                                  .delete(c.dateKey),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isCompactLayout(context)
          ? compactCornerFabs(
              actions: [
                Semantics(
                  label: today == null ? '기분 추가' : '기분 수정',
                  child: FloatingActionButton.small(
                    heroTag: 'checkin-add',
                    onPressed: () => _openMoodDialog(today),
                    child: const Icon(Icons.add_reaction_outlined),
                  ),
                ),
              ],
            )
          : MultiFabRow(
              left: const GlobalQuickAddButton(),
              right: Semantics(
                label: today == null ? '기분 추가' : '기분 수정',
                child: FloatingActionButton(
                  onPressed: () => _openMoodDialog(today),
                  child: const Icon(Icons.add_reaction_outlined),
                ),
              ),
            ),
      floatingActionButtonLocation: screenFabLocation(context),
    );
  }
}

/// Shared mood/energy/note picker, used both inline (creating today's entry
/// when none exists yet) and inside the edit bottom sheet (updating today's
/// existing one) -- the two flows only differ in starting values and what
/// happens after a successful submit.
class _CheckinForm extends StatefulWidget {
  const _CheckinForm({
    this.initialMood,
    this.initialEnergy,
    this.initialNote,
    required this.buttonLabel,
    required this.onSubmit,
  });

  final int? initialMood;
  final int? initialEnergy;
  final String? initialNote;
  final String buttonLabel;
  final Future<void> Function(int mood, int energy, String? note) onSubmit;

  @override
  State<_CheckinForm> createState() => _CheckinFormState();
}

class _CheckinFormState extends State<_CheckinForm> {
  int? _mood;
  int? _energy;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _mood = widget.initialMood;
    _energy = widget.initialEnergy;
    _noteController = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _mood != null && _energy != null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final note = _noteController.text.trim();
    await widget.onSubmit(_mood!, _energy!, note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('오늘 기분은 어때요?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _MoodRow(selected: _mood, onSelect: (v) => setState(() => _mood = v)),
        const SizedBox(height: 24),
        Text('오늘 에너지는 어때요?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _EnergyRow(
          selected: _energy,
          onSelect: (v) => setState(() => _energy = v),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: '메모 (선택)',
            hintText: '오늘 하루는 어땠나요?',
            alignLabelWithHint: true,
            // The plain outline border was barely visible against a dialog's
            // white background -- a light fill makes the field's bounds
            // obvious even before the border itself draws attention.
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.buttonLabel),
          ),
        ),
      ],
    );
  }
}

class _MoodRow extends StatelessWidget {
  const _MoodRow({required this.selected, required this.onSelect});

  final int? selected;
  final ValueChanged<int> onSelect;

  static const _emojis = ['😞', '😕', '😐', '🙂', '😄'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        final level = i + 1;
        final isSelected = selected == level;
        return Semantics(
          label: '기분 $level단계',
          selected: isSelected,
          child: InkWell(
            onTap: () => onSelect(level),
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? theme.colorScheme.primaryContainer : null,
              ),
              child: Text(_emojis[i], style: const TextStyle(fontSize: 26)),
            ),
          ),
        );
      }),
    );
  }
}

class _EnergyRow extends StatelessWidget {
  const _EnergyRow({required this.selected, required this.onSelect});

  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        final level = i + 1;
        // Rating-bar style: every bolt up to and including the selected
        // level is filled, not just the tapped one -- "에너지 4" should read
        // as "4 out of 5", the same way a star rating does.
        final filled = selected != null && level <= selected!;
        return Semantics(
          label: '에너지 $level단계',
          selected: selected == level,
          child: InkWell(
            onTap: () => onSelect(level),
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              // A faint background circle behind every slot (not just the
              // filled ones) so all 5 read as distinct tappable targets even
              // before tapping -- the bare outline-grey bolt on its own was
              // reported as nearly invisible.
              decoration: filled
                  ? null
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
              child: Icon(
                Icons.bolt,
                size: 26,
                color: filled
                    ? Colors.amber[700]
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.checkin,
    required this.isToday,
    this.onTap,
    required this.onDelete,
  });

  final Checkin checkin;
  final bool isToday;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = checkin.note;
    final dateLabel = isToday ? '오늘' : _formatDate(checkin.dateKey);

    // Same swipe-to-delete shape as memo_inbox_page.dart's Dismissible: right-
    // to-left swipe, errorContainer background, confirm dialog before it
    // actually deletes (no undo afterwards, so a stray swipe can't silently
    // wipe a day's record).
    return Dismissible(
      key: ValueKey(checkin.dateKey),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Text(
          _MoodRow._emojis[checkin.mood - 1],
          style: const TextStyle(fontSize: 28),
        ),
        title: Text(
          dateLabel,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isToday ? FontWeight.bold : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('기분 ${checkin.mood}/5', style: theme.textTheme.bodySmall),
                const SizedBox(width: 12),
                Icon(Icons.bolt, size: 14, color: Colors.amber[700]),
                Text('${checkin.energy}/5', style: theme.textTheme.bodySmall),
              ],
            ),
            if (note != null && note.isNotEmpty)
              Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        trailing: isToday ? const Icon(Icons.edit_outlined, size: 18) : null,
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('체크인 기록 삭제'),
        content: const Text('이 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  static String _formatDate(String dateKey) {
    final date = DateTime.parse(dateKey);
    return '${date.month}월 ${date.day}일';
  }
}
