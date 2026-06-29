# ADHD 플래너 개선 — 실행 명령서 (Sonnet 실행용)

> 이 문서는 다른 에이전트(Sonnet)가 **한 번에 한 TASK씩** 구현·검증·커밋하며 전체 개선 계획을 수행하도록 만든 실행 명령서다.
> 배경 분석/근거는 별도(`docs/IMPROVEMENT_PLAN.md` 또는 대화 기록)에 있고, 여기엔 **무엇을·어떻게·어떤 순서로·어떻게 검증하는지**만 담는다.

---

## 0. 실행 프로토콜 (모든 TASK 공통 — 반드시 지킬 것)

각 TASK는 아래 루프로 진행한다. **게이트를 통과하지 못하면 다음 TASK로 넘어가지 말 것.**

1. **오리엔테이션 읽기**: §1(코드베이스 지도)·§2(전역 규칙)을 먼저 숙지.
2. **[UI-CONFIRM] 표시가 있으면 먼저 사용자에게 UI 형태를 확정**받는다(AskUserQuestion). 다이얼로그/시트/풀스크린/버튼 배치 등은 임의 결정 금지 — 프로젝트 관례다.
3. **구현**: 해당 TASK의 "변경" 항목대로 코드 수정.
4. **테스트 추가/갱신**: "검증" 항목의 테스트를 반드시 추가하거나 갱신.
5. **검증 게이트(순서대로 모두 통과해야 함)**:
   - `flutter analyze <바뀐 파일들>` → **No issues found**
   - `flutter test` → **All tests passed**
   - `flutter build apk --debug` → **빌드 성공**(네이티브 변경 시 특히 필수)
6. **커밋**: §2의 커밋 규약대로 1 TASK = 1 커밋(또는 의미 단위로 분리).
7. **보고 후 정지 조건**: 게이트 실패 시, 또는 TASK에 **[REVIEW]** 표시가 있으면 사용자 확인을 받기 전까지 다음으로 진행하지 말 것.
8. 설치(`adb install`)는 사용자가 요청할 때만. 사용자가 기기 주소를 줄 때까지 빌드까지만 한다.

> **권한/프롬프트**: 명령은 PowerShell로 실행된다(아래 §2). 거부된 도구 호출은 그대로 재시도하지 말고 조정한다.

---

## 1. 코드베이스 지도 (이 줄들만 봐도 어디를 고칠지 안다)

**데이터 모델**
- `lib/data/models/segment.dart` — **블록**(구간+루틴 통합). 필드: id,name,colorValue,iconKey,startMinute,endMinute,order,note,microSteps,alarmEnabled,notificationIds. `copyWith/toMap/fromMap` 있음(주의: `fromMap`의 alarmEnabled 기본 true). 새 필드 추가 시 4곳(필드·생성자·copyWith·toMap·fromMap) 전부 갱신.
- `lib/data/models/app_settings.dart` — 전역 설정. 예: vibrationPattern, lastCelebratedDate 등. 새 설정 추가 패턴은 lastCelebratedDate를 그대로 따라 할 것.
- `lib/data/today.dart` — `dayKeyFor([now])`(yyyy-MM-dd), `completedBlockIdsOn(completions)`.
- `lib/data/block_status.dart` — `findBlockStatus(segments, nowMinute)` → `BlockStatus{segment,isCurrent}`.

**알람/알림**
- `lib/services/notification_schedule.dart` — 순수 로직. `buildSchedule(segments)`(alarm-enabled 블록당 매일 1개 spec), `notificationIdFor(segmentId, slot)`, `nextInstanceOf(minuteOfDay)`, `ScheduledSpec`. (요일 7개 → 매일 단일로 단순화 완료 상태.)
- `lib/services/notification_service.dart` — `rescheduleAll`(cancelAll 후 zonedSchedule `DateTimeComponents.time` + 네이티브 진동알람 7일→1일 재무장), `cancelNotification`, `cancelBlockAlarms`, `_scheduleVibrationAlarm`. 채널명 `com.adhdplanner.adhd_planner/alarm_sound`.
- `lib/features/focus/alarm_screen.dart` — **풀스크린 알람**. 슬라이드 해제(`_SlideToDismiss`, key `alarm-dismiss-thumb`) → `_dismiss`가 `pushAndRemoveUntil`로 루트까지 정리 후 `FocusPage.forBlock`. 화면 떠 있는 동안 네이티브에 `startScreenOffGuard`/`stopScreenOffGuard`(전원버튼=ACTION_SCREEN_OFF 무음). 콜백 `onAlarmDismissedByPower`.
- `lib/app.dart` — 무화면 워처들: `_AlarmAlertLauncher`(pendingAlarmAlert→`_showAlarmScreen`), `_ForegroundAlarmWatcher`(1초 틱, startMinute==now면 알람), `_AccountAlarmSync`, `_AchievementRecorder`, `_CompletionCelebrator`. 전역: `alarmScreenOpen`(중복 방지), `appNavigatorKey`(quick_add_button.dart 정의), `pendingAlarmAlert`.
- 네이티브: `android/app/src/main/kotlin/.../MainActivity.kt`(alarm_sound 채널·진동·screen-off 가드), `VibrationAlarmReceiver.kt`(주기 재무장, `cancel`/`cancelAll`/`stopVibration`). 매니페스트: portrait 고정, showWhenLocked/turnScreenOn, USE_FULL_SCREEN_INTENT.

**홈/Focus**
- `lib/features/planner/planner_page.dart` — 홈 다이얼. `_HomeHeader`(날짜+인사), 배지(StreakBadge·DailyChecklistBadge), `_Dial`(탭→FocusPage.forBlock, 길게→SegmentFormPage(existing)), `_CenterSummary`(지금/다음+지금 버튼), `_NextBlockCountdown`, `_AmbientBackdrop`. FAB: `MultiFabRow(left: GlobalQuickAddButton, right: 구간추가)`.
- `lib/features/focus/focus_page.dart` — Focus. live=`findBlockStatus`, 체크리스트=`_microStepsChecklist`(CheckboxListTile, 전부 체크 시 자동완료), 루틴없음=`_buildRestComposition`(`_restQuote`=`restQuoteRandom()` 진입 시 1회). 테스트 시드: 생성자 `debugNowMinuteOfDay`.
- `lib/features/focus/rest_quotes.dart` — `restQuotes`(42개), `restQuoteRandom()`(진입마다 랜덤), `restQuoteForToday()`(하루 고정, 축하용).

