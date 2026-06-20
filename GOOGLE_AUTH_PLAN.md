# 구글 계정 멀티유저 연동 — 구현 계획서

작성: 2026-06-20 (Opus 4.8 세션에서 설계, 구현은 Sonnet이 수행)
대상: 이 계획을 따라 구현하는 AI(주로 Sonnet) / 사람

이 문서는 `BUILD_INSTRUCTIONS.md`(최초 스펙)와 `HANDOFF.md`(그 이후 변경 흐름)에
이어지는 신규 기능 계획서입니다. **이 기능을 시작하기 전에 두 문서를 먼저 읽어
현재 코드 상태를 파악하세요.**

---

## 0. 결정 사항 (이미 사용자와 합의됨 — 바꾸지 말 것)

- **목표: 멀티유저.** 각 사용자가 각자 구글 계정으로 자기 데이터만 본다.
- **기존 데이터: 새로 시작.** 고정 UID(`LqBWKlX59ucI6KQ7W2rrlVZtQNv1`)에 쌓인
  데이터는 테스트 데이터라 **마이그레이션하지 않는다.** 그냥 버리고 구조만
  깔끔하게 전환한다.
- **인증 모델: "익명 시작 → 구글 연결(link)".** 설치하면 익명 계정으로 시작,
  설정에서 구글 계정을 **연결(link)** 하면 그 UID가 보존되며 구글 신원이 붙는다.
  다른 기기에서 같은 구글 계정으로 로그인하면 그 UID의 데이터가 따라온다.

## 1. 현재 상태 (출발점) — 반드시 이해하고 시작

`lib/main.dart`가 두 가지 임시방편을 쓰고 있습니다. **이 둘을 걷어내는 게 이
작업의 핵심입니다.**

1. **고정 UID hack**: 익명 로그인은 하지만 데이터는 실제 로그인 UID가 아니라
   하드코딩된 `fixedUid` 아래에 읽고 씁니다(재설치 시 데이터 유지용 임시방편).
   → 멀티유저와 근본적으로 충돌. **제거 대상.**
2. **약화된 firestore.rules**: 현재 `allow read, write: if request.auth != null`
   (로그인만 되어 있으면 누구나 모든 경로 접근). → 멀티유저에선 **`uid ==
   request.auth.uid`로 복원해야** 각자 데이터만 보임. (이 약화는 HANDOFF.md
   §3에 "나중에 복원" 항목으로 기록돼 있던 것 — 이번에 복원한다.)

또 하나 알아둘 점: **알림 액션 버튼은 이미 제거됨**(커밋 `2639a3b`). 따라서
백그라운드 isolate에서 uid를 따로 해석하던 `_handlePostpone`/`_resolveUid`
같은 코드는 **이미 없습니다.** 멀티유저 전환 시 백그라운드 핸들러의 uid
하드코딩을 걱정할 필요가 없어졌습니다(이 점이 작업을 단순하게 만듦).

---

## 2. 사용자가 직접 해야 하는 Firebase 콘솔 작업 (코드로 불가)

**이 작업이 끝나기 전에는 구글 로그인이 동작하지 않습니다. 구현 착수 전에
사용자에게 요청하세요.**

1. **Firebase 콘솔 → Authentication → Sign-in method → Google 사용 설정.**
   프로젝트 지원 이메일 지정.
2. **SHA 지문 등록.** 콘솔 → 프로젝트 설정 → 내 앱(Android) → SHA 인증서 지문
   추가. 디버그 키스토어 지문을 아래 명령으로 뽑아 SHA-1, SHA-256 둘 다 등록:
   - 사용자에게 `! ` 프리픽스로 실행하도록 안내(이 세션에서 직접 실행됨):
     ```
     ! keytool -list -v -keystore "$USERPROFILE/.android/debug.keystore" -alias androiddebugkey -storepass android -keypass android
     ```
   - (릴리스 빌드를 낼 때가 되면 릴리스 키스토어 지문도 같은 식으로 추가.)
