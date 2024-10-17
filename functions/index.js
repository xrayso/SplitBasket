const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

exports.getBasketByInvitationCode =
functions.https.onCall(async (data, context) => {
  const {invitationCode} = data;

  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated", "Request has to be authenticated.");
  }

  const userId = context.auth.uid;

  try {
    const basketSnapshot = await db.collection("baskets")
        .where("invitationCode", "==", invitationCode)
        .limit(1)
        .get();

    if (basketSnapshot.empty) {
      throw new functions.https.HttpsError(
          "not-found", "No basket found with this invitation code.");
    }

    const basketDoc = basketSnapshot.docs[0];
    const basketData = basketDoc.data();

    // Check if user is already a member
    if (!basketData.memberIds.includes(userId)) {
      await basketDoc.ref.update({
        memberIds: admin.firestore.FieldValue.arrayUnion(userId),
      });
    }

    return {basketId: basketDoc.id, basketData};
  } catch (error) {
    throw new functions.https.HttpsError(
        "unknown", `Error fetching basket: ${error.message}`);
  }
});
