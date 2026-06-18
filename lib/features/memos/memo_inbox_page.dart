import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/memo.dart';
import '../../data/providers.dart';
import 'memos_controller.dart';

/// Memo inbox: unreviewed thoughts by default (with a toggle to also show
/// ones already reviewed), a search box, and swipe-to-delete. Memos are
/// captured elsewhere via the global quick-add sheet — this page is purely
/// for triage.
class MemoInboxPage extends ConsumerStatefulWidget {
  const MemoInboxPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    final memosAsync = ref.watch(memosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('메모')),
      body: Column(
        children: [
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
        ],
      ),
    );
  }
}

class _MemoList extends ConsumerWidget {
  const _MemoList({required this.memos, required this.query, required this.showReviewed});

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
      // Leaves room for the global quick-add FAB pinned at the bottom-left
      // (see app.dart) so the last tile in a long list never sits under it.
      padding: const EdgeInsets.only(bottom: 88),
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
          child: CheckboxListTile(
            value: memo.reviewed,
            onChanged: (value) =>
                ref.read(memosControllerProvider).setReviewed(memo, value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              memo.text,
              style: memo.reviewed
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Row(
              children: [
                Icon(memo.source == MemoSource.voice ? Icons.mic : Icons.edit, size: 14),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