3. **갱신된 `google-services.json` 다운로드** → `android/app/google-services.json`
   교체. (SHA 등록 후 다시 받아야 `oauth_client` 항목이 채워짐.)

> 검증 팁: 교체한 `google-services.json`을 열어 `"oauth_client"` 배열에
> `"client_type": 1`(Android) 항목과 `"client_type": 3`(Web) 항목이 있는지
> 확인. Web client(`client_type: 3`)의 `client_id`는 아래 `serverClientId`로
> 쓰일 수 있음(토큰이 null로 나오면 필요).

---

## 3. 의존성 추가 (`pubspec.yaml`)

```yaml
  # Google 로그인
  google_sign_in: ^6.2.2
```

> **버전 주의 (중요):** 이 계획의 코드는 **google_sign_in 6.x API**(`signIn()`,
> `GoogleSignInAuthentication.idToken/accessToken`) 기준입니다. **7.x는 API가
> 완전히 다릅니다**(`authenticate()` 등). pub이 7.x를 끌어오면 6.x로 핀하거나
> 7.x API에 맞게 토큰 획득부를 고쳐야 합니다. 착수 전 pub.dev에서 현재 버전과
> Firebase 연동 예제를 한 번 확인하세요.

`firebase_auth`는 이미 있음(`^6.5.3`).

---

## 4. Phase 1 — 인증 기반 provider 재배선

### 4-1. `lib/data/providers.dart`

`plannerRepositoryProvider`를 "main에서 주입받는 throw 스텁"에서 **auth에서
직접 빌드하는 reactive provider**로 바꿉니다.

기존:
```dart
final plannerRepositoryProvider = Provider<PlannerRepository>((ref) {
  throw UnimplementedError('... overridden in main.dart ...');
});
```

변경:
```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'repositories/firestore/firestore_planner_repository.dart';

/// Firebase 인증 사용자 스트림. userChanges()는 로그인/로그아웃뿐 아니라
/// **연결(link)** 으로 providerData가 바뀔 때도 emit하므로, 익명→구글 연결을
/// UI가 즉시 반영할 수 있다(연결은 uid를 바꾸지 않아 authStateChanges로는
/// 안 잡힌다).
final firebaseUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.userChanges(),
);

/// 현재 활성 계정의 uid. select로 uid만 골라, 토큰 갱신 같은 잡음에는
/// 리빌드되지 않고 **uid가 실제로 바뀔 때만**(로그인/로그아웃/계정전환)
/// 아래 repository가 새로 만들어지게 한다.
final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(firebaseUserProvider.select((s) => s.valueOrNull?.uid)),
);

/// 활성 계정 uid 아래의 Firestore 저장소. uid가 바뀌면 이 provider가
/// 리빌드되고, 이걸 watch하는 모든 스트림(segments/routines/...)이 새 계정의
/// 데이터로 재구독된다 → 화면이 자동으로 새 계정 데이터로 바뀐다.
///
/// **테스트 불변식(절대 깨지 말 것):** 이 provider는 평범한 Provider로 두어
/// 테스트가 FakePlannerRepository로 override할 수 있게 한다. override하면 위
/// auth provider들은 빌드되지 않으므로(=Firebase 접근 없음) 테스트에서 안전하다.
final plannerRepositoryProvider = Provider<PlannerRepository>((ref) {
  final uid = ref.watch(currentUidProvider) ?? FirebaseAuth.instance.currentUser?.uid;
  // main()이 runApp 전에 반드시 로그인(익명 폴백)을 보장하고, 로그아웃은 항상
  // 익명 로그인으로 이어지므로(§5 signOut) uid는 앱 실행 중 사실상 null이 아니다.
  // 첫 프레임의 잠깐(AsyncLoading) 동안만 currentUser로 폴백한다.
  return FirestorePlannerRepository(uid!);
});
```

`notificationServiceProvider`(같은 파일 또는 notification_service.dart에 정의)도
repo를 **watch**하게(계정 바뀌면 새 repo를 쓰도록) 확인. 현재:
```dart
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.read(plannerRepositoryProvider)),
);
```
→ `ref.read`를 `ref.watch`로:
```dart
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.watch(plannerRepositoryProvider)),
);
```

