const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

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
            memberIds: admin.firestore.FieldValue.arrayUnion(userId),
            memberTokens: admin.firestore.FieldValue.arrayUnion(memberToken),
          });
        }

        return {basketId: basketDoc.id, basketData};
      } catch (error) {
        throw new functions.https.HttpsError(
            "unknown", `Error fetching basket: ${error.message}`,
        );
      }
    });


exports.sendNotification =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Request must be authenticated.",
        );
      }

      const {
        notificationTitle, notificationBody,
        userTokens, channelId,
      } = data;

      if (!userTokens || userTokens.length === 0) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "No FCM tokens provided.",
        );
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
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        tokens: userTokens, // Multiple recipients
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
