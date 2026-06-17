# ADHD 원형 생활계획표 앱 — 실행 명령서 (Sonnet 에이전트용)

> 이 문서는 **순서대로** 실행한다. 각 STEP은 ① 목표 ② 실행(명령/파일) ③ 완료 검증(Acceptance)로 구성된다.
> **한 STEP을 완료·검증하기 전에는 다음 STEP으로 넘어가지 않는다.**
> 작업 디렉터리: `C:\claude\adhd_planner`

---

## 핵심 규칙 (반드시 지킬 것)

1. **Flutter 호출은 puro로 한다.** bash의 `flutter` 셔임은 깨져 있다. 모든 flutter/dart 명령은:
   - PowerShell: `& "$env:USERPROFILE\.puro\bin\puro.bat" flutter <args>`
   - 또는 세션 시작 시 PATH 추가: `$env:Path = "$env:USERPROFILE\.puro\bin;" + $env:Path` 후 `puro flutter <args>`
   - 설치 버전: **Flutter 3.44.1 / Dart 3.12.1** (검증됨). Dart SDK ≥ 3.12.
2. **빌드 대상은 Android 우선**(사용자 OS=Windows, iOS 빌드는 Mac 필요). 모든 실행 테스트는 Android 에뮬레이터/실기기.
3. **저장소 추상화 원칙**: 화면·컨트롤러는 `Repository` 인터페이스에만 의존한다. Firebase 구현은 후반에 끼운다.
   따라서 **앱은 처음부터 로컬(In-memory/Hive) 구현으로 즉시 실행 가능**해야 하고, Firebase는 STEP 9에서 교체한다.
   (이유: Firebase 연결은 `firebase login` + `flutterfire configure`라는 **대화형 인증**이 필요 → 에이전트 단독 불가.
   먼저 동작하는 앱을 만들고, 사용자 인증이 끝나면 구현체만 갈아끼운다.)
4. **각 STEP 종료 시** `puro flutter analyze` 가 **에러 0**이어야 한다(경고는 허용하되 줄여나간다).
5. 코드 스타일: `flutter_lints` 준수. 모든 public 클래스/위젯에 간단한 의도 주석. 색만으로 정보 전달 금지(아이콘+라벨 병행).
6. 작업 추적: TaskCreate로 STEP별 작업을 만들고, 시작 시 in_progress, 끝나면 completed로 갱신한다.

---

## 의존성 목록 (STEP 1에서 pubspec에 넣는다)

| 패키지 | 용도 |
|---|---|
| `flutter_riverpod` | 상태관리/DI |
| `hive`, `hive_flutter` | 로컬 영속 저장(초기 구현체) |
| `flutter_local_notifications` | 정시 알람·전환 예고 |
| `timezone` | 알람 정확한 타임존 스케줄링 |
| `permission_handler` | 알림/정확알람/마이크 권한 |
| `speech_to_text` | 음성 메모 |
| `confetti` | 보상 효과 |
| `uuid` | 엔티티 id 생성 |
| `intl` | 시간 포맷 |
| (후반) `firebase_core`, `cloud_firestore`, `firebase_auth` | 클라우드 동기화(STEP 9) |
| dev: `flutter_lints`, `hive_generator`, `build_runner` | 린트/코드젠 |

---

# STEP 0 — 환경 확인

**목표**: 툴체인이 동작함을 확인.

**실행**:
```powershell
$env:Path = "$env:USERPROFILE\.puro\bin;" + $env:Path
puro flutter --version
puro flutter doctor
```

**Acceptance**:
- `flutter --version` 이 3.44.x 출력.
- `flutter doctor` 에서 Android toolchain 항목이 ✓ (또는 라이선스만 미동의면 `puro flutter doctor --android-licenses` 로 동의).
- 에뮬레이터 목록 확인: `puro flutter emulators` — 없으면 Android Studio에서 AVD 1개 생성 안내를 사용자에게 남긴다.

---

# STEP 1 — 프로젝트 생성 & 골격

**목표**: 실행되는 빈 Flutter 앱 + 의존성 + 폴더 구조.

**실행**:
```powershell
# adhd_planner 안에 .idea만 있으므로, 임시 폴더에 생성 후 내용 이동하거나 현재 폴더에 생성
puro flutter create --org com.adhdplanner --project-name adhd_planner --platforms=android,ios .
```
- 생성 후 `pubspec.yaml`의 `dependencies`/`dev_dependencies`에 위 의존성 추가(후반 firebase 3종은 주석으로 남겨둠).
- `puro flutter pub get` 실행.