### 4-2. `lib/main.dart`

고정 UID hack 제거 + override 제거. **초기 알람 스케줄은 main에 그대로 둔다**
(테스트 안전성 — §6 참고).

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // 항상 로그인 상태 보장: 아무 계정도 없으면 익명으로 시작.
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  final uid = FirebaseAuth.instance.currentUser!.uid;

  // 초기 알람 스케줄은 여기서 한 번. (계정 전환 시 재스케줄은 _AccountAlarmSync,
  // §6.) 이 main 경로는 위젯 테스트가 타지 않으므로 플랫폼 채널을 써도 안전.
  final repository = FirestorePlannerRepository(uid);
  final notificationService = NotificationService(repository);
  await notificationService.init();
  await notificationService.requestPermissions();
  final routines = await repository.watchRoutines().first;
  final settings = await repository.watchSettings().first;
  await notificationService.rescheduleAll(routines, settings);

  // repo/service override는 더 이상 주입하지 않는다 — provider가 auth에서
  // 스스로 빌드한다(§4-1).
  runApp(const ProviderScope(child: App()));
}
```

> 주의: `fixedUid` 상수와 그걸 쓰던 줄을 완전히 삭제. import 정리.

---

## 5. Phase 2 — AuthService (연결/로그인/로그아웃)

신규 파일 `lib/services/auth_service.dart`.

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// 연결/로그인 결과를 UI에 알리기 위한 결과 타입.
enum AuthOutcome {
  linked,        // 익명 계정에 구글이 성공적으로 연결됨(uid 보존)
  signedIn,      // 기존 구글 계정으로 로그인됨(다른 기기/복구; 현재 익명 데이터는 버려짐)
  cancelled,     // 사용자가 구글 선택창을 닫음
  failed,        // 그 외 오류
}

class AuthService {
  /// 익명 계정에 구글을 **연결(link)**. 새 구글 계정이면 uid가 보존되며
  /// 익명 데이터가 그대로 그 계정 데이터가 된다.
  ///
  /// 이미 다른 곳에서 쓰던 구글 계정이면('credential-already-in-use')
  /// 연결 대신 그 **기존 계정으로 로그인**한다(=다른 기기 복구). 이때 현재
  /// 기기의 익명 로컬 데이터는 그 계정 데이터로 교체된다(uid가 바뀜).
  Future<AuthOutcome> linkGoogle() async {
    final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
    if (gUser == null) return AuthOutcome.cancelled;

    final gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // 방어적: 거의 없겠지만 익명조차 없으면 그냥 로그인.
      await FirebaseAuth.instance.signInWithCredential(credential);
      return AuthOutcome.signedIn;
    }

    try {
      await user.linkWithCredential(credential);
      return AuthOutcome.linked;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
        // 그 구글 계정은 이미 Firebase 사용자임 → 그 계정으로 로그인(복구).
        final cred = e.credential ?? credential;
        await FirebaseAuth.instance.signInWithCredential(cred);
        return AuthOutcome.signedIn;
      }
      if (e.code == 'provider-already-linked') {
        return AuthOutcome.linked; // 이미 연결됨 — 성공으로 취급
      }
      return AuthOutcome.failed;
    } catch (_) {
      return AuthOutcome.failed;
    }
  }

  /// 로그아웃 후 즉시 익명으로 재로그인 → uid가 절대 null이 되지 않게 한다
  /// (provider 체인이 항상 유효한 uid를 가짐). 결과적으로 "새 익명 계정"이
  /// 되어 빈 상태로 시작; 다시 linkGoogle로 다른 계정에 붙을 수 있다.
  Future<void> signOutToAnonymous() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();
  }
}
```

> **토큰이 null로 나올 때:** 일부 환경에서 `gAuth.idToken`이 null이면
> `GoogleSignIn(serverClientId: '<google-services.json의 client_type:3 client_id>')`
> 로 생성해야 합니다. 그 경우 `GoogleSignIn()` 호출부를 그 인스턴스로 교체.

