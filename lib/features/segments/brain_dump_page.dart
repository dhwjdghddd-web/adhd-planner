import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../services/speech_service.dart';
import 'segments_controller.dart';
import 'slot_suggester.dart';

const _uuid = Uuid();

/// "떠오르는 일들을 적어보기" -- list out whatever's on your mind (text or
/// voice, reusing the same capture UX as the memo quick-add sheet), then let
/// [suggestSlots] propose a same-day time for each one at once, rather than
/// having to time-box each thought yourself one at a time via 구간 추가.
/// Two phases in one page: list entry, then a preview where each suggested
/// time can still be nudged before the whole batch is created together.
class BrainDumpPage extends ConsumerStatefulWidget {
  const BrainDumpPage({super.key, @visibleForTesting this.debugNowMinuteOfDay});

  /// Test-only override for "now" (minute-of-day), used by [_suggestTimes]
  /// instead of the wall clock when set -- without this, a test run close to
  /// midnight could suggest fewer slots than expected (the same class of
  /// flake [FocusPage.debugNowMinuteOfDay] exists to avoid).
  final int? debugNowMinuteOfDay;

  @override
  ConsumerState<BrainDumpPage> createState() => _BrainDumpPageState();
}

class _BrainDumpPageState extends ConsumerState<BrainDumpPage> {
  final _controller = TextEditingController();
  final _items = <String>[];
  final _speech = SpeechService();
  bool _speechAvailable = false;
  bool _listening = false;

  // null while still listing items; set once "시각 자동 배치" is pressed.
  List<SuggestedSlot>? _preview;
  // How many of _items didn't fit before midnight and were dropped from
  // _preview -- surfaced as a warning rather than silently lost.
  int _notFittingCount = 0;

  @override
  void initState() {
    super.initState();
    _speech
        .init(
          // Reset the mic button when the recognizer stops on its own (e.g.
          // a no-speech silence timeout), not just on an explicit final result.
          onDone: () {
            if (mounted && _listening) setState(() => _listening = false);
          },
        )
        .then((available) {
          if (mounted) setState(() => _speechAvailable = available);
        });
  }

  @override
  void dispose() {
    _speech.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(text);
      _controller.clear();
    });
  }

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.startListening((text, isFinal) {
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        if (isFinal) _listening = false;
      });
    });
  }

  int _minuteOfNow() {
    final override = widget.debugNowMinuteOfDay;
    if (override != null) return override;
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  void _suggestTimes() {
    final segments = ref.read(segmentsProvider).value ?? const [];
    final anchor = anchorMinuteFor(_minuteOfNow(), segments);
    final suggested = suggestSlots(_items, segments, anchorMinute: anchor);
    setState(() {
      _preview = suggested;
      _notFittingCount = _items.length - suggested.length;
    });
  }

  void _backToList() => setState(() => _preview = null);

  Future<void> _adjustStart(int index) async {
    final preview = _preview;
    if (preview == null) return;
    final slot = preview[index];
    final length = slot.endMinute - slot.startMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: slot.startMinute ~/ 60,
        minute: slot.startMinute % 60,
      ),
    );
    if (picked == null || !mounted) return;
    final newStart = picked.hour * 60 + picked.minute;
    setState(() {
      preview[index] = slot.copyWith(
        startMinute: newStart,
        endMinute: newStart + length,
      );
    });
  }

  Future<void> _createAll() async {
    final preview = _preview;
    if (preview == null || preview.isEmpty) return;
    final segments = [
      for (var i = 0; i < preview.length; i++)
        Segment(
          id: _uuid.v4(),
          name: preview[i].text,
          colorValue: kSegmentPalette[i % kSegmentPalette.length].toARGB32(),
          iconKey: 'event',
          startMinute: preview[i].startMinute,
          endMinute: preview[i].endMinute,
          order: 0,
        ),
    ];
    // Not awaited further than the controller's own call: upsertAll already
    // fire-and-forgets each write (offline-safe) and only awaits the single
    // reschedule at the end -- see SegmentsController.upsertAll.
    await ref.read(segmentsControllerProvider).upsertAll(segments);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('떠오르는 일들 적어보기')),
      body: _preview == null
          ? _buildListPhase(context)
          : _buildPreviewPhase(context),
    );
  }

  Widget _buildListPhase(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '머릿속에 떠오르는 일들을 하나씩 적어보세요.\n나중에 한꺼번에 시각을 배치해드려요.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: '예: 병원 예약 전화하기',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addItem(),
                ),
              ),
              if (_speechAvailable) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _toggleListening,
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  tooltip: _listening ? '녹음 중지' : '음성으로 입력',
                ),
              ],
              const SizedBox(width: 8),
              FilledButton(onPressed: _addItem, child: const Text('추가')),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(
                      '아직 추가한 항목이 없어요',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      title: Text(_items[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '삭제',
                        onPressed: () => _removeItem(index),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _items.isEmpty ? null : _suggestTimes,
            icon: const Icon(Icons.schedule),
            label: const Text('시각 자동 배치'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPhase(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('시각을 확인하고, 필요하면 눌러서 바꿔보세요.', style: theme.textTheme.bodyMedium),
          if (_notFittingCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '오늘 안에 자리가 없어서 $_notFittingCount개는 빠졌어요. 나머지는 구간 추가로 직접 넣어주세요.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: preview.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final slot = preview[index];
                return ListTile(
                  title: Text(slot.text),
                  subtitle: Text(
                    '${TimeGeometry.formatMinute(slot.startMinute)} – '
                    '${TimeGeometry.formatMinute(slot.endMinute)}',
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _adjustStart(index),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _backToList,
                  child: const Text('목록으로'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: preview.isEmpty ? null : _createAll,
                  child: const Text('추가하기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
