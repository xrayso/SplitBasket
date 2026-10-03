const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const OpenAI = require("openai");
const vision = require("@google-cloud/vision");
const {CATEGORIES, foldDiscounts, readReceipt, tidyNames} =
    require("./receipt-reader");

admin.initializeApp();
const db = admin.firestore();

// ── Receipts ──────────────────────────────────────────────────────────────
// The OpenAI key lives in Secret Manager. Set it once with:
//   firebase functions:secrets:set OPENAI_API_KEY
// Cloud Vision uses the functions' own service account.
const MODEL = "gpt-6-luna";
const withOpenAI = functions.runWith({
  secrets: ["OPENAI_API_KEY"],
  timeoutSeconds: 300,
  memory: "1GB",
});

exports.processReceipt = withOpenAI
    .region("us-central1")
    .storage
    .bucket("splitbasketapp.firebasestorage.app")
    .object()
    .onFinalize(async (object) => {
      // The app uploads receipts to receipts/{uid}/{file}.
      const [folder, ownerId] = object.name.split("/");
      if (folder !== "receipts" || !ownerId ||
          !object.contentType?.startsWith("image/")) {
        return null;
      }

      const receipts = db.collection("receipts");
      const base = {
        ownerId,
        storagePath: object.name,
        createdAt: FieldValue.serverTimestamp(),
      };

      try {
        const openai = new OpenAI(); // reads OPENAI_API_KEY
        const [photo] = await admin.storage()
            .bucket(object.bucket).file(object.name).download();
        const {receipt, check} = await readReceipt({
          openai,
          vision: new vision.ImageAnnotatorClient(),
          model: MODEL,
        }, photo);

        if (!receipt.readable || receipt.items.length === 0) {
          await receipts.add({...base, error: "unreadable"});
          return null;
        }
        // Discounts come off the item they're for, not as items of their own.
        const items = foldDiscounts(receipt.items);

        // Readable names; the model's own guesses are a fine fallback.
        let names = items.map((i) => ({
          name: i.description,
          category: i.category,
        }));
        try {
          ({items: names} = await tidyNames({openai, model: MODEL}, {
            store: receipt.store || "grocery store",
            items: items.map((i) => ({
              text: i.receiptText,
              code: i.code,
            })),
          }));
        } catch (err) {
          console.warn("Couldn't tidy names", err);
        }

        // Write the receipt and its items together, so the app never sees
        // the receipt before its items exist.
        const receiptRef = receipts.doc();
        const batch = db.batch();
        batch.set(receiptRef, {
          ...base,
          store: receipt.store,
          subtotal: receipt.subtotal,
          tax: receipt.tax || 0,
          total: receipt.total,
          // False when the items still don't add up to the subtotal; the
          // app warns so the user can fix the list before adding it.
          checked: check.ok,
        });
        items.forEach((item, index) => {
          const qty = Math.max(1, item.qty);
          batch.set(receiptRef.collection("items").doc(), {
            index,
            description: names[index].name || item.description,
            receiptText: item.receiptText,
            qty,
            unitPrice: item.total / qty,
            total: item.total,
            discount: item.discount,
            taxable: item.taxable,
            category: names[index].category || item.category,
          });
        });
        await batch.commit();
        console.log(`Read ${items.length} items → ${receiptRef.id}` +
          ` (checked: ${check.ok})`);
      } catch (err) {
        console.error("Couldn't read receipt", object.name, err);
        // Tell the app so it stops waiting.
        await receipts.add({...base, error: "failed"});
      }
      return null;
    });

// Turns receipt abbreviations ("KS ORG EGGS") into real product names,
// searching the web (e.g. for Costco item numbers) when unsure.
exports.cleanItemNames = withOpenAI.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated", "Request has to be authenticated.",
    );
  }
  const items = data?.items;
  if (!Array.isArray(items) || items.length === 0 || items.length > 200 ||
      !items.every((i) => typeof i?.text === "string" &&
        i.text.length <= 120 && String(i.code || "").length <= 20)) {
    throw new functions.https.HttpsError(
        "invalid-argument", "items must be 1-200 {text, code} entries.",
    );
  }

  const result = await tidyNames({openai: new OpenAI(), model: MODEL}, {
    store: String(data.store || "grocery store").slice(0, 40),
    items: items.map((i) => ({text: i.text, code: String(i.code || "")})),
  });
  return {
    items: result.items.map((i) => ({
      name: i.name,
      category: CATEGORIES.includes(i.category) ? i.category : "other",
    })),
  };
});