---

## 6. Phase 3 — 계정 전환 시 알람 재스케줄 (`_AccountAlarmSync`)

`lib/app.dart`의 `MaterialApp.builder` Stack에 위젯 하나 추가
(`_AlarmAlertLauncher`, `_ForegroundAlarmWatcher` 옆).

목적: 계정이 바뀌면(=`plannerRepositoryProvider`가 새 repo로 리빌드되면) 옛
계정 알람을 싹 지우고(cancelAll) 새 계정 알람을 다시 깐다.

```dart
class _AccountAlarmSync extends ConsumerWidget {
  const _AccountAlarmSync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // repo가 "바뀔 때만" 재스케줄. fireImmediately를 쓰지 않는 이유:
    //  - 초기 스케줄은 main()이 이미 한다(§4-2).
    //  - 위젯 테스트는 plannerRepositoryProvider를 "고정 Fake"로 override하므로
    //    이 listener는 절대 발화하지 않는다 → 테스트가 플랫폼 채널을 안 건드림.
    //    (fireImmediately를 켜면 테스트에서 rescheduleAll→cancelAll의
    //    MissingPluginException으로 깨진다. 절대 켜지 말 것.)
    ref.listen(plannerRepositoryProvider, (prev, next) async {
      if (identical(prev, next)) return;
      final routines = await next.watchRoutines().first;
      final settings = await next.watchSettings().first;
      try {
        await ref.read(notificationServiceProvider).rescheduleAll(routines, settings);
      } catch (_) {
        // 플랫폼 채널 부재(테스트 등) — 무시.
      }
    });
    return const SizedBox.shrink();
  }
}
```

Stack에 추가:
```dart
              const _AlarmAlertLauncher(),
              const _ForegroundAlarmWatcher(),
              const _AccountAlarmSync(),   // ← 추가
```

> **테스트 안전 불변식 재확인:** (1) main()의 초기 rescheduleAll을 제거하지 말 것.
> (2) `_AccountAlarmSync`는 fireImmediately 금지. (3) 위 listener는 repo가
> 실제로 바뀔 때만 돈다. 위젯 테스트의 Fake repo는 안 바뀌므로 안전.

---

## 7. Phase 4 — 설정 화면 계정 섹션

`lib/features/settings/settings_page.dart`의 계정 섹션(현재 ~264~275줄,
"업그레이드" 버튼이 "추후 지원" 스낵바를 띄우는 자리)을 교체.

상태별 UI:
- **익명일 때:** "익명으로 사용 중" + "Google 계정 연결" 버튼 → `linkGoogle()`.
- **구글 로그인 상태:** 이메일 표시 + "로그아웃" 버튼 → `signOutToAnonymous()`.

`firebaseUserProvider`를 watch해서 상태를 그린다. **단, 테스트(Firebase 미초기화)
에서 깨지지 않도록** 기존 `_currentUser()`의 try/catch 방어 패턴을 유지하거나,
`firebaseUserProvider`를 watch하되 에러/로딩 시 "익명"으로 폴백.

구현 스케치:
```dart
final userAsync = ref.watch(firebaseUserProvider);
final user = userAsync.valueOrNull;
final isSignedIn = user != null && !user.isAnonymous;

// ... 계정 섹션 ...
ListTile(
  leading: const Icon(Icons.person_outline),
  title: Text(isSignedIn ? (user!.email ?? '로그인됨') : '익명으로 사용 중'),
  subtitle: Text(isSignedIn
      ? '다른 기기에서 같은 구글 계정으로 로그인하면 이 데이터가 따라와요.'
      : 'Google 계정을 연결하면 기기를 바꿔도 데이터가 유지돼요.'),
  trailing: isSignedIn
      ? OutlinedButton(
          onPressed: () => _signOut(context, ref),
          child: const Text('로그아웃'),
        )
      : OutlinedButton(
          onPressed: () => _linkGoogle(context, ref),
          child: const Text('Google 연결'),
        ),
),
```

