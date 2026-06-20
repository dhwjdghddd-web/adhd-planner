# 작업 인수인계 문서

작성일: 2026-06-19 (Claude Sonnet 4.6 세션 종료 시점)
대상: 이 작업을 이어받는 다른 AI 에이전트 / 미래의 나

이 문서는 `BUILD_INSTRUCTIONS.md`에 명시된 STEP 0~12 작업이 전부 완료된 이후,
실제 기기(삼성 폴더블 SM-F766N)에서 반복 테스트하며 발견된 버그 수정과
설계 변경 작업의 기록입니다. `BUILD_INSTRUCTIONS.md`는 최초 설계 스펙이고,
이 문서는 그 이후 "실사용 피드백을 반영해 무엇이, 왜 바뀌었는지"를 다룹니다.
두 문서를 같이 봐야 현재 코드 상태가 이해됩니다.

---

## 0. 이 문서 이후의 변경 (필독 — 아래 §0-A가 현행 최신 상태)

**주의:** 이 HANDOFF.md의 §1~§6 본문은 커밋 `0b7cb05` 시점(2026-06-19)에
작성됐고, **그 이후 3개 커밋에서 더 많은 변경이 있었다.** §1~§6을 읽되,
그것들이 묘사하는 "미해결 버그(원래 §0)"와 일부 동작은 **이미 바뀌었으니**
반드시 이 §0-A를 먼저 읽고 최신 상태를 기준으로 판단할 것. (원래 §0에 있던
"완료해도 지금 화면에 같은 루틴이 남는 버그"는 **해결됐다** — 아래 참고.)

### §0-A. HANDOFF 이후 커밋별 변경 요약

**커밋 `ee7ae53` — 완료 후 지금 화면/다이얼 상태 버그 수정 (원래 §0 버그 해결)**
- Google의 Antigravity 에이전트가 이 HANDOFF.md를 읽고 원래 §0의 버그를
  수정했다. 단, 제안된 "완료 루틴 건너뛰기" 방식 대신 **더 근본적으로**
  재작성: `findRoutineStatus`는 이제 `completedRoutineIds`(오늘 완료된 id
  집합)를 인자로 받아, **가장 최근에 시작된 루틴 하나만** current 후보로 보고
  그게 완료됐으면 즉시 "다음" 탐색으로 직행한다(과거 루틴으로 역행하지 않음).
- 추가 버그도 같이 수정: 완료 시각이 시작 시각과 정확히 일치(delta=0)할 때
  "0분 후 시작"으로 재표시되던 문제 → next 탐색에서도 완료 루틴 제외.
- UI: 루틴/구간 수정 화면의 삭제 버튼을 AppBar에서 우측 하단 FAB으로 이동
  (좌측 메모 FAB과 대칭).
- → 즉 **원래 §0은 이미 끝난 일.** `findRoutineStatus`의 시그니처는 지금
  `findRoutineStatus(routines, nowMinute, isoWeekday, {Set<String> completedRoutineIds})`.

**커밋 `489a832` — '넘기기'(오늘 건너뛰기) 기능 추가**
- 완료/미루기와 별개인 세 번째 동작: 오늘만 그 루틴을 건너뛴다. 오늘 지금/
  다음 어디에도 안 뜨고, 오늘 남은 알람도 취소되며, 다음 주 같은 요일엔 정상
  복귀.
- 신규: `RoutineSkip` 모델(`lib/data/models/routine_skip.dart`,
  dateKey+routineId), `PlannerRepository`/Firestore/Hive/Fake 전부에
  `watchRoutineSkips`/`saveRoutineSkip` 추가, `routineSkipsProvider`.
- `routine_status.dart`에 `excludeTodaysSkips(routines, skips, {now})` 추가 —
  `findRoutineStatus` 호출 **전에** 건너뛴 루틴을 걸러낸다(지금/다음 양쪽 제외).
- `NotificationService.skipToday(routineId)`: 건너뛰기 기록 저장 + 오늘 알람
  취소. `rescheduleAll`은 오늘 건너뛴 루틴을 다음 주로 재예약
  (`_nextInstanceRespectingSkip`).
- Focus 화면(지금/다음/곧시작) + 알람 다이얼로그(전환예고/본알람)에 "넘기기"
  버튼. 다이얼 중앙 요약도 같은 필터 적용.

