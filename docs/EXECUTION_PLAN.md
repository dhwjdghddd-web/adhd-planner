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
> **UI 형태는 이미 확정 완료** — T2·T3·T5·T6·T9의 "확정 사양" 블록을 그대로 따르면 되고, 화면 형태를 다시 묻지 말 것(세부 픽셀/배치 미세조정만 재량). 남은 사용자 확인 지점은 **[REVIEW]**(T2 실기기 검증, T8 데이터 스키마, T11 범위)뿐.

### T1 — 스트릭 안전장치 + 부분 보상 + 자기연민 카피  〔규모 M〕
- **목표**: 나쁜 날에도 앱이 안전한 곳. 스트릭 절벽 완화, 부분 성공 보상.
- **변경**:
  1. **유예/회복**: `streakDateKeys` 계산에 "유예일" 도입. 설계안 A(권장): 최근 스트릭이 *어제 1일 비었어도* 끊지 않는 grace 1일 허용. 단 **과거 달성일 레코드를 덮어쓰지 않는다**(별도 파생 계산으로만). `daily_achievement.dart`에 grace 로직 추가하고 순수 함수 단위테스트로 고정.
  2. **부분 보상**: `_CompletionCelebrator`(app.dart)를 확장 — 100%는 현행 컨페티, **50% 최초 도달 시** 가벼운 1회 피드백(스낵바/소형 배지). 둘 다 `AppSettings.lastCelebratedDate`처럼 일자 키로 1일 1회 영속(두 단계 각각의 마커 필요 → 설정 필드 2개 또는 "단계" 저장).
  3. **마일스톤 가변화**: 3·7·30일에 문구/연출 분기(`completion_celebration` 또는 streak 배지 탭 시 표시).
  4. **카피**: "실패/미달성" 제거, 최고 기록 병기, 0 추락은 "다시 시작" 톤.
- **파일**: `daily_achievement.dart`, `app_settings.dart`(마커 필드), `app.dart`(`_CompletionCelebrator`), `completion_celebration.dart`, `streak_badge.dart`.
- **검증**: `daily_achievement` 순수 단위테스트(유예 경계: 어제 비고 오늘 달성→유지, 이틀 비면 끊김). `_CompletionCelebrator` 위젯테스트(50%/100% 1회 발화·재발화 안 함, 애니메이션이 pumpAndSettle 막지 않도록 억제 경로). 전체 테스트 통과.
- **커밋**: `추가: 스트릭 유예일·부분 달성 보상·자기연민 카피`.
- 비고: [[영구 저장 규칙]] 위반 금지 — 유예/회복은 파생 계산이지 저장 변경이 아니다.

### T2 — 알람 반응 옵션 복원 (스누즈 · 오늘 건너뛰기 · 전환 예고)  〔규모 L〕 [UI-CONFIRM 완료]
- **목표**: 알람을 무시 대신 "미루기/오늘 패스/미리 알림"으로 응답 가능하게.
- **확정 사양 (UI 결정 완료 — 추가 질문 불필요)**:
  - AlarmScreen 레이아웃: 기존 **슬라이드 해제(=시작)** 유지, 그 **아래에 텍스트버튼 2개 좌우** — 왼쪽 `10분 뒤 다시`, 오른쪽 `오늘은 건너뛰기`. (하단 콘텐츠가 슬라이드 트랙을 가리지 않게 간격 확보.)
  - **스누즈 기본 10분**, `AppSettings`에 `snoozeMinutes`(허용값 5/10/15, 기본 10) + 설정 화면 선택 UI.
  - **전환 예고: 켬(기본)**, 시작 **10분 전**, **풀스크린 아님(조용한 헤드업 알림, 별도 저강도 채널)**. 전역 기본 on + **블록별 끄기** 가능(`Segment.leadWarning` bool, 기본 true). 예고 분(`leadMinutes`)은 `AppSettings` 전역 기본 10.
- **변경**:
  1. **스누즈**: AlarmScreen 버튼 → 현재 알람 무음 + **+N분 일회성** 알람 예약. `notification_service`에 일회성 예약 경로 추가(반복 아님, `matchDateTimeComponents` 없이 1회 `zonedSchedule` + 네이티브 진동 1회). 알람 화면 닫기.
  2. **오늘 건너뛰기**: 오늘자 해당 블록 알람 억제. 저장은 `microStepProgress` 패턴을 따른 per-(block,day) **skip 레코드**. `_ForegroundAlarmWatcher`가 skip된 블록은 재팝 금지. (이미 발화한 예약 알림은 무음 처리.)
  3. **전환 예고**: 블록 시작 `L분 전` 저강도 헤드업 알림. `buildSchedule`에 예고 spec 추가(별도 slot, fullScreenIntent=false, 별도 채널), `notificationIdFor(segmentId, slot=1)`. 전역 기본 L분 + 블록별 on/off(Segment 필드 또는 설정).