핸들러(같은 State/Widget 안):
```dart
Future<void> _linkGoogle(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await ref.read(authServiceProvider).linkGoogle();
  if (!context.mounted) return;
  switch (outcome) {
    case AuthOutcome.linked:
      messenger.showSnackBar(const SnackBar(content: Text('구글 계정이 연결됐어요.')));
    case AuthOutcome.signedIn:
      messenger.showSnackBar(const SnackBar(
        content: Text('기존 구글 계정으로 로그인했어요. 그 계정의 데이터를 불러옵니다.')));
    case AuthOutcome.cancelled:
      break; // 조용히 무시
    case AuthOutcome.failed:
      messenger.showSnackBar(const SnackBar(content: Text('연결에 실패했어요. 다시 시도해 주세요.')));
  }
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  // 로그아웃하면 이 기기는 빈 익명 계정으로 돌아갑니다(데이터는 계정에 남아 있고
  // 다시 로그인하면 복구). 확인 다이얼로그 한 번 띄우는 걸 권장.
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(authServiceProvider).signOutToAnonymous();
  if (!context.mounted) return;
  messenger.showSnackBar(const SnackBar(content: Text('로그아웃했어요.')));
}
```

> 계정 전환 직후 화면 데이터가 새 계정으로 바뀌는 것은 provider 체인이
> 자동 처리(§4-1). 알람 재스케줄은 `_AccountAlarmSync`가 처리(§6).

---

## 8. Phase 5 — firestore.rules 복원 + 배포