**커밋 `2639a3b` — 알람 코드 전반 점검 후 버그/일관성 수정 5건**
- **(1) 무한 진동 위험 제거**: `VibrationAlarmReceiver.kt`가 무한 반복 파형 +
  Handler.postDelayed로 정지하던 구조 → **durationMs 길이의 유한 파형**으로
  변경. 잠금/종료 상태에서 프로세스가 죽어도 진동이 스스로 끝난다(재부팅 전까지
  무한 진동하던 최악 시나리오 차단).
- **(2) 포그라운드 와처 넘기기 누락**: `_ForegroundAlarmWatcher`가
  `excludeTodaysSkips`를 적용하지 않아, 넘긴 루틴인데도 그 시각에 앱을 보고
  있으면 다이얼로그가 또 뜨던 버그 수정.
- **(3,4) 알림 액션 버튼(미루기/완료) 제거**: 액션 버튼 경로에서 진동이 안
  꺼지던 문제 + '완료' 액션이 재설계(확인=완료 아님)와 모순되던 문제를 한 번에
  해결. 모든 알람 조작은 이제 **AlarmAlertDialog 한 곳**으로 통일. 죽은
  백그라운드 핸들러(`_handlePostpone`/`_handleComplete`/`_resolveUid`)와 관련
  import 제거.
- **(5) skipToday 전환예고 슬롯 가드 결함**: 전환예고는 본알람보다 일찍
  발화하므로, 그 사이 시각에 넘기기하면 다음 주 전환예고를 잘못 취소하던 문제를
  자기 시각 기준 판정으로 수정.
- **보류(의도적): `notificationIdFor`의 hashCode 충돌** — 공식을 바꾸면
  구버전 ID로 등록된 네이티브 진동 알람이 고아로 남아 매주 알림 없이 진동만
  울리는 더 심한 버그가 생겨, 안전한 마이그레이션이 가능할 때까지 둠. 확률적
  저위험.

### §0-B. 다음 작업으로 잡힌 것 — 구글 계정 멀티유저 연동

별도 계획서 **`GOOGLE_AUTH_PLAN.md`** 참조(이 HANDOFF와 같은 디렉터리). 멀티유저로
가면서 §3의 "고정 UID hack 제거 + firestore.rules 복원"을 그 작업에서 함께
처리한다. 즉 **§3의 보안 약화 항목은 그 계획서가 해소할 예정**이다.

---

## 1. 표준 작업 절차 (반드시 지킬 것)

이 프로젝트는 Windows에서 `puro`로 관리되는 Flutter SDK를 쓴다.

```
export PATH="$USERPROFILE/.puro/bin:$PATH"
puro flutter analyze        # 0 errors 확인
puro flutter test           # 전체 통과 확인 (현재 163개 전후)
puro flutter build apk --debug
```

빌드 산출물: `build\app\outputs\flutter-apk\app-debug.apk`

코드 수정 → analyze → test → build → adb install → **사용자에게 폰에서
직접 확인을 요청**하는 흐름을 매번 반복했다. 사용자는 빌드를 대신 맡기지
않고 항상 폰으로 직접 검증하길 원한다. "빌드했다"와 "사용자가 폰에서
확인했다"는 별개이니 후자 없이 작업 완료로 간주하지 말 것.

**폰 연결**: 무선 adb를 쓰는데 IP:포트가 세션마다(때로는 세션 중에도)
바뀐다. 매번 사용자가 새 `ip:port`를 알려주면 그걸로 `adb connect` 해야
한다. USB 시리얼 `R3CY60N9F4Z`가 유선 폴백으로 항상 떠 있다
(`adb devices`에 `adb-R3CY60N9F4Z-EVOnWr (2)._adb-tls-connect._tcp`로 보임).
기기는 삼성 SM-F766N 폴더블 — `adb shell screencap`을 디스플레이 id
없이 쓰면 "여러 디스플레이가 있다"는 경고가 뜨지만 첫 디스플레이로
캡처는 된다(이번 세션엔 `-d` 없이도 동작 확인). 화면을 직접 봐야 할 때는
`adb shell screencap -p /sdcard/x.png` → `MSYS_NO_PATHCONV=1 adb pull
/sdcard/x.png <로컬경로>`로 가져와서 Read 도구로 본다(Bash 경로 변환 때문에
`MSYS_NO_PATHCONV=1` 필수).

