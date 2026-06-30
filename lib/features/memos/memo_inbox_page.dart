import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen_mode.dart';
import '../../data/models/memo.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import 'memo_resurfacing.dart';
import 'memos_controller.dart';
import 'promote_memo_sheet.dart';
import 'quick_add_button.dart';
import 'quick_add_sheet.dart';

/// Memo inbox: unreviewed thoughts by default (with a toggle to also show
/// ones already reviewed), a search box, and swipe-to-delete. Memos are
/// captured elsewhere via the global quick-add sheet — this page is purely
/// for triage. Long-pressing a row offers to promote it into a block/checklist
/// item (see [showPromoteMemoSheet]) instead of just ticking it off.
class MemoInboxPage extends ConsumerStatefulWidget {
  const MemoInboxPage({super.key, @visibleForTesting this.debugNow});

  /// Test-only override for "now", used when deciding which memo (if any)
  /// is old enough to resurface -- without this, a test run near a day
  /// boundary could pick a different memo than the one it expects.
  final DateTime? debugNow;

  @override
  ConsumerState<MemoInboxPage> createState() => _MemoInboxPageState();
}

class _MemoInboxPageState extends ConsumerState<MemoInboxPage> {
  final _searchController = TextEditingController();
  bool _showReviewed = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime get _now => widget.debugNow ?? DateTime.now();

  Future<void> _dismissNudge() async {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    await ref
        .read(plannerRepositoryProvider)
        ?.saveSettings(settings.copyWith(lastMemoNudgeDate: dayKeyFor(_now)));
  }

  Future<void> _handleNudge(Memo memo) async {
    await _dismissNudge();
    if (mounted) await showPromoteMemoSheet(context, memo);
  }

  @override
  Widget build(BuildContext context) {
    final memosAsync = ref.watch(memosProvider);
    final settings = ref.watch(settingsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('메모')),
      body: Column(
        children: [
          memosAsync.maybeWhen(
            data: (memos) {
              if (settings == null ||
                  settings.lastMemoNudgeDate == dayKeyFor(_now)) {
                return const SizedBox.shrink();
              }
              final nudge = oldestNudgeworthyMemo(memos, _now);
              if (nudge == null) return const SizedBox.shrink();
              return _MemoNudgeCard(
                memo: nudge,
                onHandle: () => _handleNudge(nudge),
                onDismiss: _dismissNudge,
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '메모 검색',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SwitchListTile(
            title: const Text('확인한 메모도 보기'),
            value: _showReviewed,
            onChanged: (value) => setState(() => _showReviewed = value),
          ),
          Expanded(
            // Shrinks the visible list area itself (rather than padding
            // inside it, which only shows up once scrolled all the way
            // down) so content never reaches the global bottom-left
            // quick-add FAB even before scrolling.
            child: Padding(
              padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
              child: memosAsync.when(
                data: (memos) => _MemoList(
                  memos: memos,
                  query: _searchController.text.trim(),
                  showReviewed: _showReviewed,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('오류: $e')),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isCompactLayout(context)
          ? compactCornerFabs()
          : const MultiFabRow(left: GlobalQuickAddButton()),
      floatingActionButtonLocation: screenFabLocation(context),
    );
  }
}

class _MemoList extends ConsumerWidget {
  const _MemoList({
    required this.memos,
    required this.query,
    required this.showReviewed,
  });

  final List<Memo> memos;
  final String query;
  final bool showReviewed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var filtered = memos.where((m) => showReviewed || !m.reviewed);
    if (query.isNotEmpty) {
      filtered = filtered.where((m) => m.text.contains(query));
    }
    // Unreviewed memos first (newest first within that group), reviewed
    // ones pushed below them -- struck through in the tile itself below --
    // also newest-first within their own group.
    final sorted = filtered.toList()
      ..sort((a, b) {
        if (a.reviewed != b.reviewed) return a.reviewed ? 1 : -1;
        return b.createdAtIso.compareTo(a.createdAtIso);
      });

    if (sorted.isEmpty) {
      return Center(
        child: Text(
          showReviewed ? '메모가 없어요' : '확인하지 않은 메모가 없어요',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final memo = sorted[index];
        return Dismissible(
          key: ValueKey(memo.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(context, memo),
          onDismissed: (_) => ref.read(memosControllerProvider).delete(memo.id),
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete_outline),
          ),
          // Tapping the row body edits the memo; the leading checkbox (a
          // separate tap target) toggles reviewed, so the two don't collide.
          // Long-pressing offers to promote it into a block/checklist item
          // instead -- a third action, but on a gesture none of the other two
          // use, so it doesn't compete with them.
          child: ListTile(
            onTap: () => showEditMemoSheet(context, memo),
            onLongPress: () => showPromoteMemoSheet(context, memo),
            leading: Checkbox(
              value: memo.reviewed,
              onChanged: (value) => ref
                  .read(memosControllerProvider)
                  .setReviewed(memo, value ?? false),
            ),
            title: Text(
              memo.text,
              style: memo.reviewed
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Row(
              children: [
                Icon(
                  memo.source == MemoSource.voice ? Icons.mic : Icons.edit,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(_formatTime(memo.createdAt)),
                if (memo.category != null) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(memo.category!),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<bool> _confirmDelete(BuildContext context, Memo memo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('메모 삭제'),
        content: const Text('이 메모를 삭제할까요?'),
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
}

/// "이 메모, 아직이에요" -- nudges about the single oldest memo that's been
/// sitting unreviewed for a while (see [oldestNudgeworthyMemo]), so a stray
/// thought that's gone quiet doesn't just rot at the bottom of the inbox.
/// Shown at most once a day (see [MemoInboxPage._dismissNudge]).
class _MemoNudgeCard extends StatelessWidget {
  const _MemoNudgeCard({
    required this.memo,
    required this.onHandle,
    required this.onDismiss,
  });

  final Memo memo;
  final VoidCallback onHandle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이 메모, 아직이에요',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              memo.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('나중에')),
                FilledButton(onPressed: onHandle, child: const Text('지금 처리')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
