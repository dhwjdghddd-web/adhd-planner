import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen_mode.dart';
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
    builder: (_) => const _KeyboardAvoiding(child: QuickAddSheet()),
  ).whenComplete(() => quickAddSheetOpen.value = false);
}

/// Opens the same sheet pre-filled with an existing memo's text to edit it
/// (saving updates that memo instead of creating a new one).
Future<void> showEditMemoSheet(BuildContext context, Memo memo) {
  quickAddSheetOpen.value = true;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _KeyboardAvoiding(child: QuickAddSheet(existing: memo)),
  ).whenComplete(() => quickAddSheetOpen.value = false);
}

/// Lifts the sheet above the on-screen keyboard *and* keeps it scrollable in
/// whatever height is left.
///
/// The lift alone (a bottom [Padding] of `viewInsets.bottom`) is what every
/// keyboard-aware bottom sheet does, but on a foldable cover screen -- ~399dp
/// tall in total -- the keyboard eats over half the display, leaving the sheet
/// far less room than its content needs. The [Column] inside then blew past its
/// constraints and painted the yellow/black overflow stripes over the memo
/// field. Scrolling the leftover space (rather than overflowing it) is what
/// makes the sheet usable there; [QuickAddSheet] additionally shrinks its own
/// controls on a compact screen so it usually fits without any scrolling.
class _KeyboardAvoiding extends StatelessWidget {
  const _KeyboardAvoiding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // The sheet's own max height already accounts for the space above it;
      // this just makes the content yield instead of overflowing when the
      // keyboard has taken most of it.
      child: SingleChildScrollView(child: child),
    );
  }
}

/// Bottom sheet for capturing a stray thought in one tap: a text field plus
/// a large mic button for voice input. Saving closes the sheet immediately
/// to keep friction to a minimum. When [existing] is set, it edits that memo's
/// text instead of adding a new one.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.existing});

  final Memo? existing;

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
    if (widget.existing != null) {
      _controller.text = widget.existing!.text;
    }
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

  // Firestore's write Future only resolves once the backend acknowledges
  // it — while offline that never happens until connectivity returns, so
  // awaiting it here would leave the sheet stuck open with no feedback.
  // The local cache (and this sheet's job is done) is updated synchronously
  // regardless of network, so it's safe to close immediately and let the
  // write sync in the background.
  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final existing = widget.existing;
    if (existing != null) {
      unawaited(ref.read(memosControllerProvider).edit(existing, text));
    } else {
      unawaited(
        ref
            .read(memosControllerProvider)
            .add(text, source: _usedVoice ? MemoSource.voice : MemoSource.text),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    // On a cover screen the keyboard leaves only ~150dp for this sheet, so the
    // full-size layout (a 64px mic FAB, a 4-line field) can't fit no matter how
    // it's laid out. Trimming it here is what keeps the memo field visible
    // while typing; _KeyboardAvoiding's scroll is the backstop for the rest.
    final compact = isCompactLayout(context);
    final micSize = compact ? 44.0 : 64.0;
    final gap = compact ? 8.0 : 12.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 16, compact ? 12 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing != null ? '메모 수정' : '빠른 메모',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: gap),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: compact ? 2 : 4,
            decoration: const InputDecoration(
              hintText: '무슨 생각이 떠올랐나요?',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: gap),
          Row(
            children: [
              if (_speechAvailable)
                SizedBox(
                  width: micSize,
                  height: micSize,
                  child: FloatingActionButton(
                    heroTag: 'quick-add-mic',
                    backgroundColor: _listening
                        ? Theme.of(context).colorScheme.error
                        : null,
                    tooltip: _listening ? '녹음 중지' : '음성으로 입력',
                    onPressed: _toggleListening,
                    child: Icon(_listening ? Icons.stop : Icons.mic),
                  ),
                ),
              SizedBox(width: gap),
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