---

## 2. 이번 세션에서 한 작업 (시간순 상세)

이전 세션에서 알람음/진동 패턴 선택, 진동 무음 버그(채널 FLAG_MUTE_HAPTIC),
세그먼트 자동 귀속, 다이얼 라벨, 24시간 휠 피커, 일일 체크리스트 배지,
전체화면 알람 페이지를 작은 AlertDialog로 교체, fullScreenIntent, 9시간
타임존 버그(백그라운드 isolate에서 `tz.setLocalLocation` 누락) 수정,
"미루기" 기능(누적 오프셋) 신설까지 끝내고 한 번 커밋·푸시했다(커밋
`aeaab71`). 이번 세션은 그 이후부터다.

### 2-1. 메모 FAB가 콘텐츠를 가리는 문제 — 두 번에 걸쳐 고침

- **1차 시도(틀렸음)**: 각 화면의 `ListView`에 `padding: EdgeInsets.only(bottom: 88)`을
  줘서 FAB 영역을 피하려 했다. 그런데 이건 콘텐츠 *끝*에 여백을 주는
  것이라 **스크롤을 끝까지 해야만** 적용된 것처럼 보인다. 스크롤 전에는
  여전히 텍스트가 FAB 밑까지 그려진다. 사용자가 정확히 이 점을 지적함.
- **2차 시도(맞음, 현재 적용된 방식)**: `ListView`의 padding이 아니라
  **`body` 자체를 `Padding`으로 감싸서 화면의 보이는 영역(viewport) 자체를
  줄였다.** 이러면 스크롤 여부와 무관하게 항상 적용된다. 적용 대상:
  `settings_page.dart`, `routine_form_page.dart`, `segment_form_page.dart`,
  `routine_editor_page.dart`, `segment_editor_page.dart`, `memo_inbox_page.dart`.
- 그 다음 사용자가 "그래도 조금 가려진다"고 다시 지적 — 폴더블 기기의
  하단 시스템 제스처바 인셋을 빠뜻렸던 것. `lib/features/memos/quick_add_button.dart`에
  `fabAvoidingBottomInset(BuildContext)` 헬퍼를 추가해서
  `88 + MediaQuery.of(context).padding.bottom`을 반환하게 하고, 위 6개
  화면 전부 고정값 `88` 대신 이 함수를 쓰도록 교체했다. 이후 확인 완료.

### 2-2. 알람 다이얼로그 동작 재설계

- **탭해도 안 꺼지는 문제**: `AndroidNotificationDetails`의 `autoCancel`
  기본값이 `true`라서, 헤드업 알림을 탭해서 다이얼로그를 여는 순간 알림이
  자동으로 사라지면서(=소리/진동도 같이 멎는 것처럼 보이지만 실제로는
  알림만 사라짐) 사용자가 "확인을 눌러도 진동이 안 멈춘다"고 느꼈다.
  본알람/전환예고 채널 둘 다 `autoCancel: false`로 바꿔서, 다이얼로그의
  확인/미루기를 눌러야만(`cancelNotification` 명시적 호출) 실제로 멈추게
  했다.
- **전환예고도 다이얼로그**: 원래 본알람만 탭하면 다이얼로그가 떴는데,
  전환예고도 똑같이 확인/미루기 다이얼로그가 뜨도록 통일
  (`AlarmAlertDialog`에 `isTransition` 플래그 추가, 본문 텍스트만 다르게).
- **포그라운드 자동 표시**: 앱이 켜져 있는 동안은 헤드업을 탭하지
  않아도, 알람 시각이 되면 자동으로 다이얼로그가 뜨게 했다
  (`lib/app.dart`의 `_ForegroundAlarmWatcher` — 1초 주기 타이머로 분 단위
  변화 감지). 사용자가 "다른 앱을 보고 있어도" 뜨길 원했지만, 그건
  SYSTEM_ALERT_WINDOW 오버레이 권한이 필요한 더 큰 작업이라 **합의된
  대로 1단계(자기 앱이 포그라운드일 때만)만 구현**하고 2단계는 보류
  상태다.
