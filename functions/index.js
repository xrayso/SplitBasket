const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

exports.processReceipt = functions
    .region("us-central1")
    .storage
    .bucket("splitbasketapp.firebasestorage.app")
    .object()
    .onFinalize(async (object) => {
      console.log("help me");

      // ── Ignore non-images ─────────────────────────────────────────────
      if (!object.contentType || !object.contentType.startsWith("image/")) {
        console.log("Skipped non-image file:", object.name);
        return null;
      }

      // ── Download the file from Storage ──────────────────────────────
      const bucket = admin.storage().bucket(object.bucket);
      const [buffer] = await bucket.file(object.name).download();
      const bufferBase64 = buffer.toString("base64");

      // ── Veryfi credentials & timestamp ─────────────────────────────
      const cfg = functions.config().veryfi;
      const timestamp = Date.now().toString();

      // ── Build signature ──────────────────────────────────────────────
      // Veryfi expects you to HMAC "timestamp:<timestamp>" (no payload)
      const signature = crypto
          .createHmac("sha256", cfg.client_secret)
          .update(`timestamp:${timestamp}`)
          .digest("base64");

      const headers = {
        "Content-Type": "application/json",
        "CLIENT-ID": cfg.client_id,
        "AUTHORIZATION": `apikey ${cfg.username}:${cfg.api_key}`,
        "X-Veryfi-Request-Timestamp": timestamp,
        "X-Veryfi-Request-Signature": signature,
      };

      const body = {
        file_data: bufferBase64,
        file_name: object.name,
        boost_mode: 1, // optional
      };

      // ── Send to Veryfi ──────────────────────────────────────────────
      let data;
      try {
        ({data} = await axios.post(
            "https://api.veryfi.com/api/v8/partner/documents/",
            body,
            {headers},
        ));
      } catch (err) {
        console.error("Veryfi API error:", err);
        throw err;
      }

      // ── Save the result to Firestore ────────────────────────────────
      const receiptRef = await admin
          .firestore()
          .collection("receipts")
          .add({
            ownerId: object.name.split("/")[1], // if you added ownerId in rules
            veryfi: data,
            storagePath: object.name,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

      // ── Explode line-items into subcollection ───────────────────────
      if (Array.isArray(data.line_items) && data.line_items.length) {
        const batch = admin.firestore().batch();
        data.line_items.forEach((item) => {
          const doc = receiptRef.collection("items").doc();
          batch.set(doc, {
            description: item.description,
            qty: item.quantity != null ? item.quantity : 1,
            unitPrice: item.price,
            total: item.total,
          });
        });
        await batch.commit();
      }

      console.log(`✅  Veryfi parsed → Firestore doc ${receiptRef.id}`);
      return null;
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