**폴더 구조 생성** (`lib/` 하위):
```
lib/
  main.dart
  app.dart                     # MaterialApp, 테마, 라우팅
  core/
    theme.dart                 # 라이트/다크 테마, 색 팔레트, 글자크기 스케일
    time_geometry.dart         # 분↔각도 변환 유틸 (STEP 2)
    constants.dart
  data/
    models/                    # segment.dart, routine.dart, memo.dart, completion.dart, app_settings.dart
    repositories/
      planner_repository.dart  # 추상 인터페이스
      local/                   # Hive 구현 (초기)
      firestore/               # Firestore 구현 (STEP 9)
    providers.dart             # Riverpod provider 정의 (repository 주입 지점)
  services/
    notification_service.dart
    speech_service.dart
  features/
    planner/   segments/   routines/   focus/   memos/   rewards/   settings/
```

**Android 매니페스트 권한** (`android/app/src/main/AndroidManifest.xml` `<manifest>` 안):
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```
- `flutter_local_notifications` 가이드대로 `<application>` 안에 알림 리시버/부팅 리시버 등록, `minSdkVersion`을 21 이상(권장 23)으로, `compileSdk`/`targetSdk`는 최신(34+)으로 맞춘다.
- `android/app/build.gradle`에서 `coreLibraryDesugaringEnabled true` + `desugar_jdk_libs` 의존성 추가(flutter_local_notifications 요구).

**`main.dart`**: Hive 초기화 → `runApp(ProviderScope(child: App()))`.

**Acceptance**:
- `puro flutter run` 으로 에뮬레이터에 빈 앱(임시 홈)이 뜬다.
- `puro flutter analyze` 에러 0.

---

# STEP 2 — 코어: 시간↔각도 유틸 + 테마

**목표**: 원형 UI·알람·포커스가 공유할 **단일 시간 기하 유틸**과 접근성 테마.

**`lib/core/time_geometry.dart`** (정확히 이 시그니처로 구현):
```dart
import 'dart:math' as math;

/// 하루를 분(0~1440)으로 다루고, 24h 원형 다이얼의 각도로 변환하는 단일 유틸.
/// 12시 방향(위)=0분(자정), 시계방향 진행.
class TimeGeometry {
  static const int minutesPerDay = 1440;

  /// 분(0~1440) → 라디안. 12시 방향 기준, 시계방향.
  /// canvas 각도계는 3시 방향=0, 반시계가 양(+) 이므로 -90°(=-pi/2) 보정.
  static double minuteToRadians(int minute) {
    final frac = (minute % minutesPerDay) / minutesPerDay;
    return frac * 2 * math.pi - math.pi / 2;
  }

  /// 분 → 도(degree, 0~360), 12시=0, 시계방향.
  static double minuteToDegrees(int minute) =>
      (minute % minutesPerDay) / minutesPerDay * 360.0;

  /// 원 위 한 점(중심 center, 반지름 r, 해당 분)의 좌표.
  static Offset pointOnCircle(Offset center, double r, int minute) {
    final a = minuteToRadians(minute);
    return Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
  }

  /// 탭한 좌표 → 가장 가까운 분(역변환). 구간/루틴을 원에서 드래그 편집할 때 사용.
  static int offsetToMinute(Offset center, Offset point) {
    final a = math.atan2(point.dy - center.dy, point.dx - center.dx) + math.pi / 2;
    final frac = (a / (2 * math.pi)) % 1.0;
    final f = frac < 0 ? frac + 1.0 : frac;
    return (f * minutesPerDay).round() % minutesPerDay;
  }