- **자동 다이얼로그가 잘못된 알림 ID를 취소하려던 버그**: 미루기를 누르면
  본알람/전환예고가 슬롯 2/3번(일회성 재스케줄)으로 다시 등록되는데,
  `_ForegroundAlarmWatcher`는 항상 슬롯 0/1(영구 반복) ID로 취소를
  시도하고 있었다. 그래서 미루기 후 확인을 눌러도 실제 알림이 안 꺼지고
  진동이 계속됐다. `lib/app.dart`의 `_check()`에서 오늘 미루기 기록이
  있으면 슬롯 2/3 ID를 쓰도록 분기 추가해서 수정함.
- **확인 버튼 동작 재설계**: 처음엔 본알람 "확인" = 완료 기록 + 다이얼로그
  닫기였는데, 사용자가 "Focus 화면의 완료(마이크로스텝 전체 체크)와
  혼동된다"고 지적. 최종 결론: **본알람 확인은 완료 기록을 남기지 않고,
  알람만 끄고 Focus 화면으로 자동 이동**(`Navigator.pushReplacement`로 —
  `pop` 후 별도 `push`를 했더니 다이얼로그가 완전히 안 닫히고 스택에
  남아있던 버그가 있어서 `pushReplacement`로 교체). 전환예고 확인은
  그냥 알람만 끄고 닫기, Focus로 이동하지 않음(사용자가 "사전알람에서
  확인 누르면 지금으로 이동했으면" 요청했다가 곧바로 "아니야 취소할게"로
  되돌림 — Focus 화면 자체가 leadWarningMin 창 안에서는 이미 마이크로스텝
  미리 체크 가능한 화면을 보여주므로 굳이 자동 이동까지는 필요 없다는
  결론).
- **미루기 피드백 누락**: 미루기를 눌러도 아무 피드백이 없다는 지적 →
  `AlarmAlertDialog._postpone`에서 "N분 후 다시 알려드려요" SnackBar를
  추가. 이 SnackBar도 처음엔 메모 FAB에 가려졌다가, `margin`에
  `fabAvoidingBottomInset` 적용해서 고침.
- **Focus 화면 미루기 버튼 제거**: 사용자가 "지금 화면에서 미루기가
  없어도 될 것 같다"고 해서 `FocusPage`의 미루기 버튼과 관련 코드
  (`_postpone`, `_tryPostpone`) 전부 삭제. 알람 다이얼로그 쪽 미루기는
  그대로 유지.

### 2-3. 무음 모드에서 진동이 안 울리는 문제 — 진짜 원인을 찾기까지

1. 처음엔 `AndroidScheduleMode.exactAllowWhileIdle`을 `alarmClock`
   (`AlarmManager.setAlarmClock`)으로 바꿔서 "진짜 알람시계처럼" 등록하면
   무음 모드를 우회할 거라 추정하고 적용. 효과 없었음(사용자가 직접
   재현 확인).
2. 마이크로스텝 연속입력 버그도 같은 시점에 "안 고쳐졌다"는 보고를
   받고, 둘 다 진지하게 원인을 파악하라는 요청을 받음.
3. **결정적 실험**: 사용자 폰이 마침 무음 모드였길래, 설정 화면의
   "진동 패턴 미리듣기" 버튼(네이티브에서 `Vibrator.vibrate()`를 직접
   호출하는 기존 기능)을 `adb shell input tap`으로 직접 눌러봤다. →
   **무음 모드에서도 진동이 느껴졌다.** 즉 OS가 진동 자체를 막는 게
   아니라, **Notification 채널을 통한 진동만** 삼성 OneUI의 "무음" 정책에
   걸려 억제된다는 게 확정됨. `setAlarmClock`은 "정확한 시각에 깨어나는
   것"만 보장할 뿐, 그 후 Notification이 진동하는 건 별개 정책이라
   전혀 도움이 안 됐던 것.
