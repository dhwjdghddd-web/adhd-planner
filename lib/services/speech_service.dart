import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around `speech_to_text` for the memo quick-add sheet's mic
/// button. The plugin's own [SpeechToText.initialize] requests the
/// microphone permission natively — no separate permission_handler step
/// needed. [init] never throws: any failure (denied permission, no speech
/// recognizer on the device, missing plugin in a test environment) just
/// resolves to false so callers can fall back to text-only input.
class SpeechService {
  final SpeechToText _speech = SpeechToText();

  /// [onDone] fires whenever the recognizer stops listening for ANY reason --
  /// the user stopping it, the final result, OR the plugin auto-cancelling
  /// after a silence timeout (saying nothing). Without it the mic button's
  /// "listening" state would stay stuck on after a no-speech timeout, since
  /// `onResult` is never called with a final result in that case.
  Future<bool> init({void Function()? onDone}) async {
    try {
      return await _speech.initialize(
        onStatus: (status) {
          if (status == SpeechToText.notListeningStatus ||
              status == SpeechToText.doneStatus) {
            onDone?.call();
          }
        },
        onError: (_) => onDone?.call(),
      );
    } catch (_) {
      return false;
    }
  }

  bool get isListening => _speech.isListening;

  /// Starts a listen session, invoking [onResult] with the current best
  /// transcription each time it updates and whether it's the final result.
  Future<void> startListening(
    void Function(String text, bool isFinal) onResult,
  ) {
    return _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  Future<void> stopListening() => _speech.stop();

  void dispose() => _speech.cancel();
}
