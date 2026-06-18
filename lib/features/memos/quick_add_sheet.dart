import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/memo.dart';
import '../../services/speech_service.dart';
import 'memos_controller.dart';

/// Whether the quick-add sheet is currently open. The persistent global FAB
/// (see quick_add_button.dart) watches this to hide itself rather than
/// floating on top of the sheet it just opened.
final ValueNotifier<bool> quickAddSheetOpen = ValueNotifier<bool>(false);

/// Opens the quick-add bottom sheet from anywhere in the app. Resizes with
/// the keyboard so the text field and mic button stay visible while typing.
Future<void> showQuickAddSheet(BuildContext context) {
  quickAddSheetOpen.value = true;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: const QuickAddSheet(),
    ),
  ).whenComplete(() => quickAddSheetOpen.value = false);
}

/// Bottom sheet for capturing a stray thought in one tap: a text field plus
/// a large mic button for voice input. Saving closes the sheet immediately
/// to keep friction to a minimum.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _controller = TextEditingController();
  final _speech = SpeechService();
  bool _speechAvailable = false;
  bool _listening = false;
  bool _usedVoice = false;

  @override
  void initState() {
    super.initState();
    _speech.init().then((available) {
      if (mounted) setState(() => _speechAvailable = available);
    });
  }

  @override
  void dispose() {
    _speech.dispose();
    _controller.dispose();
    super.dispose();
  }

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
        _usedVoice = true;
        if (isFinal) _listening = false;
      });
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await ref.read(memosControllerProvider).add(
          text,
          source: _usedVoice ? MemoSource.voice : MemoSource.text,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('빠른 메모', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '무슨 생각이 떠올랐나요?',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_speechAvailable)
                SizedBox(
                  width: 64,
                  height: 64,
                  child: FloatingActionButton(
                    heroTag: 'quick-add-mic',
                    backgroundColor:
                        _listening ? Theme.of(context).colorScheme.error : null,
                    tooltip: _listening ? '녹음 중지' : '음성으로 입력',
                    onPressed: _toggleListening,
                    child: Icon(_listening ? Icons.stop : Icons.mic),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  child: const Text('저장'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