4. **해결**: 알림과는 완전히 별도로, 같은 시각에 울리는 또 하나의
   `AlarmManager` 알람을 등록해서 `BroadcastReceiver`가 `Vibrator.vibrate()`를
   직접 호출하게 했다.
   - 신규 파일 `android/app/src/main/kotlin/com/adhdplanner/adhd_planner/VibrationAlarmReceiver.kt`:
     `schedule()`/`cancel()`/`stopVibration()` static 메서드 제공.
     `repeatIntervalMs > 0`이면 자기 자신을 다음 주(7일 후)로 재등록해서
     매주 반복 알람도 네이티브 쪽에서 자체적으로 유지(Dart가 안 떠 있어도
     계속 동작).
   - `MainActivity.kt`에 `scheduleVibrationAlarm`/`cancelVibrationAlarm`
     MethodChannel 핸들러 추가.
   - `AndroidManifest.xml`에 `<receiver android:name=".VibrationAlarmReceiver" />`
     등록.
   - `lib/services/notification_service.dart`: `rescheduleAll`,
     `postpone`(본알람/전환예고 양쪽), `cancelNotification`에서 알림
     스케줄/취소와 **항상 같이** 진동 알람도 스케줄/취소하도록 연결.
     `cancelRoutineAlarms(Routine)` 추가해서 루틴 삭제 시
     (`routines_controller.dart`의 `delete()`)에도 진동 알람이 고아로
     남지 않게 정리.
   - **버그 하나 발생 후 수정**: 처음 구현에서 `vibrationPattern`을
     `Int64List`(타입 있는 배열) 그대로 MethodChannel에 넘겼는데, 네이티브
     쪽에서 `long[]`로 도착해서 `List<*>`로 캐스팅하다가
     `ClassCastException: long[] cannot be cast to java.lang.Iterable`이
     발생했다. `ensureAlarmChannel`이 이미 같은 패턴을 `.toList()`로
     박싱된 `List<int>`로 보내고 있었으니 그것과 똑같이 고쳐서 해결.
   - 사용자가 무음 모드에서 실제로 재현 테스트해서 **정상 동작 확인함.**
     (확인/미루기 누르면 즉시 멈춤, 방치 시 본알람 1분/전환예고 ~5초
     후 자동 정지도 확인.)
   - **트레이드오프**: `setAlarmClock`을 쓰는 한, 알람이 예약되어 있는
     동안 상태바에 항상 알람시계 아이콘이 뜬다(시계 앱 알람처럼). 사용자
     에게 미리 알렸고 별다른 반대는 없었음.

### 2-4. 마이크로스텝 연속 입력 버그 — 두 번에 걸쳐 고침

- **1차 시도(틀렸음)**: "+" 버튼이 포커스를 가져가서 키보드가 닫히는
  거라 추정하고 `ExcludeFocus`로 감쌌다. 사용자가 "안 고쳐졌다"고 재확인
  요청.
- **logcat으로 진짜 원인 확인**: `adb logcat`에서
  `ImeInsetsSourceProvider: showImePostLayout aborted` → `onHidden`을
  확인. 코드를 다시 보니: 마이크로스텝 입력 `Row`와 그 위의
  `for (var i = 0; i < _microSteps.length; i++) ListTile(...)`들이 **key
  없이** 위치 기반으로 렌더링되고 있었다. 스텝을 추가할 때마다 입력
  `Row`가 리스트에서 한 칸씩 뒤로 밀리면서, Flutter가 그 자리의 기존
  위젯과 타입이 다르다고 판단해 **입력 `Row` 전체(그 안의 TextField
  포함)를 dispose하고 새로 생성** — 이게 IME 연결을 끊어서 키보드가
  닫히는 진짜 원인이었다.
- **2차 수정(맞음)**: 입력 `Row`에 안정적인 `GlobalKey`
  (`_microStepInputKey`)를 부여하고, 각 `ListTile`에도
  `ValueKey('microStep$i-${_microSteps[i]}')`를 부여해서 위치가 아니라
  내용으로 위젯 아이덴티티를 추적하게 했다. `ExcludeFocus`는 그대로
  남겨둠(부가적인 안전장치로는 무해).
- 추가로 사용자가 "+ 누르면 새 입력칸으로 화면이 자동 스크롤됐으면"
  요청 → `_addMicroStep()` 끝에서
  `WidgetsBinding.instance.addPostFrameCallback`으로 `Scrollable.ensureVisible`
  호출, `_microStepInputKey.currentContext`를 대상으로 200ms 애니메이션.
  확인 완료.

### 2-5. 홈 화면 루틴 추가 바로가기

- 사용자가 "루틴 창 들어가서 추가하기 번거롭다"고 해서, 메모 FAB
  반대쪽(우측 하단)에 같은 모양의 FAB을 신설(`planner_page.dart`).
  세그먼트가 하나도 없으면 SnackBar로 먼저 구간을 만들라고 안내(기존
  `RoutineEditorPage`의 동작과 동일하게 맞춤).

