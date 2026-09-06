import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/achieved_day.dart';
import 'models/alarm_skip.dart';
import 'models/app_settings.dart';
import 'models/checkin.dart';
import 'models/completion.dart';
import 'models/memo.dart';
import 'models/micro_step_move.dart';
import 'models/micro_step_progress.dart';
import 'models/mit.dart';
import 'models/rest_day.dart';
import 'models/segment.dart';
import 'repositories/firestore/firestore_planner_repository.dart';
import 'repositories/planner_repository.dart';

/// 앱 전역 SharedPreferences 인스턴스 Provider.
/// main()에서 SharedPreferences.getInstance()를 로드해 overrideWithValue로 주입합니다.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// Firebase 인증 사용자 스트림. userChanges()는 로그인/로그아웃뿐 아니라
/// **연결(link)** 으로 providerData가 바뀔 때도 emit하므로, 익명→구글 연결을
/// UI가 즉시 반영할 수 있다(연결은 uid를 바꾸지 않아 authStateChanges로는
/// 안 잡힌다).
final firebaseUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.userChanges(),
);

/// main() 시작 시 FirebaseAuth에서 확정한 초기 uid.
final initialUidProvider = Provider<String?>((ref) => null);

/// 현재 활성 계정의 uid. select로 uid만 골라, 토큰 갱신 같은 잡음에는
/// 리빌드되지 않고 **uid가 실제로 바뀔 때만**(로그인/로그아웃/계정전환)
/// 아래 repository가 새로 만들어지게 한다.
final currentUidProvider = Provider<String?>((ref) {
  final streamUid =
      ref.watch(firebaseUserProvider.select((s) => s.valueOrNull?.uid));
  final initialUid = ref.watch(initialUidProvider);
  final fallbackUid = FirebaseAuth.instance.currentUser?.uid;
  return streamUid ?? initialUid ?? fallbackUid;
});

/// 활성 계정 uid 아래의 Firestore 저장소.
final plannerRepositoryProvider = Provider<PlannerRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return FirestorePlannerRepository(uid);
});

/// uid가 null인 순간(signOut ↔ signInAnonymously 사이)에는 empty 스트림 대신
/// 빈 리스트 스트림을 반환하여, StreamProvider가 영구 로딩에 갇히지 않도록 안전 보호합니다.
Stream<List<T>> _guardedStream<T>(
  PlannerRepository? repo,
  Stream<List<T>> Function(PlannerRepository) watch,
) {
  if (repo == null) return Stream.value(const []);
  return watch(repo);
}

final segmentsProvider = StreamProvider<List<Segment>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchSegments(),
  ),
);

final memosProvider = StreamProvider<List<Memo>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchMemos(),
  ),
);

final completionsProvider = StreamProvider<List<Completion>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchCompletions(),
  ),
);

final microStepProgressProvider = StreamProvider<List<MicroStepProgress>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchMicroStepProgress(),
  ),
);

final achievedDaysProvider = StreamProvider<List<AchievedDay>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchAchievedDays(),
  ),
);

final alarmSkipsProvider = StreamProvider<List<AlarmSkip>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchAlarmSkips(),
  ),
);

final mitsProvider = StreamProvider<List<Mit>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchMits(),
  ),
);

final checkinsProvider = StreamProvider<List<Checkin>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchCheckins(),
  ),
);

final microStepMovesProvider = StreamProvider<List<MicroStepMove>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchMicroStepMoves(),
  ),
);

final restDaysProvider = StreamProvider<List<RestDay>>(
  (ref) => _guardedStream(
    ref.watch(plannerRepositoryProvider),
    (r) => r.watchRestDays(),
  ),
);

/// Settings는 null uid 구간에 기본값을 유지한다(앱이 깜빡이지 않게).
final settingsProvider = StreamProvider<AppSettings>((ref) {
  final repo = ref.watch(plannerRepositoryProvider);
  if (repo == null) return Stream.value(const AppSettings.defaults());
  return repo.watchSettings();
});

/// [plannerRepositoryProvider]를 null 허용으로 바꾼 뒤, 기존에
/// `Provider<PlannerRepository>` 타입으로 해당 provider를 직접 read/watch하던
/// 곳(예: app.dart의 _AccountAlarmSync)을 위한 편의 확장.
/// null이면 Firestore에 접근하지 않고 skip한다.
extension PlannerRepoX on PlannerRepository? {
  /// null이면 Future.value(null)을 반환하는 guard 헬퍼.
  Future<T?> guardedFirst<T>(
    Stream<T> Function(PlannerRepository) watch,
  ) async {
    final repo = this;
    if (repo == null) return null;
    return watch(repo).first;
  }
}
