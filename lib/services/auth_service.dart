import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// 연결/로그인 결과를 UI에 알리기 위한 결과 타입.
enum AuthOutcome {
  linked, // 익명 계정에 구글이 성공적으로 연결됨(uid 보존)
  signedIn, // 기존 구글 계정으로 로그인됨(다른 기기/복구; 현재 익명 데이터는 버려짐)
  cancelled, // 사용자가 구글 선택창을 닫음
  failed, // 그 외 오류
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
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
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

  /// 계정 영구 삭제: 먼저 [wipeData]로 모든 Firestore 데이터를 지우고(아직
  /// 그 uid로 인증된 상태라 보안 규칙이 허용함), Firebase 사용자를 삭제한 뒤,
  /// 다시 익명으로 로그인해 "uid는 절대 null이 아니다" 불변식을 지킨다(기기는
  /// 빈 상태로 새로 시작).
  ///
  /// 완료하지 못하면 false(예: 구글 연결 계정 삭제에 필요한 재로그인을
  /// 사용자가 취소). 이 경우 인증 쪽은 건드리지 않는다([wipeData]가 이미 한
  /// 작업은 별개).
  Future<bool> deleteAccount(Future<void> Function() wipeData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    await wipeData();

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // 구글 연결 계정은 삭제 전에 최근 재인증을 요구한다.
      if (e.code != 'requires-recent-login') return false;
      final reauthed = await _reauthenticateWithGoogle(user);
      if (!reauthed) return false;
      await user.delete();
    }

    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signInAnonymously();
    return true;
  }

  Future<bool> _reauthenticateWithGoogle(User user) async {
    final gUser = await GoogleSignIn().signIn();
    if (gUser == null) return false; // 사용자가 취소
    final gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
    return true;
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
