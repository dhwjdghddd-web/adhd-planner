# Firestore 보안 규칙 테스트

`firestore.rules`의 **데이터 격리**(사용자는 자기 `users/{uid}` 하위만 접근)
회귀를 막는 에뮬레이터 기반 테스트입니다. 과거 규칙은 `request.auth != null`만
확인해 아무 로그인 사용자나 다른 사용자의 데이터를 읽고 쓸 수 있었습니다 —
이 테스트가 그 구멍이 다시 생기는 것을 잡아줍니다.

## 실행

[Firebase CLI](https://firebase.google.com/docs/cli)와 Node가 필요합니다.

```bash
cd test/firestore_rules
npm install
firebase emulators:exec --only firestore "npm test"
```

`emulators:exec`가 Firestore 에뮬레이터를 띄우고 → `npm test`(Jest)를 실행한 뒤
→ 에뮬레이터를 내립니다. 별도 에뮬레이터 설정은 필요 없습니다(테스트가
`../../firestore.rules`를 직접 읽어 로드).

## 테스트 내용

- 본인 문서 읽기/쓰기 → 허용
- 다른 사용자 문서 읽기/쓰기 → 거부
- 미인증 클라이언트 → 모두 거부
