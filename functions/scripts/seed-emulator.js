#!/usr/bin/env node
// Fills the local Firebase emulators with test accounts and a sample basket.
// Only ever talks to the emulators (firebase.emulators.json), never the real
// project:
//
//   firebase emulators:start --config firebase.emulators.json
//   node scripts/seed-emulator.js
//
// Test accounts (emulator only): test-josh@splitbasket.test,
// test-sam@splitbasket.test, test-alex@splitbasket.test, all with the
// password "emulator-only-123".

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ||= "127.0.0.1:9199";

const admin = require("firebase-admin");

admin.initializeApp({projectId: "splitbasketapp"});
const db = admin.firestore();
const PASSWORD = "emulator-only-123";

const PEOPLE = [
  {key: "josh", userName: "Josh", friendCode: "1001"},
  {key: "sam", userName: "Sam", friendCode: "2002"},
  {key: "alex", userName: "Alex", friendCode: "3003"},
];

const even = (...ids) => Object.fromEntries(
    ids.map((id) => [id, {share: 1 / ids.length, isManual: false}]));

(async () => {
  // Fixed IDs, so re-seeding after an emulator restart keeps the app's
  // logged-in test session valid.
  const uid = {};
  for (const p of PEOPLE) {
    uid[p.key] = `test-${p.key}`;
    try {
      await admin.auth().getUser(uid[p.key]);
    } catch {
      await admin.auth().createUser({
        uid: uid[p.key],
        email: `test-${p.key}@splitbasket.test`,
        password: PASSWORD,
      });
    }
  }

  for (const p of PEOPLE) {
    await db.collection("users").doc(uid[p.key]).set({
      id: uid[p.key],
      userName: p.userName,
      lowerCaseUserName: p.userName.toLowerCase(),
      friendCode: p.friendCode,
      email: `test-${p.key}@splitbasket.test`,
      token: "",
      friendIds: PEOPLE.filter((o) => o.key !== p.key).map((o) => uid[o.key]),
      incomingFriendRequests: [],
      outgoingFriendRequests: [],
    });
  }

  const {josh, sam, alex} = uid;
  const item = (id, name, price, quantity, paidBy, userShares, extra = {}) =>
    ({id, name, price, quantity, addedBy: josh, paidBy, userShares, ...extra});

  await db.collection("baskets").doc("seed-costco").set({
    id: "seed-costco",
    name: "Costco run",
    hostId: josh,
    memberIds: [josh, sam, alex],
    memberTokens: [],
    invitationCode: "SEED01",
    invitedUserIds: [],
    receiptTax: 4.42,
    items: [
      item("i1", "Kirkland Signature Organic Eggs, 24 ct", 9.49, 1, josh,
          even(josh, sam, alex), {category: "dairy_eggs"}),
      item("i2", "Bananas", 1.99, 2, josh, even(josh, sam, alex),
          {category: "produce"}),
      item("i3", "Kirkland Signature Paper Towels, 12 rolls", 24.99, 1, josh,
          even(josh, sam, alex), {taxable: true, category: "household"}),
      item("i4", "Rotisserie Chicken", 7.99, 1, josh,
          {[josh]: {share: 0.7, isManual: true},
            [sam]: {share: 0.3, isManual: false}},
          {category: "meat_seafood"}),
      item("i5", "Kirkland Signature Mixed Nuts, 1.13 kg", 18.99, 1, sam,
          even(sam, alex), {taxable: true, category: "snacks"}),
      item("i6", "San Pellegrino Sparkling Water, 24 x 500 mL", 15.49, 1,
          josh, {}, {taxable: true, category: "beverages"}),
      item("i7", "Organic Baby Spinach, 1 lb", 5.99, 1, josh, {},
          {category: "produce"}),
      item("i8", "Dish Soap", 8.99, 1, josh, even(josh), {taxable: true,
        category: "household"}),
    ],
  });

  await db.collection("baskets").doc("seed-empty").set({
    id: "seed-empty",
    name: "Farm Boy",
    hostId: josh,
    memberIds: [josh, sam],
    memberTokens: [],
    invitationCode: "SEED02",
    invitedUserIds: [],
    items: [],
  });

  console.log("Seeded emulators:", JSON.stringify(uid));
  process.exit(0);
})();
