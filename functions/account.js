const {FieldValue} = require("firebase-admin/firestore");

/**
 * Deletes someone's account and the data that's only theirs: their profile,
 * friend links, basket memberships and invites, receipt photos and the
 * receipts read from them, and finally their sign-in.
 *
 * Shared history stays. Items and charges in baskets with other people keep
 * the user's id, which leads to no name once the profile is gone, so the app
 * shows "Deleted user" and everyone else's totals still add up. Baskets
 * nobody else is in are deleted.
 *
 * Safe to run again if it stops partway: the sign-in goes last, so the user
 * can still retry.
 * @param {{db: object, bucket: object, auth: object}} deps Admin services.
 * @param {string} uid The account to delete.
 * @return {Promise<{basketsLeft: number, basketsDeleted: number}>}
 */
async function deleteUserData({db, bucket, auth}, uid) {
  const userRef = db.collection("users").doc(uid);
  const token = (await userRef.get()).data()?.token || "";

  const users = db.collection("users");
  const baskets = db.collection("baskets");
  const [friends, incoming, outgoing, memberOf, invitedTo, receipts] =
      await Promise.all([
        users.where("friendIds", "array-contains", uid).get(),
        users.where("incomingFriendRequests", "array-contains", uid).get(),
        users.where("outgoingFriendRequests", "array-contains", uid).get(),
        baskets.where("memberIds", "array-contains", uid).get(),
        baskets.where("invitedUserIds", "array-contains", uid).get(),
        db.collection("receipts").where("ownerId", "==", uid).get(),
      ]);

  const writer = db.bulkWriter();

  // Friends and friend requests, in both directions.
  const linked = new Map();
  for (const snap of [friends, incoming, outgoing]) {
    snap.docs.forEach((doc) => linked.set(doc.id, doc.ref));
  }
  linked.delete(uid);
  linked.forEach((ref) => writer.update(ref, {
    friendIds: FieldValue.arrayRemove(uid),
    incomingFriendRequests: FieldValue.arrayRemove(uid),
    outgoingFriendRequests: FieldValue.arrayRemove(uid),
  }));

  // Leave every basket. The next member takes over as host so someone can
  // still finalize it.
  let basketsLeft = 0;
  let basketsDeleted = 0;
  for (const doc of memberOf.docs) {
    const basket = doc.data();
    const others = (basket.memberIds || []).filter((id) => id !== uid);
    if (others.length === 0) {
      writer.delete(doc.ref);
      basketsDeleted++;
      continue;
    }
    writer.update(doc.ref, {
      memberIds: FieldValue.arrayRemove(uid),
      invitedUserIds: FieldValue.arrayRemove(uid),
      ...(token && {memberTokens: FieldValue.arrayRemove(token)}),
      ...(basket.hostId === uid && {hostId: others[0]}),
    });
    basketsLeft++;
  }
  const member = new Set(memberOf.docs.map((doc) => doc.id));
  invitedTo.docs
      .filter((doc) => !member.has(doc.id))
      .forEach((doc) => writer.update(doc.ref, {
        invitedUserIds: FieldValue.arrayRemove(uid),
      }));
  await writer.close();

  // Receipts they scanned: the photos, and what was read from them.
  await Promise.all(receipts.docs.map((doc) => db.recursiveDelete(doc.ref)));
  await bucket.deleteFiles({prefix: `receipts/${uid}/`});

  await userRef.delete();
  try {
    await auth.deleteUser(uid);
  } catch (err) {
    if (err.code !== "auth/user-not-found") throw err;
  }
  return {basketsLeft, basketsDeleted};
}

module.exports = {deleteUserData};
