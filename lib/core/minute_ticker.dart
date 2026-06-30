import 'dart:async';

/// Fires [onMinute] once shortly after each wall-clock minute boundary, instead
/// of waking every second to ask "did the minute change yet?".
///
/// The screens that show "current minute" state (the dial's now-marker, Focus's
/// remaining-time, the foreground alarm watcher) only ever act on a minute
/// *change*, so polling at 1Hz meant ~59 of every 60 wake-ups did nothing. This
/// re-arms a single one-shot timer to the next boundary after each fire, so it
/// wakes ~once a minute. (A small buffer past the boundary avoids waking back
/// inside the same minute if the timer fires a hair early.)
///
/// Call [start] from initState and [cancel] from dispose.
class MinuteTicker {
  MinuteTicker(this.onMinute);

  final void Function() onMinute;
  Timer? _timer;

  void start() => _scheduleNext();

  void _scheduleNext() {
    final now = DateTime.now();
    final msIntoMinute = now.second * 1000 + now.millisecond;
    final msToNext = 60000 - msIntoMinute + 50;
    _timer = Timer(Duration(milliseconds: msToNext), () {
      onMinute();
      _scheduleNext();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