// Existing Function: getBasketByInvitationCode
exports.getBasketByInvitationCode = functions.
    https.onCall(async (data, context) => {
      const {invitationCode, memberToken} = data;

      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Request has to be authenticated.",
        );
      }

      const userId = context.auth.uid;
      try {
        const basketSnapshot = await db.collection("baskets")
            .where("invitationCode", "==", invitationCode)
            .limit(1)
            .get();

        if (basketSnapshot.empty) {
          throw new functions.https.HttpsError(
              "not-found", "No basket found with this invitation code.",
          );
        }

        const basketDoc = basketSnapshot.docs[0];
        const basketData = basketDoc.data();

        // Check if user is already a member
        if (!basketData.memberIds.includes(userId)) {
          await basketDoc.ref.update({
            memberIds: FieldValue.arrayUnion(userId),
            memberTokens: FieldValue.arrayUnion(memberToken),
          });
        }

        return {basketId: basketDoc.id, basketData};
      } catch (error) {
        throw new functions.https.HttpsError(
            "unknown", `Error fetching basket: ${error.message}`,
        );
      }
    });


// ── Notifications ─────────────────────────────────────────────────────────

/**
 * Splits a list into pieces of at most `size` (Firestore's "in" limit).
 * @param {Array} list
 * @param {number} size
 * @return {Array<Array>}
 */
function chunks(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

/**
 * Narrows `tokens` to devices of people the caller is connected to: a
 * friend, a pending friend request, someone they share a basket with, or
 * someone they have charges with (baskets are deleted once finalized). This
 * stops the function being used to message strangers.
 * @param {string} callerId
 * @param {Array<string>} tokens Device tokens the app asked to notify.
 * @return {Promise<Array<string>>} The tokens that may be notified.
 */
async function allowedTokens(callerId, tokens) {
  const wanted = [...new Set(tokens.filter((t) => typeof t === "string" && t))]
      .slice(0, 100);
  if (wanted.length === 0) return [];

  const caller = (await db.collection("users").doc(callerId).get()).data() ||
    {};
  const related = new Set([
    callerId,
    ...(caller.friendIds || []),
    ...(caller.incomingFriendRequests || []),
    ...(caller.outgoingFriendRequests || []),
  ]);
  const basketTokens = new Set();
  const baskets = await db.collection("baskets")
      .where("memberIds", "array-contains", callerId).get();
  baskets.forEach((doc) => {
    const basket = doc.data();
    (basket.memberIds || []).forEach((id) => related.add(id));
    (basket.invitedUserIds || []).forEach((id) => related.add(id));
    (basket.memberTokens || []).forEach((t) => basketTokens.add(t));
  });

  const owners = new Map(); // token -> uid
  for (const chunk of chunks(wanted, 30)) {
    const users = await db.collection("users")
        .where("token", "in", chunk).get();
    users.forEach((doc) => owners.set(doc.data().token, doc.id));
  }

  const unrelated = [...new Set(owners.values())]
      .filter((uid) => !related.has(uid)).slice(0, 10);
  await Promise.all(unrelated.map(async (uid) => {
    const [owes, owed] = await Promise.all([
      db.collection("charges").where("payerId", "==", callerId)
          .where("payeeId", "==", uid).limit(1).get(),
      db.collection("charges").where("payerId", "==", uid)
          .where("payeeId", "==", callerId).limit(1).get(),
    ]);
    if (!owes.empty || !owed.empty) related.add(uid);
  }));

  return wanted.filter((t) =>
    basketTokens.has(t) || (owners.has(t) && related.has(owners.get(t))));
}

exports.sendNotification =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Request must be authenticated.",
        );
      }

      const {userTokens, channelId} = data;
      const notificationTitle = String(data.notificationTitle || "")
          .slice(0, 100);
      const notificationBody = String(data.notificationBody || "")
          .slice(0, 500);

      if (!Array.isArray(userTokens) || userTokens.length === 0) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "No FCM tokens provided.",
        );
      }

      const tokens = await allowedTokens(context.auth.uid, userTokens);
      if (tokens.length < userTokens.length) {
        console.warn(`Skipped ${userTokens.length - tokens.length} ` +
          `token(s) not connected to ${context.auth.uid}`);
      }
      if (tokens.length === 0) {
        return {success: true, message: "No connected recipients."};
      }

      const message = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        android: {
          notification: {
            channelId: channelId,
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: notificationTitle,
                body: notificationBody,
              },
              sound: "default",
            },
          },
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        tokens, // Multiple recipients
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(message);
        console.log(`Notifications sent: ${response.successCount},
    failures: ${response.failureCount}`);
        return {success: true, message: "Notifications sent."};
      } catch (error) {
        console.error("Error sending notifications:", error);
        throw new functions.https
            .HttpsError("unknown", "Failed to send notifications.");
      }
    });