`firestore.rules`를 멀티유저 안전 규칙으로 되돌린다:
```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

배포는 사용자가(또는 firebase CLI 로그인 후):
```
! firebase deploy --only firestore:rules
```
> 배포 전에 §4(고정 UID 제거)가 끝나 있어야 함. 안 그러면 앱이 `fixedUid` 경로를
> 읽다가 규칙에 막혀 데이터가 안 보인다(현재 익명 uid != fixedUid).

---

## 9. 테스트 작성/수정

### 반드시 수정해야 하는 기존 테스트
- `test/features/settings/settings_page_test.dart`: "the account upgrade button
  shows a coming-soon snackbar" 테스트는 더 이상 유효하지 않음(버튼이 구글
  연결을 트리거). → 그 테스트를 **계정 섹션이 '익명' 상태를 렌더한다**는
  테스트로 교체(Firebase 미초기화 환경이라 `firebaseUserProvider`가 에러/로딩
  → '익명으로 사용 중'과 'Google 연결' 버튼이 보이는지 확인). 실제 구글
  로그인 플로우는 플랫폼 의존이라 위젯 테스트로 검증하지 않는다.
- `test/widget_test.dart`: App을 통째로 pump하는 스모크 테스트들. **`App`이
  `_AccountAlarmSync`를 포함**하므로, 그게 `plannerRepositoryProvider`(테스트에서
  Fake로 override됨)만 watch하는지 확인. auth provider를 직접 읽지 않으니
  override만 유지되면 통과해야 함. 만약 깨지면 `firebaseUserProvider`를
  `StreamProvider`로 override(`Stream.value(null)`)하는 한 줄을 테스트
  ProviderScope에 추가.

### 새 테스트(가능한 범위)
- `AuthService`는 Firebase/GoogleSignIn 플랫폼 의존이라 순수 단위 테스트가
  어렵다. `AuthOutcome` enum 분기 로직을 테스트하려면 GoogleSignIn/FirebaseAuth를
  추상화(인터페이스 주입)해야 하는데, 비용 대비 효과가 낮다. **무리해서
  목킹하지 말 것.** 대신 실기기 검증(§10)으로 커버.
- providers 재배선이 기존 `plannerRepositoryProvider` override 계약을 깨지
  않는지가 핵심 → 기존 위젯 테스트 전부 통과하면 그걸로 충분.

### 절차
매 단계 후 `puro flutter analyze`(0 에러) → `puro flutter test`(전체 통과).

---

## 10. 실기기 검증 체크리스트

(빌드/설치는 HANDOFF.md §1의 표준 절차. 폰 IP:포트는 매번 사용자에게 받기.)

1. 새 설치 → 익명으로 시작, 데이터 빈 상태. 루틴 몇 개 생성.
2. 설정 → "Google 연결" → 구글 계정 선택 → "연결됐어요" → 루틴 그대로 유지
   (uid 보존 확인).
3. (다른 기기 또는 앱 데이터 삭제 후 재설치) → 익명으로 시작(빈 상태) →
   "Google 연결" → **같은 구글 계정** 선택 → "기존 구글 계정으로 로그인" →
   1~2에서 만든 루틴이 복구되는지 확인.
4. 알람: 계정 전환(복구) 직후, 새 계정의 루틴 알람이 실제로 울리는지(옛 계정
   알람은 안 울리는지) — `adb shell dumpsys alarm | grep adhdplanner`로 확인.
5. 로그아웃 → 빈 익명 상태로 돌아오는지, 알람이 옛 계정 것 없이 비워지는지.
6. firestore.rules 배포 후: 정상 동작하는지(자기 데이터 읽기/쓰기 OK),
   콘솔 로그에 권한 거부(PERMISSION_DENIED)가 안 뜨는지.

---

## 11. 막힘/주의 사항 (Gotchas)

- **google_sign_in 버전**: 6.x vs 7.x API 차이(§3). 7.x면 `signIn()` 없음.
- **SHA 지문 누락**: 가장 흔한 실패 원인. 디버그/릴리스 각각, SHA-1+SHA-256 모두.
  등록 후 `google-services.json` 재다운로드 필수.
- **idToken null**: `serverClientId`(Web client id) 지정 필요할 수 있음(§5 주석).
- **테스트 안전 불변식 3가지**(§6): main 초기 스케줄 유지 / fireImmediately 금지 /
  plannerRepositoryProvider override 가능 상태 유지. 이걸 어기면 위젯 테스트가
  플랫폼 채널(MissingPluginException)로 깨진다.
- **rules 배포 타이밍**(§8): 고정 UID 제거 전에 rules를 조이면 데이터가 막힌다.
  반드시 §4 → §8 순서.
- **계정 전환 = uid 변경**: provider 체인이 자동으로 새 계정 데이터로 바꾸지만,
  알람은 `_AccountAlarmSync`가 명시적으로 다시 깔아야 한다(별개 시스템).
- **백그라운드 알림 핸들러**: 액션 버튼이 이미 제거돼(커밋 2639a3b) uid를
  background isolate에서 해석할 일이 없다 — 멀티유저로 인한 추가 작업 없음.
- **iOS**: 이 계획은 Android 기준. iOS 구글 로그인은 별도 설정(URL scheme,
  GoogleService-Info.plist의 REVERSED_CLIENT_ID 등)이 필요하나, 이 프로젝트는
  Windows에서 Android만 빌드하므로 범위 밖.

---

## 12. 작업 순서 요약 (체크리스트)

- [ ] §2 Firebase 콘솔: Google 공급자 + SHA 지문 + google-services.json 교체 (사용자)
- [ ] §3 pubspec: google_sign_in 추가
- [ ] §4 providers.dart 재배선 + main.dart에서 고정 UID/override 제거
- [ ] §5 auth_service.dart 신규
- [ ] §6 app.dart에 _AccountAlarmSync 추가
- [ ] §7 settings_page.dart 계정 섹션 교체
- [ ] §9 테스트 수정(설정 테스트 교체, 위젯 테스트 통과 확인)
- [ ] analyze 0 / test 전체 통과
- [ ] 빌드/설치 → §10 실기기 검증 (연결/복구/알람/로그아웃)
- [ ] §8 firestore.rules 복원 + 배포 (검증 후 마지막에)
- [ ] HANDOFF.md의 firestore.rules "복원 필요" 항목 해소로 갱신, 커밋/푸시
