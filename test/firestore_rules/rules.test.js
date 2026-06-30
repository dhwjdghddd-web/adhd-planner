/**
 * Regression tests for firestore.rules — guards the critical data-isolation
 * fix (a user may only touch their OWN users/{uid} subtree). Run against the
 * Firestore emulator:
 *
 *   cd test/firestore_rules
 *   npm install
 *   firebase emulators:exec --only firestore "npm test"
 *
 * (See README.md.)
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'adhd-planner-rules-test',
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe('users/{uid} subtree', () => {
  test('a user can read and write their own documents', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(alice, 'users/alice/segments/s1'), { name: 'block' }),
    );
    await assertSucceeds(getDoc(doc(alice, 'users/alice/segments/s1')));
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), { themeMode: 0 }));
  });

  test("a user CANNOT read another user's documents", async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(getDoc(doc(alice, 'users/bob/segments/s1')));
    await assertFails(getDoc(doc(alice, 'users/bob')));
  });

  test("a user CANNOT write another user's documents", async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(alice, 'users/bob/segments/s1'), { name: 'hijack' }),
    );
    await assertFails(setDoc(doc(alice, 'users/bob'), { themeMode: 1 }));
  });

  test('an unauthenticated client is denied everywhere', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users/alice/segments/s1')));
    await assertFails(
      setDoc(doc(anon, 'users/alice/segments/s1'), { name: 'x' }),
    );
  });
});