- **파일**: `alarm_screen.dart`, `notification_service.dart`, `notification_schedule.dart`, `app.dart`(워처 skip 반영), `app_settings.dart`(스누즈 분·예고 분), 필요 시 `segment.dart`(예고 on/off)·네이티브(일회성 진동).
- **검증**: `notification_schedule` 단위테스트(예고 spec 생성/슬롯 id 비충돌). skip 저장/조회 테스트. AlarmScreen 위젯테스트(스누즈/건너뛰기 버튼 동작·화면 닫힘, 기존 슬라이드 해제 테스트 유지). 빌드(네이티브 변경 시 필수).
- **커밋**: 의미 단위로 — 예) `추가: 알람 스누즈/오늘 건너뛰기`, `추가: 구간 전환 예고 알림`.
- 비고: 과거에 의도적으로 제거했던 기능의 재도입이다. 관련 설계 메모를 갱신했다는 점을 커밋 본문에 남길 것. **[REVIEW]** — 네이티브·알림 동작은 실기기 확인이 필요하니 설치 후 사용자 검증 요청.

### T3 — 빈 상태·계획 보조 (스타터 칩 + 브레인덤프→자동배치)  〔규모 M~L〕 [UI-CONFIRM 완료]
- **목표**: 빈 다이얼 콜드스타트 제거.
- **확정 사양 (UI 결정 완료)**:
  1. **빈 상태 홈**: `segments`가 비면 다이얼 대신 안내문 + **개별 스타터 칩**을 Wrap으로. 칩 1탭 = 그 블록 1개를 기본 시각·아이콘으로 추가(다이얼이 즉시 채워짐). 칩 세트(7종, 합리적 기본 시각·아이콘):
     - 기상 07:00–07:30, 약 07:30–07:40, 아침 07:40–08:10, 집중 09:00–11:00, 점심 12:00–13:00, 휴식 15:00–15:30, 수면 23:00–익일(end는 1439 등 합리값). 아이콘은 `segment_icons.dart`의 기존 key 사용.
     - 데이터는 `lib/features/segments/segment_templates.dart`(신규)에 `const` 리스트로. 칩 추가는 `segments_controller.upsert`(오프라인 unawaited 패턴) 사용.
  2. **브레인덤프 → 블록 (자동 시각 추천 포함)**: 떠오르는 일들을 나열(텍스트, 음성 캡처 재사용) → **"시각 자동 배치"** 버튼으로 각 항목에 시각 제안 → 사용자가 조정 가능 → 일괄 생성.
     - 자동배치는 **순수·결정적 함수** `suggestSlots(items, existingSegments, anchorMinute)`로 구현(단위테스트 필수). 휴리스틱(1차): anchor = max(현재시각을 30분 올림, 마지막 기존 블록 end). 각 항목 기본 30분, 기존 블록과 겹치면 다음 빈 구간으로 밀어 순차 배치. 자정 넘기면 중단/경고.
     - 생성 전 미리보기에서 시각/길이 수정 가능. 일괄 생성은 `segments_controller`에 bulk upsert 추가.
- **파일**: 홈 빈 상태 위젯(`planner_page.dart` 또는 신규), 템플릿 데이터(신규 `lib/features/segments/segment_templates.dart`), `segments_controller`(일괄 upsert), 브레인덤프 화면(신규).
- **검증**: 템플릿 추가 후 `segments`에 반영되는 위젯/컨트롤러 테스트. 빈 상태 렌더 테스트. 전체 통과.
- **커밋**: `추가: 빈 상태 스타터 템플릿`, (후속) `추가: 브레인덤프로 블록 만들기`.

### T4 — 메모 '닫는 고리' (블록 승격 + 재부상)  〔규모 M〕
- **목표**: 메모 무덤 방지 — 캡처를 행동(블록/항목)으로.
- **변경**:
  1. 메모 항목에 **"블록/할일로 승격"**: `SegmentFormPage`를 메모 텍스트로 프리필해 열거나, 기존 블록의 microStep으로 추가하는 선택 시트.
  2. **재부상**: 오래된 미검토 메모를 가끔 상단에 넛지("이 메모, 아직이에요").
  3. (선택) "오늘 처리할 메모 N개" 소형 표면.
