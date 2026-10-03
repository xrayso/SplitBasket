#!/usr/bin/env node
// Fills the local Firebase emulators with test accounts, baskets, charges,
// a basket invitation and a friend request, so every screen has something
// to show.
// Only ever talks to the emulators (firebase.emulators.json), never the real
// project:
//
//   firebase emulators:start --config firebase.emulators.json
//   node scripts/seed-emulator.js
//
// Test accounts (emulator only): test-josh@splitbasket.test,
// test-sam@splitbasket.test, test-alex@splitbasket.test and
// test-jordan@splitbasket.test, all with the password "emulator-only-123".

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
  // Not a friend yet: has sent Josh a friend request.
  {key: "jordan", userName: "Jordan Lee", friendCode: "4004"},
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

  const {josh, sam, alex, jordan} = uid;
  const friends = {josh: [sam, alex], sam: [josh, alex], alex: [josh, sam],
    jordan: []};
  for (const p of PEOPLE) {
    await db.collection("users").doc(uid[p.key]).set({
      id: uid[p.key],
      userName: p.userName,
      lowerCaseUserName: p.userName.toLowerCase(),
      friendCode: p.friendCode,
      email: `test-${p.key}@splitbasket.test`,
      token: "",
      friendIds: friends[p.key],
      incomingFriendRequests: p.key === "josh" ? [jordan] : [],
      outgoingFriendRequests: p.key === "jordan" ? [josh] : [],
    });
  }

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
      item("i9", "Oral-B CrossAction Advanced Soft Toothbrushes, 8 count",
          12.99, 1, josh, even(josh, alex),
          {taxable: true, category: "personal_care"}),
      item("i10", "Rao's Homemade Marinara Sauce, 2 × 872 mL", 12.99, 2,
          alex, even(josh, sam, alex), {category: "pantry"}),
      item("i11", "Kirkland Signature Frozen Wild Blueberries, 2.27 kg",
          13.99, 1, josh, even(josh, sam, alex), {category: "frozen"}),
      item("i12", "Bagels, 12 count", 7.99, 1, josh, even(sam),
          {category: "bakery"}),
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

  await db.collection("baskets").doc("seed-cottage").set({
    id: "seed-cottage",
    name: "Cottage weekend groceries and supplies",
    hostId: sam,
    memberIds: [sam, josh, alex],
    memberTokens: [],
    invitationCode: "SEED03",
    invitedUserIds: [],
    items: [
      item("c1", "Ground Coffee, 1 kg", 21.99, 1, sam, even(sam, josh, alex),
          {category: "pantry"}),
      item("c2", "Firewood bundle", 9.99, 3, sam, even(sam, josh, alex),
          {taxable: true, category: "other"}),
    ],
  });

  // An invitation waiting for Josh.
  await db.collection("baskets").doc("seed-invite").set({
    id: "seed-invite",
    name: "Roommates – October",
    hostId: alex,
    memberIds: [alex],
    memberTokens: [],
    invitationCode: "SEED04",
    invitedUserIds: [josh],
    items: [],
  });

  // Charges from earlier baskets: Sam owes Josh, Josh owes Alex, and Alex has
  // asked Josh to confirm a payment.
  const charges = db.collection("charges");
  for (const doc of (await charges.get()).docs) await doc.ref.delete();
  const charge = async (id, payerId, payeeId, amount, name, extra = {}) => {
    // Like finalizing: a tax charge's item price is the tax rate.
    const price = extra.isTax ? 0.13 : amount;
    await charges.doc(id).set({
      id, payerId, payeeId, amount,
      item: item(`ci-${id}`, name, price, 1, payeeId, {}),
      date: admin.firestore.Timestamp.fromDate(new Date(2026, 8, 20)),
      involvedUserIds: [payeeId, payerId],
      status: "pending", isTax: false, requestedBy: "",
      ...extra,
    });
  };
  await charge("ch1", sam, josh, 12.5, "Rotisserie Chicken");
  await charge("ch2", sam, josh, 1.63, "Tax", {isTax: true});
  await charge("ch3", josh, alex, 8.25, "Ground Coffee, 1 kg");
  await charge("ch4", alex, josh, 15, "Paper Towels",
      {status: "requested", requestedBy: alex});

  console.log("Seeded emulators:", JSON.stringify(uid));
  process.exit(0);
})();