### 2-6. 다이얼에 "오늘 완료" 체크 배지

- 사용자가 "마이크로스텝을 다 체크하면 오늘 화면(다이얼)에서 그 루틴을
  완료했다는 표시가 바로 보였으면 좋겠다"고 요청.
- `planner_page.dart`에서 `completionsProvider`를 watch해서 오늘
  날짜(dateKey)로 필터링한 `Set<String> completedRoutineIds`를 계산,
  `_Dial` → `DialPainter`까지 전달.
- `dial_painter.dart`의 `_paintRoutineMarkers`에서 마커를 그릴 때
  `completedRoutineIds.contains(routine.id)`이면 마커 우측 상단에 작은
  초록색 체크 배지(`_paintCompletedBadge`)를 추가로 그림.
  `shouldRepaint`에도 `completedRoutineIds` 변화를 비교하도록 추가.
- 테스트 `planner_page_test.dart`에 완료/미완료 루틴을 구분해서
  `DialPainter.completedRoutineIds`에 올바르게 전달되는지 확인하는
  테스트 추가.

### 2-7. 길이(duration) 설정 완전 제거 — 가장 큰 설계 변경

사용자가 먼저 "길이 설정이 의미 없게 느껴진다. 정해진 시간 안에 체크를
못 하면 그냥 지나가버리고 다시 체크를 못 하는 게 불합리하고 실패감을
준다"는 의문을 제기했고, 코드를 같이 검토한 뒤(아래 표 참고) 제거하는
것에 합의했다.

**제거 전 `durationMin`의 실제 역할**:
1. Focus 화면의 카운트다운 링 진행률 계산
2. `findRoutineStatus`의 "지금" 판정 — `[시작, 시작+길이)` 구간을 벗어나면
   "지금"이 아니게 됨 (← 이게 사용자가 느낀 "실패감"의 근원)

다이얼 화면에서 길이는 어떤 시각적 역할도 하지 않았고(루틴은 점 마커
하나일 뿐), 이 앱의 다른 모든 설계(마이크로스텝, 미루기 무제한 누적,
반복요일)가 "유연하게 다시 시도 가능"을 지향하는 것과도 철학이
안 맞았다. 그래서 **완전히 제거**하기로 결정.

**구체적 변경 내역**:
- `lib/data/models/routine.dart`: `durationMin` 필드, `endMinute` getter,
  `containsMinute()` 메서드 전부 삭제. `copyWith`/`toMap`/`fromMap`도 같이
  정리. 클래스 doc comment에 "왜 길이 필드가 없는지"를 명시해둠(다음에
  또 누가 추가하려 하지 않도록).
- `lib/data/routine_status.dart`의 `findRoutineStatus()` 전면 재작성:
  "오늘 `nowMinute` 이전에 시작된 루틴 중 가장 늦게 시작된 것"을
  current로 채택(만료 없음). 없으면 "아직 시작 안 한 것 중 가장 빠른
  것"을 next로(`remainingMinutes` 계산은 이제 단순 `start - now`, wrap 처리
  안 함 — 아래 "알려진 한계" 참고).
- `lib/features/focus/focus_page.dart`:
  - 카운트다운 링(`FocusCountdownPainter`) 제거, 파일 자체 삭제
    (`lib/features/focus/focus_countdown_painter.dart`).
  - "지금" 상태 UI를 큰 알람 아이콘 + 제목 + 스트릭 배지로 단순화.
  - "다음 루틴까지 N분" 텍스트를 절대 시각(`TimeGeometry.formatMinute`)
    표시로 변경 — 사용자가 "카운트다운 숫자는 시간 감각에 안 맞고
    자극이 안 된다, 실제 트리거는 알람 소리/진동이지 화면 텍스트가
    아니다"라고 정확히 짚었고, 동의해서 그렇게 바꿈. 완전히 없애는 것도
    검토했지만 "오늘 일정 없음"과 "지금은 할 일 없을 뿐"을 구분하기
    위해 다음 할 일 이름 + 절대 시각은 남기기로 사용자가 선택함.