**보상/스트릭**
- `lib/features/rewards/daily_achievement.dart` — `DailyAchievement{checked,total,hasAnyCompletion, isAchieved(≥50% 또는 total0이면 완료유무)}`, `dailyAchievementFor(...)`, `achievedDateKeys(...)`, `streakDateKeys(achievedDays, ..., now)`(과거는 저장된 AchievedDay만, 오늘은 실시간). 영구 저장 규칙: 과거 달성일은 절대 덮어쓰지 않는다.
- `lib/features/rewards/completion_celebration.dart` — `showCompletionCelebration(context, reduceMotion:)` 풀스크린 컨페티. 트리거: `_CompletionCelebrator`(app.dart)가 오늘 checked==total일 때 1회, `AppSettings.lastCelebratedDate`로 영속.
- `streak_badge.dart`, `daily_checklist_badge.dart`(오늘 N/M).

**메모/구간**
- `lib/features/memos/` — `quick_add_sheet.dart`(`showQuickAddSheet`, `showEditMemoSheet`, `QuickAddSheet(existing:)`), `memos_controller.dart`(`add/setReviewed/edit/delete`), `memo_inbox_page.dart`(ListTile + 앞 Checkbox + 본문탭→수정 + 스와이프 삭제).
- `lib/features/segments/` — `segments_controller.dart`(`upsert/delete`는 Firestore 쓰기를 **unawaited**로 두고 `_rescheduleAll` 호출 — 오프라인 차단 방지), `segment_form_page.dart`(`existing:`로 수정), `segment_editor_page.dart`, `segment_icons.dart`(`iconForKey`).

**테스트**
- `test/` 미러 구조. `test/fakes/fake_planner_repository.dart`(인메모리 repo). 위젯 테스트는 `ProviderScope(overrides:[plannerRepositoryProvider.overrideWithValue(repo)])`. Focus 시계 의존은 `FocusPage(debugNowMinuteOfDay: 12*60)`로 고정. 현재 **162개 통과**가 기준선.

---

## 2. 전역 규칙 / 가드레일 (위반 금지)

**환경/명령 (Windows, PowerShell)**
- Flutter 명령은 **PowerShell**로: `flutter analyze`, `flutter test`, `flutter build apk --debug`. (Bash의 flutter 래퍼는 puro 경로가 깨져 있어 쓰지 말 것.)
- adb 경로: `C:\Users\MS\AppData\Local\Android\Sdk\platform-tools\adb.exe` (PATH에 없음). 설치: `adb connect <ip:port>` 후 `adb -s <ip:port> install -r build\app\outputs\flutter-apk\app-debug.apk`.
- 실기기 설치는 **디버그 빌드만**(release 금지). 기기 IP는 `192.168.0.34`, **포트는 매번 바뀐다** → 사용자가 주는 새 `ip:port` 사용. 안 주면 빌드까지만.
- **도구 출력은 작게**: 통짜 `git diff`·거대한 파일 통읽기·큰 명령 출력 금지(한글이 잘려 `invalid high surrogate` 400 유발). Read는 offset/limit, Grep은 output_mode/head_limit, diff는 `--stat`/파일 단위.

**제품/플랫폼 제약**
- **세로 모드 전용**(main.dart의 SystemChrome + 매니페스트 portrait). 새 화면도 세로 기준으로만 설계. 가로 대응 불필요.
- **UI는 한글**. 영어 i18n은 아직 미도입(P2에서 다룸). 새 문자열은 한글 하드코딩(나중에 교체 쉽게 한 곳에 모으기).
- **하단 콘텐츠는 항상 메모 FAB 위**. 바닥 위젯은 `fabAvoidingBottomInset(context)`(quick_add_button.dart) 만큼 띄울 것.
- **오프라인 쓰기 패턴**: Firestore 쓰기 Future는 오프라인에서 resolve 안 됨. 쓰기 뒤에 부수효과(재스케줄·화면전환)가 있으면 쓰기를 `await`하지 말고 `unawaited(...)`로. 로컬 캐시는 동기 갱신되므로 직후 `watch...().first` 읽기는 안전. (참고: `segments_controller`, `_CompletionCelebrator`.)
- **UI 형태 사전 확정**: 다이얼로그 vs 시트 vs 풀스크린, 버튼 배치 등은 만들기 전 사용자에게 물을 것([UI-CONFIRM] TASK).

**테스트 규율**
- 기능 추가/수정마다 테스트 추가 또는 갱신. 기준선(162개) 깨지면 그 자리에서 고친다.
- 시계 의존 위젯 테스트는 고정 시각 주입(예: `debugNowMinuteOfDay`). 새로 시계에 의존하는 화면을 만들면 같은 주입 시드를 제공.
- 애니메이션이 `pumpAndSettle`을 막을 수 있음(컨페티 등) — 자동 발화하는 풀스크린 연출은 테스트에서 억제 가능하게(예: 설정 플래그/주입).