  /// "HH:mm" 포맷.
  static String formatMinute(int minute) {
    final h = (minute ~/ 60) % 24;
    final m = minute % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
```
> `Offset`는 `package:flutter/painting.dart` 또는 `dart:ui`에서 온다. import 추가.

**단위 테스트** `test/time_geometry_test.dart`:
- `minuteToDegrees(0)==0`, `minuteToDegrees(360)==90`(=6시간=90°), `minuteToDegrees(720)==180`.
- `offsetToMinute(pointOnCircle(c, r, m)) ≈ m` 왕복 일치(여러 m에 대해, ±1 허용).

**`lib/core/theme.dart`**:
- 라이트/다크 ColorScheme(고대비), 구간용 색 팔레트(색맹 안전 8색), 큰 탭 타깃(`MaterialTapTargetSize.padded`), `textScaler`를 설정값과 연동할 수 있는 구조.

**Acceptance**: `puro flutter test` 통과(time_geometry_test). `analyze` 에러 0.

---

# STEP 3 — 데이터 모델 + Repository 인터페이스 + 로컬 구현

**목표**: 도메인 모델과 저장소 추상화, 그리고 즉시 동작하는 Hive 로컬 구현.

**모델** (`lib/data/models/`), 각 모델은 `toMap`/`fromMap`(Firestore 대비)와 Hive 어댑터(또는 Hive는 Map 저장로 단순화) 포함:
- `Segment`: `id, name, colorValue(int), iconKey(String), startMinute, endMinute, order`.
  - 자정 넘김(예: 22:00~02:00) 허용: `endMinute < startMinute` 이면 다음날로 래핑. 길이 계산 헬퍼 `lengthMinutes` 제공.
- `Routine`: `id, segmentId, title, note, microSteps(List<String>), startMinute, durationMin, alarmEnabled(bool), leadWarningMin(int, 기본5), snoozeMin(int, 기본5), repeatDays(List<int> 1=월..7=일), notificationIds(List<int>)`.
- `Memo`: `id, text, source('text'|'voice'), createdAtIso(String), reviewed(bool), category(String?)`.
- `Completion`: `dateKey('yyyy-MM-dd'), routineId, completedAtIso`.
- `AppSettings`: `themeMode, fontScale(double), reduceMotion(bool), exactAlarmGranted(bool)`.

**Repository 인터페이스** `lib/data/repositories/planner_repository.dart`:
```dart
abstract class PlannerRepository {
  // Segments
  Stream<List<Segment>> watchSegments();
  Future<void> upsertSegment(Segment s);
  Future<void> deleteSegment(String id);
  // Routines
  Stream<List<Routine>> watchRoutines();
  Future<void> upsertRoutine(Routine r);
  Future<void> deleteRoutine(String id);
  // Memos
  Stream<List<Memo>> watchMemos();
  Future<void> addMemo(Memo m);
  Future<void> updateMemo(Memo m);
  Future<void> deleteMemo(String id);
  // Completions
  Stream<List<Completion>> watchCompletions();
  Future<void> setCompletion(Completion c);
  Future<void> removeCompletion(String dateKey, String routineId);
  // Settings
  Stream<AppSettings> watchSettings();
  Future<void> saveSettings(AppSettings s);
}
```

**로컬 구현** `lib/data/repositories/local/hive_planner_repository.dart`:
- Hive 박스 5개(segments, routines, memos, completions, settings). 변경 시 `ValueListenable`/스트림으로 emit.
- `watch*`는 박스의 변경을 Stream으로 노출(`box.watch()` → 전체 리스트 재방출).

**Provider** `lib/data/providers.dart`:
```dart
final plannerRepositoryProvider = Provider<PlannerRepository>((ref) {
  return HivePlannerRepository(); // STEP 9에서 Firestore 구현으로 교체
});
final segmentsProvider = StreamProvider<List<Segment>>(
  (ref) => ref.watch(plannerRepositoryProvider).watchSegments());
// routines, memos, completions, settings 동일 패턴
```

**Acceptance**:
- Hive 박스 초기화 후 `upsertSegment` → `watchSegments`가 변경을 방출함을 위젯/단위 테스트로 확인.
- 앱 재시작 후 데이터 유지(영속성) 확인.
- `analyze` 에러 0.

---

# STEP 4 — 구간(Segments) 편집 화면

**목표**: 하루를 사용자 방식으로 분할(오전/오후/퇴근 후…).

**화면** `features/segments/segment_editor_page.dart`:
- 구간 리스트(이름·색·아이콘·시간범위 표시), 추가/수정/삭제.
- 추가/수정 폼: 이름, 색 선택(팔레트), 아이콘 선택, 시작/끝 시각(`showTimePicker` → 분으로 변환).
- 검증: 길이>0, 겹침은 **허용하되 경고 표시**(원형에서 겹치면 안쪽 링으로 표시). 자정 넘김 허용.
- 접근성: 각 항목 `Semantics(label: '오전 구간, 06시부터 12시, 파랑')`.

**컨트롤러**: Riverpod Notifier가 `upsertSegment`/`deleteSegment` 호출, order 관리(드래그 정렬 `ReorderableListView`).

**Acceptance**: 구간 3개(예: 오전 6–12, 오후 12–18, 퇴근후 18–24) 생성 → 재시작 후 유지.

---

# STEP 5 — 홈: 원형 계획표 (CustomPainter)

**목표**: 24h 원형 다이얼에 구간 호·루틴 마커·현재시각 바늘 렌더.

**화면** `features/planner/planner_page.dart` + `features/planner/dial_painter.dart`.

**`DialPainter extends CustomPainter`** 요구사항:
- 바깥 원(시계 테), 24개(또는 4·6시간) 눈금 + 주요 시각 라벨(0/6/12/18시).
- 각 `Segment`를 `startMinute~endMinute` 호(arc)로 색칠. `TimeGeometry.minuteToRadians` 사용.
  - Canvas `drawArc(rect, startAngle, sweepAngle, ...)`: startAngle=`minuteToRadians(startMinute)`,
    sweep=`(lengthMinutes/1440)*2π`. 자정 넘김도 length로 자연 처리.
- 각 `Routine`을 해당 시작분 위치에 점/아이콘 마커로 표시(구간 색 기반).
- **현재시각 바늘**: 지금 분 → `pointOnCircle`로 중심→테두리 선(빨강), 1분마다 갱신
  (`Timer.periodic` 또는 `Ticker`로 setState/provider invalidate).
- 중앙: "다음 할 일 + 남은 시간" 요약 + '지금' 버튼(→ STEP 7 포커스).
- **탭 처리**: `GestureDetector`로 원 위 탭 → `offsetToMinute`로 분 추정 → 가장 가까운 구간/루틴 선택 → 편집 이동.

**성능**: `shouldRepaint`는 입력(segments/routines/현재분) 변경 시에만 true.

**Acceptance**:
- 구간 색 호가 정확한 위치/길이로 그려짐(예: 오전 6–12시는 우상단 1사분면 영역).
- 빨간 바늘이 현재 시각을 가리키고 1분마다 이동.
- `analyze` 에러 0, 60fps 근처(디버그라도 끊김 없음).

---

# STEP 6 — 루틴(Routines) 편집

**목표**: 구간 안에 루틴 배치 + 알람/전환예고/마이크로스텝/반복요일 설정.

**화면** `features/routines/routine_editor_page.dart`:
- 입력: 제목, 메모, 소속 구간(드롭다운), 시작 시각, 길이(분), 알람 on/off,
  전환 예고 분(기본 5), 스누즈 분(기본 5), 반복 요일(월~일 토글), 마이크로스텝(추가/삭제 리스트).
- 저장 시 `upsertRoutine` → **알람 재예약 트리거**(STEP 8의 `NotificationService.reschedule`).
- 접근성: 큰 버튼, 한 화면 한 주요 동작 흐름.

**Acceptance**: 루틴 생성/수정/삭제가 홈 원형 마커에 즉시 반영. 재시작 후 유지.

---

# STEP 7 — '지금' 집중 화면 (Focus)

**목표**: 인지 부하 최소화 — 현재 할 일 **하나만** 크게 + 카운트다운 링.

**화면** `features/focus/focus_page.dart`:
- 현재 분에 해당하는 루틴 1개 선택(시작분≤now<시작분+length, 오늘 반복요일 매칭).
  없으면 "다음 루틴까지 N분" 표시.
- 큰 제목 + 마이크로스텝 체크리스트 + **남은 시간 원형 카운트다운**(CustomPainter 또는 `CircularProgressIndicator` 커스텀).
- 버튼 3개(큰 사이즈): **완료**(→ Completion 기록 + 보상 STEP 10), **스누즈**(알람 미루기), **다음 할 일**.
- 산만 방지: 풀스크린, 최소 색·요소, 모션감소 설정 존중.

**Acceptance**: 현재 시각에 걸린 루틴이 자동 표시되고 카운트다운이 줄어든다. 완료 누르면 기록됨.

---

# STEP 8 — 알림: 정시 알람 + 전환 예고 + 스누즈

**목표**: 앱이 꺼져 있어도 정시 발화하는 로컬 알림.

**`lib/services/notification_service.dart`** 핵심 요구:
- `init()`: `flutter_local_notifications` 초기화 + `timezone` 초기화(`tz.initializeTimeZones()`, 로컬 타임존 set).
- 권한: Android 13+ `POST_NOTIFICATIONS`, 정확알람 `SCHEDULE_EXACT_ALARM`(`permission_handler` 또는 플러그인 API). 거부 시 설정 화면 유도 폴백.
- `Future<void> rescheduleAll(List<Routine> routines)`:
  1) 기존 예약 전체 취소(`cancelAll` 또는 routine별 notificationIds 취소).
  2) 각 알람 켜진 루틴에 대해 **반복요일마다**:
     - **본 알람**: 시작분에 `zonedSchedule`(채널 'routine', 액션: 스누즈/완료).
     - **전환 예고**: 시작분 − leadWarningMin 에 `zonedSchedule`(채널 'transition', "곧 전환: <제목>").
     - 정확 발화: `androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle`.
     - `matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime` 로 주간 반복.
  3) 부여한 notification id들을 routine에 저장(취소 추적).
- 알림 id 규칙: `routineHash*100 + slot`(본알람/예고/요일 구분)로 충돌 방지·역추적 가능.
- 스누즈 액션 핸들러: 탭 시 `snoozeMin` 후 1회성 재알림.
- **재예약 트리거**: 루틴 변경/삭제, 앱 시작, 부팅 후(`RECEIVE_BOOT_COMPLETED`) 시 `rescheduleAll` 호출.

**Acceptance** (반드시 실기기/에뮬레이터 수동 검증):
- 루틴을 **현재시각 +2분**, 전환예고 1분으로 설정 → 앱을 백그라운드로 → 1분 뒤 "곧 전환" 예고, 2분 뒤 본 알람 발화.
- 알림의 스누즈 누르면 N분 뒤 재알림.
- 기기 재부팅 후에도 예약 유지(부팅 리시버).

---

# STEP 9 — Firebase 교체 (클라우드 동기화)  ⚠️ 사용자 대화형 인증 필요

**목표**: 로컬 구현체를 Firestore 구현체로 교체(앱 로직 무변경).

**사전(사용자가 직접 수행해야 함 — 에이전트는 명령만 안내)**:
```powershell
# Firebase CLI 설치(없으면): npm i -g firebase-tools
firebase login                 # ← 브라우저 대화형 로그인 (사용자 수행)
dart pub global activate flutterfire_cli
flutterfire configure          # ← Firebase 프로젝트 선택/생성 (사용자 수행)
```
> 에이전트는 위 3개가 끝나 `lib/firebase_options.dart` 가 생성된 뒤에 이어서 진행한다.
> 만약 아직 안 됐으면 STEP 9는 **보류**하고 STEP 10~11을 먼저 끝낸 뒤 사용자에게 인증을 요청한다.

**에이전트 작업**:
- pubspec의 firebase 3종 주석 해제 → `pub get`.
- `main.dart`에 `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` + 익명 로그인:
  `FirebaseAuth.instance.signInAnonymously()`.
- Firestore 오프라인 영속성 활성화(모바일 기본 on; `Settings(persistenceEnabled: true)` 확인).
- `lib/data/repositories/firestore/firestore_planner_repository.dart` 구현: 인터페이스 동일, 경로
  `users/{uid}/segments|routines|memos|completions`, settings는 단일 문서.
  `watch*`는 `snapshots()` 스트림 매핑.
- `providers.dart`의 `plannerRepositoryProvider`를 Firestore 구현으로 교체(또는 설정 플래그로 선택).
- **마이그레이션**: 기존 Hive 데이터 → Firestore 1회 업로드 유틸(선택).
- **보안 규칙**(`firestore.rules`): `match /users/{uid}/{document=**} { allow read, write: if request.auth.uid == uid; }` → `firebase deploy --only firestore:rules`(사용자 수행).

**Acceptance**:
- 비행기 모드에서 메모/루틴 추가 → 네트워크 복구 시 Firestore 콘솔에 반영.
- 앱 재설치 후(같은 익명 계정 한정 주의) 또는 로그인 계정으로 데이터 복원.

---

# STEP 10 — 보상/스트릭 (비처벌)

**목표**: 도파민 보상은 주되, 거른 날을 벌하지 않음.

**구현** `features/rewards/`:
- 루틴 완료 시 `confetti` + `HapticFeedback.mediumImpact()` + 체크 애니메이션(모션감소 시 정적).
- 스트릭 계산: `completions`에서 "오늘 완료한 루틴이 1개 이상인 날" 연속 수.
  - **비처벌 규칙**: 하루 걸러도 0으로 리셋하지 않음 — "프리즈" 1~2회 자동 적용 또는 "최고 기록"만 강조하고 현재 스트릭은 부드럽게 표기.
  - 격려 문구(수치심 유발 금지): "오늘 하나라도 했으면 충분해요" 류.
- 홈/포커스에 작은 스트릭 배지.

**Acceptance**: 완료 시 효과 발생, 하루 걸러도 스트릭이 0으로 떨어지지 않음(단위 테스트로 로직 검증).

---

# STEP 11 — 메모 인박스 + 음성 + 전역 빠른 추가

**목표**: 잡생각을 1탭으로 즉시 캡처, 나중에 정리.

**구현**:
- **전역 FAB**: `app.dart`의 공통 `Scaffold`(또는 각 페이지)에서 항상 접근 가능한 빠른 추가 버튼.
  탭 → 바텀시트(텍스트 입력 + 🎤 음성 버튼). 저장 즉시 닫힘(마찰 최소화).
- **음성** `lib/services/speech_service.dart`: `speech_to_text`로 마이크 권한 요청 → 실시간 변환 → 텍스트로 저장(source='voice').
- **인박스** `features/memos/memo_inbox_page.dart`: 미확인 메모 리스트, '확인함' 토글, 카테고리 라벨(나중에 분류), 삭제, 검색.
- 접근성: 음성 버튼 큰 사이즈, 변환 실패 시 텍스트 폴백.

**Acceptance**: 어느 화면에서나 FAB→텍스트/음성으로 메모 추가, 인박스에서 확인 처리.

---

# STEP 12 — 설정 + 접근성 마감 + 온보딩

**목표**: 권한·계정·테마 제어, 접근성 검수, 첫 실행 안내.

**구현** `features/settings/`:
- 알림/정확알람/마이크 권한 상태 표시 + 요청 버튼(거부 시 시스템 설정 이동).
- 테마(라이트/다크/시스템), 글자 크기 슬라이더(`fontScale`→`MediaQuery.textScaler`), 모션 감소 토글.
- 계정: 익명 → Google/Apple 로그인 업그레이드 자리(STEP 9 이후).
- **온보딩**: 첫 실행 시 3~4장 가이드(구간 만들기→루틴→알람 권한 허용→메모). 기본 구간 템플릿(오전/오후/저녁) 제공 옵션.
- **접근성 검수**: TalkBack 켜고 주요 화면 라벨 읽힘, 글자 200%에서 레이아웃 안 깨짐, 대비 4.5:1 이상, 모든 정보가 색 외 단서(아이콘/텍스트) 동반.

**Acceptance**: 권한 토글 동작, 글자 크기/다크모드 즉시 반영, 온보딩 1회 노출.

---

# 최종 통합 검증 (전체 시나리오)

1. 온보딩 → 구간 3개 생성 → 각 구간에 루틴 추가(알람·전환예고 켬).
2. 홈 원형에 구간 호·루틴 마커·현재 바늘 정상 표시.
3. 루틴을 현재시각 +2분으로 설정 → 백그라운드 → 예고/본 알람 발화 → 스누즈 동작.
4. '지금' 화면에서 현재 루틴 표시·카운트다운·완료 → confetti+햅틱, 스트릭 증가.
5. 아무 화면에서 FAB로 텍스트·음성 메모 → 인박스 확인.
6. (STEP 9 완료 시) 비행기 모드 추가 → 복구 후 Firestore 동기화.
7. `puro flutter analyze` 에러 0, `puro flutter test` 통과.

---

## 막힘/주의 사항 (Gotchas)

- **알람 정확도**: Android 12+는 정확알람 권한 별도. 미허용 시 `inexact`로 폴백하고 사용자에게 안내.
- **알림 id 충돌**: routine별 결정적 id 규칙 고수, 변경 시 항상 cancel→reschedule.
- **자정 넘김 구간/루틴**: 모든 길이 계산은 `(end - start + 1440) % 1440` 패턴 사용.
- **Firebase는 대화형 인증 의존**: 에이전트 단독으로 `flutterfire configure` 불가 → STEP 9는 사용자 협조 필요. 그 전까지 로컬 구현으로 완전 동작해야 함.
- **iOS**: Windows에서 빌드 불가. iOS는 Mac/클라우드 빌드에서 별도 처리(알림 권한·푸시 설정 추가).
- 각 STEP 종료 시 커밋 단위로 작업(요청 시). git 미초기화 상태이므로 필요하면 `git init` 후 진행.