- `lib/features/planner/planner_page.dart`의 `_CenterSummary`도 같은
  이유로 "N분 후 시작" → 절대 시각으로 변경(`isCurrent`일 때는 더
  이상 "N분 남음" 표시 자체가 의미가 없어져서 그 줄을 통째로 제거).
- `lib/features/routines/routine_form_page.dart`: 길이 스테퍼(+5/-5분
  버튼)와 길이 프리셋 ChoiceChip(15/30/45/60/90분) UI 전부 삭제.
- `lib/features/routines/routine_editor_page.dart`: 목록 부제목에서
  "끝시각 · 길이" 표시 제거, 시작 시각만 표시.
- `lib/features/planner/dial_painter.dart`: `_sameRoutines`에서
  `durationMin` 비교 제거.
- 영향받은 테스트 전부 수정: `routine_test.dart`(containsMinute 테스트
  그룹 전체 삭제), `routine_status_test.dart`(전면 재작성, "가장 최근에
  시작된 게 이긴다", "만료 없이 계속 current", "completedRoutineIds 없이는
  완료 여부 무관하게 current 유지"— 이 마지막 게 바로 0번 항목 버그를
  증명하는 케이스이니 그 버그 고칠 때 같이 업데이트할 것),
  `focus_page_test.dart`, `planner_page_test.dart`,
  `routine_editor_page_test.dart`, `routine_form_page_test.dart` 전부.
- **테스트 작성 중 발견한 별도의 미묘한 버그**: `focus_page_test.dart`의
  몇몇 테스트가 `(_currentMinuteOfNow() + N) % (24 * 60)`로 미래
  시각을 만들었는데, 자정 근처에서 실행하면 모듈로 연산이 자정을 넘겨
  "오늘 이른 시각"으로 wrap되어 버린다. 새 모델에서는 "이미 지난(오늘
  이른 시각에 시작한)" 루틴은 즉시 current가 되어버리므로, 테스트가
  "next(미래)"를 기대했는데 실제로는 "current"가 되어 실패했다.
  `%` 대신 `.clamp(0, 24*60 - 1)`로 바꿔서 자정을 넘기지 않게 수정함
  (3곳: `+60`, `+5`, `+10`). **이건 실제 자정 근처 사용 시 마찬가지로
  발생할 수 있는 진짜 엣지케이스이기도 하다** — 예: 유일한 루틴이
  자정에 등록돼 있고 지금이 23:50이면, "오늘 00:00에 이미 시작해서
  하루 종일 current"가 되는 게 새 모델 하에서는 의미상 맞는 동작이긴
  하지만, 직관과 다를 수 있으니 사용자 피드백이 오면 참고할 것.
- 전부 `puro flutter analyze`(0 에러) / `puro flutter test`(160개 전부
  통과) 확인 완료. **다만 이 변경 자체를 내가 빌드해서 사용자 폰에
  설치하지는 않았다** — 사용자가 "안티그래비티"라는 별도 도구로 직접
  빌드·설치해서 검증했고, 그 과정에서 0번 항목의 버그를 발견해
  보고했다.

---

## 3. 보안 — firestore.rules 임시 약화 (원복 필요)

`firestore.rules`가 다음과 같이 약화된 상태로 이번 커밋에 포함됐다:

```
// 원래(안전)
allow read, write: if request.auth != null && request.auth.uid == uid;

// 현재(임시, 약함)
allow read, write: if request.auth != null;
```

이건 **이번 세션에서 내가 바꾼 게 아니고**, 이전 어느 세션(디버깅 중
권한 거부 문제를 우회하려고 했을 가능성)에서 바뀐 채 커밋되지 않고
남아있던 것을 이번에 같이 커밋·푸시했다. 로그인만 되어 있으면 (자신의
익명 계정이든 다른 사용자 계정이든) **누구나 다른 사용자의 모든
데이터를 읽고 쓸 수 있는 상태**라 실제 보안 약점이다.

사용자에게 확인했고, 답변은 **"당분간 이렇게 두고, 나중에 다시 원래대로
복원해야 하는 부분으로 기억해두기"**였다. 즉:
- 지금 당장 고치지 말 것 (의도적으로 보류 중)
- 이 항목을 잊지 말고, 적절한 시점에(예: 출시 전, 또는 사용자가 다시
  요청할 때) `request.auth.uid == uid` 조건을 복원해야 함