**커밋 규약**
- 한국어, `유형: 요약` 형식(예: `추가:`, `수정:`, `변경:`). 본문에 무엇/왜.
- 마지막 줄에 반드시:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```
- 기본 브랜치 `main`에 직접 커밋(이 저장소 관례). 푸시는 사용자가 요청할 때.

**Definition of Done (TASK 1개)**
- [ ] 변경 구현 + 한글 문자열
- [ ] 테스트 추가/갱신, `flutter test` 전체 통과
- [ ] `flutter analyze` 무결
- [ ] `flutter build apk --debug` 성공
- [ ] 커밋(규약 준수)
- [ ] [REVIEW]거나 게이트 실패면 사용자 보고 후 정지

---

## 3. TASK 목록 (실행 순서대로)

> 권장 순서: **T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11**.
> **UI 형태는 이미 확정 완료** — T2·T3·T5·T6·T8·T9의 "확정 사양" 블록을 그대로 따르면 되고, 화면 형태를 다시 묻지 말 것(세부 픽셀/배치 미세조정만 재량). 남은 사용자 확인 지점은 **[REVIEW]**(T11 범위)뿐.

### T1 — 스트릭 안전장치 + 부분 보상 + 자기연민 카피  〔규모 M〕 ✅(ab0f013)
- **목표**: 나쁜 날에도 앱이 안전한 곳. 스트릭 절벽 완화, 부분 성공 보상.
- **실행 결과 (2026-06-26, Sonnet 4.6 실행)**: 구현 전 코드 확인 결과 **항목 1(유예일)은 이미 구현돼 있었음** — `streak.dart`의 `currentStreak`/`longestStreak`가 `freezeAllowance=2`로 grace를 처리하고(`streakDateKeys`보다 한 계층 위), `streak_test.dart`에 경계 테스트도 이미 존재. 재구현하지 않고 그대로 둠. 항목 2~4(부분 보상·마일스톤·카피)만 신규 구현. 다음 실행자는 "유예일"을 다시 만들지 말 것.
- **변경**:
  1. ~~유예/회복~~ — 스킵(이미 구현됨, 위 참고).
  2. **부분 보상 (구현 완료)**: `_CompletionCelebrator`(app.dart) 확장. `achievement.total > 0 && achievement.isAchieved && !fullyDone`을 `partiallyDone`으로 정의(체크리스트가 있는 날의 50%↑·100%미달만 — 항목 없는 날의 whole-block fallback 달성은 제외해 "절반"이라는 말이 의미 없는 케이스를 막음). 100%(`fullyDone`)와 `if/else-if`로 상호배타 처리 후 각각 독립적으로 reset. 마커: `AppSettings.lastPartialCelebratedDate`(신규 필드, `lastCelebratedDate`와 동일 패턴으로 필드·생성자·copyWith·toMap·fromMap 4곳 갱신). 표시는 `showAppSnackBar`(quick_add_button.dart, 이미 app.dart에 import돼 있음) — 풀스크린 다이얼로그 아님, 가벼운 스낵바. 문구: `오늘 절반을 해냈어요 — 충분히 잘하고 있어요`.
  3. **마일스톤 가변화 (구현 완료)**: `completion_celebration.dart`에 `const Set<int> celebrationMilestones = {3, 7, 14, 30, 60, 100}` 공개 상수 추가. `showCompletionCelebration`/`_CompletionCelebration`에 `int streakDays = 0` 파라미터 추가 — 마일스톤에 해당하면 본문 타이틀 아래 `$streakDays일 연속, 정말 멋져요!` 줄 추가, 아니면 기존과 완전 동일(매일 숫자 노출 안 함). `_CompletionCelebrator`가 100% 트리거 시 `achievedDaysProvider`를 watch해 `currentStreak(streakDateKeys(...))`로 오늘 포함 스트릭을 계산해 전달.
  4. **카피 (구현 완료)**: `StreakBadge`에서 `best > 0 && current == 0`(스트릭이 막 0으로 끊긴 상태) 케이스를 위해 시각 텍스트와 **Semantics 라벨 둘 다** `· 다시 시작해도 좋아요` / `최고 연속 N일, 다시 시작해도 좋아요`로 교체 — 기존엔 시각은 침묵, 라벨은 "현재 연속 0일"이라는 적나라한 0을 그대로 말하고 있었음(접근성 누락 발견·수정). "실패/미달성" 어휘는 grep 확인 결과 rewards/checklist 쪽엔 이미 없었음(코드 주석 1건 제외, user-facing 아님).
- **파일 (실제)**: `app_settings.dart`(`lastPartialCelebratedDate` 필드), `app.dart`(`_CompletionCelebrator` — partiallyDone 분기·streak 계산, import `features/rewards/streak.dart` 추가), `completion_celebration.dart`(`celebrationMilestones`·`streakDays` 파라미터), `streak_badge.dart`(0-추락 카피). `daily_achievement.dart`는 **변경 없음**(grace는 다른 파일에 이미 있었으므로).
- **검증 (실제)**: `streak_test.dart`의 기존 grace 경계 테스트 그대로 유효(재확인만, 변경 없음). 신규: `streak_badge_test.dart`에 best>0&&current==0 케이스(시각 텍스트 + Semantics 라벨에 "현재 연속 0일" 부재 확인) 1개, `completion_celebration_test.dart`(신규 파일) 4개(비-마일스톤/마일스톤/상수값/reduceMotion), `widget_test.dart`에 App 레벨 통합 3개(50% 스낵바 발화·재발화 안 함·100%+마일스톤 줄). 전체 162→**170개 통과**, analyze 무결, `flutter build apk --debug` 성공.
- **커밋**: `ab0f013` — `추가: 스트릭 부분 달성(50%) 보상 마일스톤 변주 자기연민 카피 (T1)`.
- 비고: [[영구 저장 규칙]] 위반 없음 — `AchievedDay` 저장/`daily_achievement.dart` 미변경, 새 마커들은 설정 문서일 뿐 달성 이력이 아님.

### T2 — 알람 반응 옵션 복원 (스누즈 · 오늘 건너뛰기 · 전환 예고)  〔규모 L〕 [UI-CONFIRM 완료] ✅(d46a687)
- **목표**: 알람을 무시 대신 "미루기/오늘 패스/미리 알림"으로 응답 가능하게.
- **실행 결과 (2026-06-26, Sonnet 4.6 구현 → Opus 4.8 검토)**:
  - 세 항목(스누즈/건너뛰기/전환예고)이 모두 확정 사양대로 구현됨. **네이티브 코드 변경 0** — 스누즈의 1회성은 기존 `_scheduleVibrationAlarm`에 `repeatInterval: Duration.zero`만 넘기면 됨(`VibrationAlarmReceiver.kt`가 `repeatIntervalMs > 0`일 때만 재무장 — 이미 그렇게 동작하고 있었음), 전환 예고 채널은 `flutter_local_notifications`가 첫 스케줄 때 자동 생성(메인 알람만 진동 무음화 버그 회피용 네이티브 `ensureAlarmChannel`이 필요했던 것).
  - **버그 발견·수정**: `AlarmScreen`의 `PopScope(canPop: false)`가 시스템 백제스처만 막아야 하는데 `Navigator.maybePop()`(따라서 `popDisposition` 경로 전체)까지 막는다는 걸 위젯테스트가 잡음 — 새 스누즈/건너뛰기 버튼이 `maybePop()`으로 화면을 닫으려다 안 닫히던 실제 버그. `Navigator.pop()`(직접 호출, `popDisposition` 미경유)으로 교체해 해결. **[REVIEW] 항목**: 이 PopScope 동작은 Flutter 프레임워크 소스로 확인했지만, 실기기에서 두 버튼이 실제로 화면을 닫는지 별도 확인 가치 있음.
  - 세 기능이 `app_settings.dart`/`notification_service.dart` 등 같은 파일의 같은 함수 안에서 얽혀 구현돼, 계획서가 제안한 2-커밋 분리(`스누즈/건너뛰기` vs `전환예고`) 대신 **하나의 커밋**으로 묶음 — 인위적 분리 시 중간 커밋이 컴파일 안 되는 상태가 될 위험.
  - `AppSettings.leadMinutes`는 필드만 추가(전역 기본 10), 사양대로 설정화면 UI는 만들지 않음(스누즈 분만 UI 있음).
  - **실기기 검증 중 추가 버그 발견·수정 (커밋 f76fa51)**: 사용자가 Z Flip7 실기기에서 "스누즈로 미룬 알람이 다시 울릴 때 벨소리모드는 전혀 안 울리고 무음모드는 진동이 짧게 한 번만"이라고 보고. 원인은 `_snooze()`가 `cancelNotification`(취소)과 `scheduleSnooze`(재예약)을 `unawaited`로 순서 보장 없이 나란히 발사 — 둘 다 같은 네이티브 채널로 같은 `requestCode`의 AlarmManager 항목을 다루는데 각자 다른 await 체인을 타 실제 도착 순서가 뒤집힐 수 있었음(스케줄이 취소보다 먼저 도착하면 막 건 스누즈 알람이 바로 지워짐). `await cancel; await schedule;`로 순서 고정. 기기에서 알람 볼륨/DND/STREAM_ALARM 상태를 `adb dumpsys audio`로 확인해 기기 설정 쪽 원인은 배제. 가짜 NotificationService(취소를 인위적으로 지연)로 호출 완료 순서를 고정하는 회귀테스트 추가. test 189→190.
  - **실기기 재검증 후 두 번째 버그(설계 결함) 발견·수정 (커밋 e823dd3)**: f76fa51 적용 후에도 "잠금상태 본알람: 화면만 켜지고 벨 안 들리고 진동 한 번뿐, 잠금 풀면 이미 조용한 풀스크린만 남음" 보고. 원인은 `_handleResponse`(알림 탭/fullScreenIntent 자동실행 시 호출)가 그 즉시 `_silenceAlarm`을 불러 벨/진동을 껐던 기존 설계 — 폴더블 커버 화면이 알람 화면을 못 띄울 경우를 위한 안전장치였으나, 부작용으로 사용자가 반응하기 전에 화면 켜지는 신호만으로 알람이 무음 처리됨. **사용자에게 변경 여부를 직접 확인**(채팅으로, AskUserQuestion 도구가 이 시점 한글 인코딩 깨짐 — 직접 텍스트로 질문) 후 승인받아 `_handleResponse`의 자동-무음 호출 제거. 이제 끄는 경로는 AlarmScreen의 명시적 동작 3가지 + 전원버튼 가드뿐이며, 손이 안 닿는 경우의 안전장치는 기존 60초 타임아웃이 유지. 알림 채널 모킹 회귀테스트 추가. test 190→192.
  - **부수적으로 발견된 두 가지 (T2 범위 밖, 기존부터 있던 결함) — 별도 커밋, 둘 다 미확정 보류**:
    - ① 설정 화면 알람음 선택 행에서 `currentUri==null`(기본값 사용 중)일 때 네이티브 RingtoneManager 피커가 목록 어디에도 체크 표시를 안 보여줌. 1차 수정(1a1501e, `getDefaultUri` 간접 지시 URI 사용)은 효과 없었고, 2차 교정(09cc28f, `getActualDefaultRingtoneUri` 실제 파일 URI 사용)으로 이론상으론 맞게 고쳤으나 **사용자가 실기기에서 확신을 못 얻은 채 "일단 넘어가자, 나중에 확실히 잡겠다"고 보류**(2026-06-28). 다음 실행자/검토자는 이 항목을 "해결됨"으로 단정하지 말 것 — 실기기 재확인 필요.
    - ② "알람이 실제로 울리는 도중에 설정의 알람음 행을 누르면 한 번 크래시"가 보고됐으나 재현이 알람 활성 상태를 요구해 로그를 못 잡음 — **사용자 요청으로 보류, 나중에 마주치면 그때 로그캡처로 진단**.
- **확정 사양 (UI 결정 완료 — 추가 질문 불필요)**:
  - AlarmScreen 레이아웃: 기존 **슬라이드 해제(=시작)** 유지, 그 **아래에 텍스트버튼 2개 좌우** — 왼쪽 `10분 뒤 다시`, 오른쪽 `오늘은 건너뛰기`. (하단 콘텐츠가 슬라이드 트랙을 가리지 않게 간격 확보.)
  - **스누즈 기본 10분**, `AppSettings`에 `snoozeMinutes`(허용값 5/10/15, 기본 10) + 설정 화면 선택 UI.
  - **전환 예고: 켬(기본)**, 시작 **10분 전**, **풀스크린 아님(조용한 헤드업 알림, 별도 저강도 채널)**. 전역 기본 on + **블록별 끄기** 가능(`Segment.leadWarning` bool, 기본 true). 예고 분(`leadMinutes`)은 `AppSettings` 전역 기본 10.
- **변경**:
  1. **스누즈**: AlarmScreen 버튼 → 현재 알람 무음 + **+N분 일회성** 알람 예약. `notification_service`에 일회성 예약 경로 추가(반복 아님, `matchDateTimeComponents` 없이 1회 `zonedSchedule` + 네이티브 진동 1회). 알람 화면 닫기.
  2. **오늘 건너뛰기**: 오늘자 해당 블록 알람 억제. 저장은 `microStepProgress` 패턴을 따른 per-(block,day) **skip 레코드**. `_ForegroundAlarmWatcher`가 skip된 블록은 재팝 금지. (이미 발화한 예약 알림은 무음 처리.)
  3. **전환 예고**: 블록 시작 `L분 전` 저강도 헤드업 알림. `buildSchedule`에 예고 spec 추가(별도 slot, fullScreenIntent=false, 별도 채널), `notificationIdFor(segmentId, slot=1)`. 전역 기본 L분 + 블록별 on/off(Segment 필드 또는 설정).
- **파일 (실제)**: `lib/data/models/alarm_skip.dart`(신규), `lib/features/focus/alarm_skip_controller.dart`(신규), `data/repositories/planner_repository.dart`/`firestore_planner_repository.dart`/`test/fakes/fake_planner_repository.dart`(alarmSkips 한 벌), `data/providers.dart`(`alarmSkipsProvider`), `data/today.dart`(`skippedBlockIdsOn`), `data/models/segment.dart`(`leadWarning`), `data/models/app_settings.dart`(`snoozeMinutes`/`leadMinutes`), `services/notification_schedule.dart`(`isLeadWarning`/`buildSchedule(leadMinutes)`), `services/notification_service.dart`(`scheduleSnooze`, lead 채널/분기), `features/focus/alarm_screen.dart`(버튼 UI+동작+pop 버그수정), `app.dart`(워처 skip 가드), `features/segments/segment_form_page.dart`(전환예고 토글), `features/settings/settings_page.dart`(스누즈 분 선택).
- **검증 (실제)**: `notification_schedule`/`notification_service_test.dart`에 6개(예고 spec 생성·슬롯 비충돌·자정 wrap·payload 태그). `data/today_test.dart`에 `skippedBlockIdsOn` 2개. `segment_test.dart`/`app_settings_test.dart`에 round-trip 각 2개. `alarm_screen_test.dart`에 4개(버튼 표시·스누즈 동작·건너뛰기 동작, 기존 슬라이드 테스트 유지). `segment_form_page_test.dart`/`settings_page_test.dart`에 토글/칩 각 2개. 합계 172→**189개 통과**, analyze 무결, `flutter build apk --debug` 성공(네이티브 변경 없음 — 위 참고).
- **커밋**: `d46a687` — `추가: 알람 스누즈 · 오늘 건너뛰기 · 구간 전환 예고 알림 (T2)` (단일 커밋, 사유는 위 실행 결과 참고).
- 비고: 과거에 의도적으로 제거했던 기능의 재도입 — 커밋 본문에 명시함([[project_alarm_alert_postpone_design]] 계열 메모가 있다면 함께 갱신 권장). **[REVIEW] 남음**: 실기기에서 잠금화면/포그라운드 상태의 알람·스누즈·건너뛰기·전환예고 실제 동작 확인.

### T3 — 빈 상태·계획 보조 (스타터 칩 + 브레인덤프→자동배치)  〔규모 M~L〕 [UI-CONFIRM 완료] ✅(8a47371)
- **목표**: 빈 다이얼 콜드스타트 제거.
- **T3 범위 밖, 실기기 검증 중 발견·수정한 독립 버그 (커밋 88fc9c4, a0a8495)**: 사용자가 로그아웃 시 완료축하 팝업이 잘못 뜨고, 실제 체크완료 시엔 팝업이 순식간에 사라진다고 보고. 두 가지 별개 원인 — ① 로그아웃의 uid=null 구간에서 `settingsProvider`는 즉시 defaults로 리셋되는데 `segments/completions/progress/achievedDays`는 빈 스트림으로 바뀌어도 Riverpod가 이전 계정의 마지막 값을 유지. **88fc9c4의 1차 수정(`plannerRepositoryProvider == null`이면 건너뛰는 가드)은 실기기에서 동작하지 않았다** — adb logcat으로 재추적한 결과, uid=null 구간 자체는 가드가 잘 막았지만 그 *다음*(새 익명 계정의 repo가 이미 활성화된 뒤에도 segments 등 4개 provider가 각자 새 구독을 거는 데 실기기에서 ~100ms+ 걸려 옛 계정 값을 그대로 보여주는 구간)에 여전히 오발화했다. a0a8495에서 "repo가 null인가"가 아니라 "5개 provider 각각이 isLoading인가"로 가드를 교정 — 같은 구조(데이터가 다 모인 뒤에야 쓰기)인 `_AchievementRecorder`에도 동일 가드 추가(과거 미banked 일자를 새 계정에 잘못 쓸 위험). 실기기 logcat으로 정확한 발화/차단 시점을 확인했고, 회귀 테스트도 정적 override 대신 `ProviderContainer`+`StateProvider`로 실제 Riverpod 전환·비대칭 catch-up을 재현하도록 다시 작성(가드 끄면 red, 켜면 green 확인). ② `focus_page.dart`의 `_complete()`가 자체 900ms 셀러브레이션 후 `Navigator.pop()`으로 Focus를 닫는데, 같은 순간 `_CompletionCelebrator`도 완료축하 다이얼로그를 같은 네비게이터 위에 띄워 경쟁 — `pop()`은 항상 "현재 맨 위"를 제거하므로 늦게 도착한 Focus의 pop이 다이얼로그를 지워버림. `route.isCurrent`로 위에 뭔가 떴는지 확인해 그 경우만 자기 라우트를 `removeRoute`로 specifically 제거(유일 라우트일 때 `removeRoute`가 `_history.isNotEmpty` 단언을 깨는 것도 같은 분기로 회피). 부수로 `brain_dump_page_test.dart`의 자정-인접 플레이키 테스트도 발견해 `BrainDumpPage`에 `debugNowMinuteOfDay` 시드 추가. test 208→210.
- **실행 결과 (2026-06-28, Sonnet 4.6 구현)**: 확정 사양대로 구현. 한 가지 실제 버그를 구현 중 발견·수정: 빈 상태 콘텐츠(안내문+칩7+버튼)의 자연 높이가 옛 다이얼의 `dialSize`처럼 화면 크기에 맞춰 계산되지 않아, 작은 화면/테스트 서피스에서 `RenderFlex` 오버플로우가 났음(기존 `app bar action`/`구간 추가 FAB` 테스트가 이걸로 깨짐 — 내 변경의 직접 회귀). 빈 상태 전용 Column을 `Expanded`+`SingleChildScrollView`로 분리해 해결. 기존 "지금' 버튼이 빈 상태에서도 동작" 테스트는 그 어포던스 자체가 새 디자인에서 의도적으로 사라졌으므로(빈 다이얼 자체가 없어짐) 삭제, "오늘 일정이 없어요" 테스트는 새 스타터칩 기준으로 교체.
- **확정 사양 (UI 결정 완료)**:
  1. **빈 상태 홈**: `segments`가 비면 다이얼 대신 안내문 + **개별 스타터 칩**을 Wrap으로. 칩 1탭 = 그 블록 1개를 기본 시각·아이콘으로 추가(다이얼이 즉시 채워짐). 칩 세트(7종, 합리적 기본 시각·아이콘):
     - 기상 07:00–07:30, 약 07:30–07:40, 아침 07:40–08:10, 집중 09:00–11:00, 점심 12:00–13:00, 휴식 15:00–15:30, 수면 23:00–익일(end는 1439 등 합리값). 아이콘은 `segment_icons.dart`의 기존 key 사용.
     - 데이터는 `lib/features/segments/segment_templates.dart`(신규)에 `const` 리스트로. 칩 추가는 `segments_controller.upsert`(오프라인 unawaited 패턴) 사용.
  2. **브레인덤프 → 블록 (자동 시각 추천 포함)**: 떠오르는 일들을 나열(텍스트, 음성 캡처 재사용) → **"시각 자동 배치"** 버튼으로 각 항목에 시각 제안 → 사용자가 조정 가능 → 일괄 생성.
     - 자동배치는 **순수·결정적 함수** `suggestSlots(items, existingSegments, anchorMinute)`로 구현(단위테스트 필수). 휴리스틱(1차): anchor = max(현재시각을 30분 올림, 마지막 기존 블록 end). 각 항목 기본 30분, 기존 블록과 겹치면 다음 빈 구간으로 밀어 순차 배치. 자정 넘기면 중단/경고.
     - 생성 전 미리보기에서 시각/길이 수정 가능. 일괄 생성은 `segments_controller`에 bulk upsert 추가.
- **파일 (실제)**: `lib/features/segments/segment_templates.dart`(신규, 칩 7개 데이터), `lib/features/segments/slot_suggester.dart`(신규, `suggestSlots`/`anchorMinuteFor`/`SuggestedSlot` 순수 함수), `lib/features/segments/brain_dump_page.dart`(신규, 2단계 화면: 목록입력→미리보기), `segments_controller.dart`(`upsertAll` 추가), `planner_page.dart`(빈 상태 분기 + `_EmptyHomeStarter`), `test/features/planner/planner_page_test.dart`(빈 상태 테스트 교체).
- **검증 (실제)**: `slot_suggester_test.dart` 12개(라운딩·기존블록 회피·자정 컷오프·wrap 가드). `brain_dump_page_test.dart` 4개(버튼 활성/비활성·목록 추가삭제·미리보기·일괄생성·목록으로 돌아가기). `planner_page_test.dart`에 빈상태 렌더 1개 + 칩탭→생성 1개(교체). 전체 192→**208개 통과**, analyze 무결, build 성공.
- **커밋**: `8a47371` — `추가: 빈 다이얼 스타터 칩 + 브레인덤프로 한꺼번에 시각 배치 (T3)` (단일 커밋).

### T4 — 메모 '닫는 고리' (블록 승격 + 재부상)  〔규모 M〕 [UI-CONFIRM 완료] ✅(aa5d2e3)
- **목표**: 메모 무덤 방지 — 캡처를 행동(블록/항목)으로.
- **변경**:
  1. 메모 항목에 **"블록/할일로 승격"**: `SegmentFormPage`를 메모 텍스트로 프리필해 열거나, 기존 블록의 microStep으로 추가하는 선택 시트.
  2. **재부상**: 오래된 미검토 메모를 가끔 상단에 넛지("이 메모, 아직이에요").
  3. (선택) "오늘 처리할 메모 N개" 소형 표면.
- **파일**: `memo_inbox_page.dart`, `memos_controller.dart`(또는 segments_controller 연계), `quick_add_sheet.dart`(재사용).
- **검증**: 승격 시 블록/마이크로스텝 생성 컨트롤러 테스트, 메모 인박스 위젯테스트(기존 탭=수정·체크·스와이프 유지). 전체 통과.
- **커밋**: `추가: 메모를 블록/할일로 승격, 오래된 메모 재부상`.
- **확정 사양 (UI 결정 완료)**: 1) 승격은 메모 행 **롱프레스** → 바텀시트("새 블록으로 만들기" / "기존 블록에 항목으로 추가"), 완료 시 메모 reviewed=true. 2) 재부상은 인박스 상단 카드, **3일 이상** 미확인 메모 중 가장 오래된 것 하나, **하루 한 번**(AppSettings.lastMemoNudgeDate). 3) "오늘 처리할 메모 N개" 표면은 사용자 지시로 **보류**(project_memo_today_count_surface_deferred 메모리).
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: 확정 사양대로 구현, 1·2번만(3번 보류). `SegmentFormPage`에 `initialName` 파라미터 + 저장 시 `Navigator.pop(context, true)` 추가(승격 성공 여부 판별용). 신규: `memo_resurfacing.dart`(순수 `oldestNudgeworthyMemo`/`kMemoNudgeMinAge`), `promote_memo_sheet.dart`(승격 시트 + 블록 피커). `AppSettings.lastMemoNudgeDate` 필드 추가(4곳 패턴). 구현 중 실제 버그 두 건 발견·수정: ① 기존 `memo_inbox_page_test.dart` 픽스처가 고정 과거 날짜를 써서 재부상 기준(3일)에 걸려 텍스트 중복으로 4개 테스트 깨짐 → `MemoInboxPage`에 `debugNow` 시드 추가(FocusPage의 `debugNowMinuteOfDay`와 같은 패턴). ② 승격 플로우가 `ref.read(segmentsProvider).value`를 직접 읽었는데, 그 provider를 트리의 아무도 먼저 watch한 적 없으면 첫 읽기가 스트림의 비동기 첫 이벤트보다 앞서 동기적으로 빈 리스트를 반환하는 레이스 발견 → `SegmentsController`가 이미 쓰는 "저장소에서 직접 fresh read" 패턴으로 교정. test 210→227(+17). 실기기 설치·확인 완료(사용자 "확인완료").

### T5 — Focus를 진짜 집중 도구로 (블록 내 잔여시간 + 짧은 타이머 + 2분 룰)  〔규모 M~L〕 [UI-CONFIRM 완료] ✅(8d443ba)
- **목표**: 시간맹(블록 내부)·착수·과몰입 탈출 대응.
- **확정 사양 (UI 결정 완료)**:
  1. **블록 잔여시간**: Focus 상단에 **진행 링(또는 바) + "20분 남음"** 텍스트(현재 블록 경과/잔여). 시계 의존이므로 위젯테스트는 `debugNowMinuteOfDay` 시드로.
  2. **집중 타이머**: 시작 → 타임박스. **25분 집중/5분 휴식(포모도로) 기본 + 15분 + 사용자정의** 선택. 진행 링, 일시정지/취소. 상태는 riverpod 컨트롤러.
  3. **타이머 종료 알림(백그라운드 포함)**: 타이머 시작 시 **종료 시각에 일회성 알림 예약**(앱을 나가 있어도 진동/소리). → **T2의 일회성 알림 예약 경로를 재사용**(별도 채널). 앱이 떠 있으면 인앱 표시도.
  4. **"2분만 시작" 버튼**: 큰 시작 옆/아래에 제공 → 2분 타이머로 초저력 착수. 동작은 일반 타이머와 동일(길이만 2분).
- **의존**: T2 선행 권장(일회성 알림 예약 인프라 공유). T2 이후 T5를 하면 중복 구현 없음.
- **파일**: `focus_page.dart`, 타이머 컨트롤러(신규, riverpod), 필요 시 알림 인프라.
- **검증**: 타이머 컨트롤러 단위테스트(시작/일시정지/완료 전이), Focus 위젯테스트(잔여시간 표시는 `debugNowMinuteOfDay` 시드로 결정). 전체 통과.
- **커밋**: `추가: Focus 블록 잔여시간·집중 타이머·2분 룰`.
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: 확정 사양대로 구현, 실기기 다단계 검증으로 디자인·버그 모두 수정. ① 잔여시간 표시는 처음엔 상단 분리 막대였으나 사용자가 "원형 그래픽에 합쳐서"라고 명확히 지적해 `WaitingIllustration`의 가장 바깥 ripple 링을 진행률 트랙+아크로 교체하는 형태로 재설계(`progress` 파라미터 신규, null이면 다른 화면 영향 없음). ② 타이머 종료 진동이 처음엔 너무 짧음(명시적 vibrationPattern 누락) → 추가했는데도 무음모드에서 안 울림 → T2의 메인 알람과 같은 Samsung OneUI 버그로 확인, 네이티브 Vibrator 직접 호출(기존 `VibrationAlarmReceiver.kt` 재사용, 새 코드 없음)로 해결. ③ **치명적 레이아웃 버그 발견**: 체크리스트가 하단 FAB(메모/모두완료) 영역을 침범, 스크롤로도 못 피함 — `SingleChildScrollView` 내부 padding만으론 콘텐츠가 짧아 스크롤이 안 일어나는 경우 효과 없다는 걸 실기기로 확인, `Expanded` 전체를 `Padding(bottom: fabAvoidingBottomInset)`로 감싸 가용 높이 자체를 줄이는 방식으로 교정(다른 5개 FAB 화면은 전부 이미 이 방식이라 점검만 함). ④ 타이머 섹션이 체크리스트와 같이 스크롤되던 것도 지적받아 헤더(원형+스트릭) 쪽 고정 영역으로 재배치. test 226→250(+24).

### T6 — 다음 한 행동(Next Action) 저부하 모드  〔규모 M〕 [UI-CONFIRM 완료] ✅(f7efe18)
- **목표**: 과제마비형 구제 — 하루 전체 대신 "지금 딱 하나".
- **확정 사양 (UI 결정 완료)**:
  - **진입**: **홈 상단의 토글 버튼**으로 다이얼 ↔ 다음한행동 즉시 전환(별도 라우트 push 아님, 같은 홈에서 뷰 스왑). 마지막 선택 상태는 기억(설정/로컬).
  - **화면 구성**: 다이얼·배지·카운트다운 숨기고 **현재(없으면 다음) 블록 1개 + 큰 '시작' 버튼**만. `findBlockStatus` 재사용. 시작 → `FocusPage.forBlock`. "지금/다음 없음"이면 차분한 빈 메시지.
  - FAB 규칙 동일(하단 메모 FAB 위 유지).
- **파일**: 신규 미니멀 뷰, `app_settings.dart`(모드 플래그), 라우팅(`_RootRouter`/홈 토글).
- **검증**: 모드별 렌더 위젯테스트(현재 있음/없음/일정 없음). 전체 통과.
- **커밋**: `추가: 다음 한 행동(저부하) 모드`.
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: 확정 사양대로 구현. 토글 아이콘은 탭하면 전환되는 *목표* 모드를 보여주는 컨벤션(다이얼 모드엔 bolt, 다음한행동 모드엔 donut_large). `AppSettings.homeViewMode` 신규 필드(4곳 패턴). 구현 중 발견: ① `PlannerPage`에 시계 주입 시드가 없어 "다음 블록" 케이스 테스트가 불안정할 뻔함 → 다른 화면들과 같은 `debugNowMinuteOfDay` 패턴 추가. ② 테스트에서 "항상 현재"를 표현하려던 하루 종일(0~24*60) 블록이 `findBlockStatus`의 모듈러 연산상 길이 0인 퇴화 블록으로 취급돼 건너뛰어짐(테스트 쪽 실수) → ±60분 같은 실제 범위로 교정. 실기기 검증 후 사용자가 "무슨 의미가 있냐"고 질문 — 과제마비(task paralysis) 상태에서 하루 전체 정보량 자체가 시작을 막는 벽이 될 때, 그 결정을 앱이 대신 내려 인지부하를 최소화하는 용도로 설명. test 250→257(+7, planner_page_test 5건 + app_settings_test 2건).

### T7 — 오늘의 MIT (우선순위 1~3개)  〔규모 S~M〕 [UI-CONFIRM 완료] ✅(fd957eb)
- **목표**: 핵심을 놓치는 전형 방지.
- **변경**: 블록/항목에 "오늘 중요" 표시(일별 MIT 저장소 또는 segment 플래그) + 홈·Focus·T6 모드에서 강조.
- **파일**: 저장소/모델, `planner_page.dart`·`focus_page.dart` 강조 UI.
- **검증**: MIT 토글/표시 위젯·저장 테스트. 전체 통과.
- **커밋**: `추가: 오늘의 중요 항목(MIT) 강조`.
- **확정 사양 (UI 결정 완료)**: 1) 단위는 **구간(블록) 단위만**(항목 단위 없음). 2) 저장은 **영구 플래그 아니고 그날 하루만 유효한 일별 기록**(AlarmSkip/Completion과 같은 dateKey+segmentId 키 패턴). 3) 개수 제한 **없음**(자유롭게). 4) 표시/선택은 **구간 관리 화면에서만** 별 아이콘 토글(Focus·다이얼·다음한행동은 읽기 전용). 5) 강조는 전부 **노란 별(Icons.star)**로 통일.
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: 확정 사양대로 구현. 신규 `Mit` 모델(`lib/data/models/mit.dart`) + `PlannerRepository`에 `watchMits`/`saveMit`/`removeMit`(Firestore·Fake 둘 다, 90일 윈도우 재사용). `mitBlockIdsOn`(data/today.dart)으로 같은 "오늘만 유효" 패턴 재사용. `DialPainter`에 `mitSegmentIds` 파라미터(아치의 1/4 지점에 별 배지 — 완료 체크마크가 쓰는 중간 지점과 겹치지 않게). 구간 관리는 토글 가능한 별 아이콘, Focus/다음한행동은 읽기 전용 별 표시. test 257→270(+13).

### T8 — 기분·에너지 체크인  〔규모 L〕 [UI-CONFIRM 완료] ✅
- **목표**: 자기인식.
- **변경**: 하루 한 번 기분(이모지 5단계)·에너지(번개 5단계, 별점식)·자유 메모 체크인. 전용 "체크인" 화면(홈 AppBar 진입 아이콘) — 화면 자체는 "최근 기록"만 표시(오늘 포함, 최신순), 좌하단 메모 FAB·우하단 "기분 추가/수정" FAB가 다이얼로그를 열어 입력/수정. 스와이프로 기록 삭제(확인 다이얼로그). 설정에 "체크인 알림" 토글+시간(기본 21:00, 시간 선택은 segment_form_page와 동일한 CupertinoDatePicker 휠) — 알림 탭 시 체크인 화면+다이얼로그 자동 오픈, 무음모드에서도 네이티브 Vibrator로 진동.
- **파일**: 신규 `Checkin` 모델 + `PlannerRepository`에 `watchCheckins`/`saveCheckin`/`removeCheckin`(Firestore 90일 윈도우 + Fake), `AppSettings`에 `checkinAlarmEnabled`/`checkinAlarmMinuteOfDay`, `lib/features/checkin/`(`checkin_controller.dart`·`checkin_page.dart`), `notification_service.dart`(`scheduleCheckinAlarm`/`cancelCheckinAlarm`/`pendingCheckinAlert`), `app.dart`(`_CheckinAlertLauncher`), `settings_page.dart`(토글+시간 휠), `planner_page.dart`(AppBar 진입 아이콘).
- **검증**: 모델 round-trip, controller/page/알림 핸들러/설정 위젯테스트. 전체 통과.
- **커밋**: `추가: 기분·에너지 체크인 (T8)`.
- **확정 사양 (사용자 검토 완료)**: 1) **약 복용 추적 생략**(마이크로스텝으로 충분, 의료용 데이터 제공 목적 없음). 2) 하루 한 번, 이모지 5단계+자유 텍스트. 3) 화면은 전용 "체크인" + 홈 AppBar 아이콘(옵션 A). 4) **내보내기(백업) 기능 없음**. 5) (후속 요청) 설정의 일일 알림 토글+시간 지정, 탭 시 다이얼로그 자동 오픈.
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: 확정 사양대로 구현 후 실기기 피드백 루프 다수 반영 — ① 저장 시 스낵바 대신 화면 종료(다른 저장 액션과 동일 관례)로 변경, ② 화면 구조를 "오늘 입력 폼+최근 기록 분리"에서 "최근 기록 리스트에 오늘도 포함, FAB+다이얼로그로 입력/수정 통합"으로 재설계(사용자 제안), ③ 일일 알림 기능 추가(설정 토글+CupertinoDatePicker 휠, 무음모드 네이티브 진동, 탭 시 자동 다이얼로그), ④ 스와이프 삭제 추가, ⑤ FAB 텍스트 라벨 제거(아이콘만, Semantics로 접근성 유지), ⑥ 에너지 아이콘/메모 입력란/빈 상태 문구 시인성 개선(대비색·배경·중앙정렬). test 270→292(+22).

### T9 — 수면 와인드다운  〔규모 M〕 [UI-CONFIRM 완료] ✅
- **목표**: 수면 블록을 단순 알람이 아닌 와인드다운 루틴으로.
- **확정 사양 (UI 결정 완료)**: 수면 블록 Focus 진입 시 **① 화면 디밍(어둡게) ② 호흡 가이드 애니메이션(들숨/날숨 확장·수축) ③ "이제 폰 내려놓아요" 노스크린 넛지**. `reduce-motion`이면 호흡 애니메이션 대신 정적 안내. 어떤 블록이 '수면'인지 식별 기준 필요 — 1차는 iconKey가 수면 아이콘이거나 이름에 '수면' 포함 등 단순 규칙(구현 시 명확히 고정, 테스트로 박제).
- **파일**: 신규 `lib/features/focus/sleep_wind_down.dart`(`isSleepBlock` 식별 함수 + `SleepWindDown` 위젯), `focus_page.dart`(체크리스트/휴식 분기보다 먼저 체크).
- **검증**: 위젯테스트. 전체 통과.
- **커밋**: `추가: 수면 와인드다운`.
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: 확정 사양대로 구현. 식별 규칙은 `iconKey == 'bedtime' || name.contains('수면')`(기존 "수면" 템플릿과 정확히 일치) — 체크리스트가 있어도 무조건 와인드다운 화면이 우선(체크리스트/타이머가 "폰 내려놓기" 취지와 상충하므로). 화면은 거의 검은 배경 + `AnimationController.repeat(reverse: true)`(4초 들숨/4초 날숨, easeInOut 스케일)로 커지고 작아지는 원 + "들이쉬세요"/"내쉬세요" 교대 텍스트 + "이제 폰 내려놓아요" 넛지. `reduceMotion`이면 고정 크기 원 + "천천히 숨을 쉬어보세요" 정적 문구로 대체. 위젯테스트는 무한 반복 애니메이션 때문에 `pumpAndSettle` 대신 고정 횟수 `pump`로 검증. test 292→303(+11).

### T10 — 접근성·감각  〔규모 S~M〕 ✅(알림 채널만; 다이얼 색각이상 보조는 보류)
- **목표**: 색각이상 대비 + 알림 정비.
- **변경**: ~~다이얼 호 구분에 패턴/라벨 보조(색 단독 의존 제거)~~(사용자 지시로 이번엔 보류), 알림 채널 점검 → **설정에 채널별 시스템 설정 바로가기 추가**(사용자 확정).
- **파일**: `notification_service.dart`(채널 id 공개 + `openChannelSettings`), `MainActivity.kt`(`Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS` 인텐트), `settings_page.dart`(알림 채널 섹션 4행).
- **검증**: 위젯테스트(행 표시·탭 시 올바른 채널 id 호출). 전체 통과.
- **커밋**: `개선: 알림 채널별 시스템 설정 바로가기 (T10)`.
- **실행 결과 (2026-06-29, Sonnet 4.6 구현)**: UI 형태가 미확정이라 사용자에게 두 항목 모두 선택지 제시 → ① 다이얼 색각이상 보조는 보류, ② 알림 채널 정비는 "설정에 채널별 시스템 설정 바로가기"로 확정. 구간 알람(소리·진동 조합에 따라 동적 채널 id)·구간 전환 예고·집중 타이머·체크인 알림, 4개 채널 각각의 행을 탭하면 `Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS` 인텐트로 안드로이드 시스템의 해당 채널 설정으로 이동. 다이얼 색각이상 보조는 별도 보류 항목으로 남김. test 303→305(+2).

### T11 — 보류 항목 연계 (i18n·도움말·구글로그인·디자인 토큰)  〔규모 L〕 [REVIEW]
- **목표**: 기존 보류 과제를 신규 작업과 충돌 없이 통합.
- **변경**: 영어 i18n 도입 + 휴식 문구 영어 격언 분기(`rest_quotes`를 로케일별 리스트로), 도움말 페이지, 구글 로그인 업그레이드(연결-not-로그인 설계), 디자인 토큰 리스타일.
- **검증**: 로케일 전환 테스트, 기존 테스트 유지.
- **커밋**: 항목별 분리. **[REVIEW]**(범위가 커서 사용자와 우선순위 합의 후).

---

## 4. 진행 추적
- 각 TASK 완료 시 이 파일의 해당 항목 제목 끝에 `✅(커밋해시)`를 덧붙여 진행 상태를 남긴다.
- TASK 사이에 사용자 피드백으로 설계가 바뀌면, 바뀐 결정을 해당 TASK "변경" 항목에 갱신해 다음 실행자가 같은 맥락을 갖게 한다.

## 5. 검증 지표 (배포 후 효과 측정 — 참고)
- 빈 상태 이탈률 ↓(첫 블록 생성 전환율 ↑) — T3
- 알람 "해제만" 비율 ↓, 스누즈/예고 사용률 — T2
- 7일+ 비활성 후 복귀율 ↑ — T1
- 부분 달성(50–99%)일의 다음날 재방문율 — T1
