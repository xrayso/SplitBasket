// Runs against the Firestore, Auth and Storage emulators, e.g.
//   firebase emulators:exec --config firebase.emulators.json \
//     --only firestore,auth,storage --project splitbasketapp \
//     "npm --prefix functions test"
// and is skipped otherwise.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {deleteUserData} = require("../account");

const emulated = process.env.FIRESTORE_EMULATOR_HOST &&
  process.env.FIREBASE_AUTH_EMULATOR_HOST &&
  process.env.FIREBASE_STORAGE_EMULATOR_HOST;

test("deleteUserData removes the account but keeps shared history", {
  skip: !emulated && "needs the Firestore, Auth and Storage emulators",
}, async () => {
  const admin = require("firebase-admin");
  const app = admin.initializeApp({projectId: "splitbasketapp"}, "account");
  const db = app.firestore();
  const auth = app.auth();
  const bucket = app.storage().bucket("splitbasketapp.firebasestorage.app");
  const me = "leaving";
  const get = async (path) => (await db.doc(path).get()).data();

  await auth.createUser({uid: me, email: "leaving@example.com",
    password: "emulator-only-123"});
  await db.doc(`users/${me}`).set({id: me, userName: "leaving",
    token: "tok-me", friendIds: ["amy"], incomingFriendRequests: ["cal"],
    outgoingFriendRequests: ["bo"]});
  await db.doc("users/amy").set({id: "amy", token: "tok-amy",
    friendIds: [me], incomingFriendRequests: [], outgoingFriendRequests: []});
  await db.doc("users/bo").set({id: "bo", token: "tok-bo", friendIds: [],
    incomingFriendRequests: [me], outgoingFriendRequests: []});
  await db.doc("users/cal").set({id: "cal", token: "tok-cal", friendIds: [],
    incomingFriendRequests: [], outgoingFriendRequests: [me]});

  const items = [{id: "milk", name: "Milk", price: 4, quantity: 1,
    paidBy: "amy", addedBy: me, userShares: {
      [me]: {share: 0.5, isManual: false},
      amy: {share: 0.5, isManual: false},
    }}];
  await db.doc("baskets/shared").set({hostId: me, memberIds: [me, "amy"],
    memberTokens: ["tok-me", "tok-amy"], invitedUserIds: ["bo"], items});
  await db.doc("baskets/solo").set({hostId: me, memberIds: [me],
    memberTokens: ["tok-me"], invitedUserIds: ["amy"], items: []});
  await db.doc("baskets/invite").set({hostId: "bo", memberIds: ["bo"],
    memberTokens: ["tok-bo"], invitedUserIds: [me], items: []});
  await db.doc("charges/owed").set({payerId: me, payeeId: "amy", amount: 2,
    involvedUserIds: ["amy", me], status: "pending"});
  await db.doc("receipts/mine").set({ownerId: me});
  await db.doc("receipts/mine/items/1").set({description: "Milk"});
  await db.doc("receipts/amys").set({ownerId: "amy"});
  await bucket.file(`receipts/${me}/a.jpg`).save("photo");
  await bucket.file("receipts/amy/b.jpg").save("photo");

  const result = await deleteUserData({db, bucket, auth}, me);
  assert.deepEqual(result, {basketsLeft: 1, basketsDeleted: 1});

  // Theirs: gone.
  assert.equal(await get(`users/${me}`), undefined);
  await assert.rejects(auth.getUser(me), {code: "auth/user-not-found"});
  assert.equal(await get("baskets/solo"), undefined);
  assert.equal(await get("receipts/mine"), undefined);
  assert.equal(await get("receipts/mine/items/1"), undefined);
  assert.equal((await bucket.getFiles({prefix: `receipts/${me}/`}))[0].length,
      0);

  // Links to them: gone.
  assert.deepEqual((await get("users/amy")).friendIds, []);
  assert.deepEqual((await get("users/bo")).incomingFriendRequests, []);
  assert.deepEqual((await get("users/cal")).outgoingFriendRequests, []);
  assert.deepEqual((await get("baskets/invite")).invitedUserIds, []);

  // Shared history: kept, with Amy now hosting.
  const shared = await get("baskets/shared");
  assert.deepEqual(shared.memberIds, ["amy"]);
  assert.deepEqual(shared.memberTokens, ["tok-amy"]);
  assert.deepEqual(shared.invitedUserIds, ["bo"]);
  assert.equal(shared.hostId, "amy");
  assert.deepEqual(shared.items, items);
  assert.equal((await get("charges/owed")).amount, 2);
  assert.equal((await get("receipts/amys")).ownerId, "amy");
  assert.equal((await bucket.getFiles({prefix: "receipts/amy/"}))[0].length,
      1);

  // Running it again (say, after a timeout) is harmless.
  assert.deepEqual(await deleteUserData({db, bucket, auth}, me),
      {basketsLeft: 0, basketsDeleted: 0});
  await app.delete();
});