- `firebase deploy --only firestore:rules` 등으로 실제 배포되기 전까지는
  로컬/git 상의 설정일 뿐이지만, 배포되는 순간 실제 보안 영향이 생김

---

## 4. 남아있는 보류 작업 (이번 세션 범위 밖)

- **#58~60 (보류, 메모리에도 기록됨)**: 앱 내 도움말(튜토리얼) 페이지
  작성, 설정 화면에 진입점 추가, 테스트 작성. 사용자가 "현재 기능 수정
  작업을 끝낸 뒤에" 하자고 명시적으로 미뤄둔 작업.
- **Google 로그인 → 멀티유저 연동 (다음 작업으로 확정)**: 익명 계정에 Google을
  "연결(link)"하는 방식으로 합의됐고, **멀티유저 + 새로 시작(기존 고정 UID
  데이터 마이그레이션 없음)**으로 범위가 정해졌다. 상세 구현 계획은
  **`GOOGLE_AUTH_PLAN.md`** 참조. 이 작업이 §3의 고정 UID hack 제거와
  firestore.rules 복원을 함께 처리한다. (설정 화면 "업그레이드" 버튼은 아직
  "곧 지원" SnackBar 상태.)
- **알림 오버레이(2단계)**: 다른 앱을 보고 있을 때도 알람 다이얼로그가
  자동으로 뜨는 기능. SYSTEM_ALERT_WINDOW 권한 + 네이티브 오버레이
  윈도우가 필요한 더 큰 작업으로, 1단계(자기 앱 포그라운드일 때만)만
  구현하고 보류하기로 사용자와 합의함.
- **전원 버튼으로 진동 중단**: 사용자가 요청했었으나, Android는 앱이
  `KEYCODE_POWER`를 가로채는 것을 허용하지 않는다(시스템 예약 키).
  대안으로 볼륨 버튼(`dispatchKeyEvent` 네이티브 후킹)은 가능하다고
  설명했지만, 이후 다른 우선순위 작업들에 밀려 실제 구현은 안 됨. 다시
  요청이 오면 볼륨 버튼 방식으로 제안할 것.

---

## 5. 참고: 영속 메모리 위치

`C:\Users\MS\.claude\projects\C--claude-adhd-planner\memory\`에 이
프로젝트 관련 영속 메모리가 있다(자동으로 매 세션 로드됨, 별도 조회
불필요). 다만 일부는 이번 세션 변경으로 미묘하게 낡았을 수 있다:

- `project_alarm_alert_postpone_design.md` — "알람 UI는 작은
  AlertDialog, 미루기는 누적 오프셋" 자체는 여전히 맞지만, `autoCancel`,
  확인 버튼이 Focus로 이동하는 동작, 무음모드 진동 보강 등 이번 세션의
  세부 사항은 반영 안 돼 있음. 이 문서(HANDOFF.md)가 더 최신/상세함.
- `feedback_confirm_ui_shape_before_building.md` — 이번 세션에도 여전히
  유효한 교훈(다이얼로그 vs 풀스크린, 카운트다운 제거 여부 등 매번
  먼저 물어보고 진행했음).
- 나머지(`reference_github_repo.md`, `project_help_page_deferred.md`,
  `project_google_signin_upgrade_deferred.md`,
  `feedback_foldable_screencap_display_id.md`,
  `project_sideload_restricted_settings.md`)는 그대로 유효함.

---

## 6. 코드 상태 요약

> 아래는 원래 작성 시점(`0b7cb05`) 기준이었고, §0-A의 후속 커밋들로 갱신됨.

- **최신 커밋: `2639a3b`** (origin/main에 푸시 완료). 그 뒤로 작업이 더
  있었다면 `git log --oneline -10`으로 실제 HEAD를 확인할 것.
- `puro flutter analyze`: 0 에러
- `puro flutter test`: **전체 179개 통과**(커밋 `2639a3b` 시점). 변경 시
  재실행해서 확인.
- 사용자 폰(삼성 SM-F766N): 위 모든 변경(넘기기 + 알람 점검 5건)이 설치·검증
  완료된 상태. 무음+잠금 진동 정지, 넘기기 동작까지 사용자 직접 확인함.
- **다음 작업**: 구글 계정 멀티유저 연동 — `GOOGLE_AUTH_PLAN.md` 참조(§0-B).
