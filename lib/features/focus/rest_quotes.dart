import '../../data/today.dart';

/// Short, warm second-person reassurances for the rest / waiting screens, with
/// a few light "take it easy" sayings mixed in.
///
/// Deliberately kept short, single-line, and free of author attributions: this
/// screen is where an ADHD user puts the load *down*, so a long aphorism — or
/// anything that reads as a lecture ("— 니체" and friends) — would add cognitive
/// weight rather than lift it. The point is a gentle "you're okay", not a quote
/// of the day to ponder.
const List<String> restQuotes = [
  // Warm second-person reassurances (the majority).
  '잠깐 멈춰도 괜찮아요',
  '지금은 아무것도 안 해도 돼요',
  '여기까지 온 것만으로 충분해요',
  '숨 한 번 고르고 가요',
  '쉬는 것도 오늘의 일이에요',
  '천천히 가도 괜찮아요',
  '지금은 그냥 쉬어요',
  '잘하고 있어요, 정말로',
  '몸과 마음을 잠시 내려놓아요',
  '아무 생각 안 해도 되는 시간이에요',
  '조금 느려도 괜찮아요',
  '지금 이 순간은 당신 거예요',
  // Light "take it easy" sayings (a few, mixed in).
  '서두르지 않아도 도착해요',
  '쉼표가 있어야 문장이 읽혀요',
  '느린 걸음도 앞으로 가는 거예요',
  '비운 만큼 다시 채워져요',
];

/// Today's single rest message, fixed for the whole day so it doesn't flicker
/// on every rebuild. Seeded by the local day key, so it stays put within a day
/// but rotates to a different one tomorrow.
String restQuoteForToday([DateTime? now]) {
  final key = dayKeyFor(now);
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return restQuotes[hash % restQuotes.length];
}
