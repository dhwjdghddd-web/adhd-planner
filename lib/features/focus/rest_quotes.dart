import 'dart:math';

import '../../data/today.dart';

/// Warm, single-line lines for the rest / waiting screens: gentle second-person
/// reassurances mixed with short sayings about rest, leisure, and slowing down.
///
/// Kept short, single-line, and free of author attributions on purpose — this
/// is where the load gets put *down*, so a long ponderous quote ("— 니체" and
/// friends) would add weight rather than lift it. Even the aphorisms are phrased
/// as a light nudge, not a lecture.
const List<String> restQuotes = [
  // Warm second-person reassurances.
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
  '애쓰지 않아도 되는 시간이에요',
  '잠시 눈을 감아도 좋아요',
  '오늘의 당신에게 고마워요',
  '쉬어도 당신의 가치는 그대로예요',
  '지친 건 게으른 게 아니에요',
  '잘 쉬고 있다면 잘하고 있는 거예요',
  // Short sayings about rest, leisure, and slowing down.
  '서두르지 않아도 도착해요',
  '쉼표가 있어야 문장이 읽혀요',
  '느린 걸음도 앞으로 가는 거예요',
  '비운 만큼 다시 채워져요',
  '멈춤은 게으름이 아니라 준비예요',
  '잘 쉰 하루가 내일을 만들어요',
  '휴식은 멈추는 게 아니라 돌보는 거예요',
  '가끔은 아무 데도 안 가는 게 가장 좋은 여행이에요',
  '늘 당겨둔 활은 부러져요',
  '쉼이 있어야 멜로디가 음악이 돼요',
  '여백이 있어야 그림이 숨을 쉬어요',
  '느림은 멈춤이 아니라 음미예요',
  '충분히 쉰 마음이 더 멀리 가요',
  '게으른 오후 하나쯤은 누려도 돼요',
  '바쁨이 곧 중요함은 아니에요',
  '쉬는 법을 아는 것도 능력이에요',
  '땅도 쉬어야 이듬해 곡식을 줘요',
  '잠깐의 딴짓이 마음을 살려요',
  '아무것도 안 한 시간은 낭비가 아니에요',
  '천천히 마시는 차가 더 향기로워요',
  '오늘 못한 일은 내일의 몫으로 남겨둬요',
  '쉬어가는 길에도 풍경은 있어요',
  '숨을 고르는 동안에도 당신은 자라고 있어요',
];

final _random = Random();

/// A rest message chosen at random — for screens that should feel fresh *each
/// time they're entered* (the routine-less Focus rest screen). Call it once when
/// the screen appears and hold the result, so it doesn't reshuffle on every
/// rebuild while you're looking at it.
String restQuoteRandom() => restQuotes[_random.nextInt(restQuotes.length)];

/// Today's single rest message, fixed for the whole day so it doesn't flicker
/// on every rebuild. Seeded by the local day key, so it stays put within a day
/// but rotates to a different one tomorrow. Used where a once-per-day feel fits
/// (e.g. the completion celebration).
String restQuoteForToday([DateTime? now]) {
  final key = dayKeyFor(now);
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return restQuotes[hash % restQuotes.length];
}