- **파일**: `memo_inbox_page.dart`, `memos_controller.dart`(또는 segments_controller 연계), `quick_add_sheet.dart`(재사용).
- **검증**: 승격 시 블록/마이크로스텝 생성 컨트롤러 테스트, 메모 인박스 위젯테스트(기존 탭=수정·체크·스와이프 유지). 전체 통과.
- **커밋**: `추가: 메모를 블록/할일로 승격, 오래된 메모 재부상`.

### T5 — Focus를 진짜 집중 도구로 (블록 내 잔여시간 + 짧은 타이머 + 2분 룰)  〔규모 M~L〕 [UI-CONFIRM 완료]
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

### T6 — 다음 한 행동(Next Action) 저부하 모드  〔규모 M〕 [UI-CONFIRM 완료]
- **목표**: 과제마비형 구제 — 하루 전체 대신 "지금 딱 하나".
- **확정 사양 (UI 결정 완료)**:
  - **진입**: **홈 상단의 토글 버튼**으로 다이얼 ↔ 다음한행동 즉시 전환(별도 라우트 push 아님, 같은 홈에서 뷰 스왑). 마지막 선택 상태는 기억(설정/로컬).
  - **화면 구성**: 다이얼·배지·카운트다운 숨기고 **현재(없으면 다음) 블록 1개 + 큰 '시작' 버튼**만. `findBlockStatus` 재사용. 시작 → `FocusPage.forBlock`. "지금/다음 없음"이면 차분한 빈 메시지.
  - FAB 규칙 동일(하단 메모 FAB 위 유지).
- **파일**: 신규 미니멀 뷰, `app_settings.dart`(모드 플래그), 라우팅(`_RootRouter`/홈 토글).
- **검증**: 모드별 렌더 위젯테스트(현재 있음/없음/일정 없음). 전체 통과.
- **커밋**: `추가: 다음 한 행동(저부하) 모드`.

### T7 — 오늘의 MIT (우선순위 1~3개)  〔규모 S~M〕
- **목표**: 핵심을 놓치는 전형 방지.
- **변경**: 블록/항목에 "오늘 중요" 표시(일별 MIT 저장소 또는 segment 플래그) + 홈·Focus·T6 모드에서 강조.
- **파일**: 저장소/모델, `planner_page.dart`·`focus_page.dart` 강조 UI.
- **검증**: MIT 토글/표시 위젯·저장 테스트. 전체 통과.
- **커밋**: `추가: 오늘의 중요 항목(MIT) 강조`.

### T8 — 약·기분·에너지 체크인  〔규모 L〕 [REVIEW]
- **목표**: 자기인식 + 진료용 데이터.
- **변경**: 약 복용 추적(복용/누락 1탭), 간단 기분·에너지 체크인, 주간 히스토리, (선택) 내보내기.
- **파일**: 신규 데이터 모델 3종(repository 인터페이스 + Firestore 구현 + Fake), 체크인 표면, 히스토리 뷰.
- **검증**: 모델 round-trip(toMap/fromMap) 단위테스트, 저장/조회 테스트, 위젯테스트. 전체 통과.
- **커밋**: 의미 단위 분리. **[REVIEW]**(데이터 스키마는 사용자 확인 후).

### T9 — 수면 와인드다운  〔규모 M〕 [UI-CONFIRM 완료]
- **목표**: 수면 블록을 단순 알람이 아닌 와인드다운 루틴으로.
- **확정 사양 (UI 결정 완료)**: 수면 블록 Focus 진입 시 **① 화면 디밍(어둡게) ② 호흡 가이드 애니메이션(들숨/날숨 확장·수축) ③ "이제 폰 내려놓아요" 노스크린 넛지**. `reduce-motion`이면 호흡 애니메이션 대신 정적 안내. 어떤 블록이 '수면'인지 식별 기준 필요 — 1차는 iconKey가 수면 아이콘이거나 이름에 '수면' 포함 등 단순 규칙(구현 시 명확히 고정, 테스트로 박제).
- **파일**: `focus_page.dart` 또는 전용 화면.
- **검증**: 위젯테스트. 전체 통과.
- **커밋**: `추가: 수면 와인드다운`.

### T10 — 접근성·감각  〔규모 S~M〕
- **목표**: 색각이상 대비 + 알림 정비.
- **변경**: 다이얼 호 구분에 패턴/라벨 보조(색 단독 의존 제거), 알림 채널 점검.
- **파일**: `dial_painter.dart`, 알림 설정.
- **검증**: 렌더 테스트(보조 표식 존재). 전체 통과.
- **커밋**: `개선: 색각이상 대비·알림 채널 정비`.

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
