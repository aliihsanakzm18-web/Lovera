const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// Cift belgelerinde uyeler user1/user2 alanlarinda (eski surumlerde users dizisi) tutulur.
function coupleMembers(c) {
  if (!c) return [];
  const list = Array.isArray(c.users) ? c.users : [];
  return [...new Set([...list, c.user1, c.user2].filter(Boolean))];
}

/**
 * Kullanıcı belgesi güncellendiğinde (Şarj pingi, Kalp pingi veya Düşük Pil)
 * partnerin kapalı olan telefonuna doğrudan Google FCM HTTP v1 üzerinden Push Bildirimi yollar.
 */
exports.onUserUpdated = onDocumentUpdated("users/{userId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (!afterData) return null;

  // 1. ŞARJ HATIRLATMASI (chargePing) GELDİ Mİ?
  const beforeCharge = beforeData?.chargePing;
  const afterCharge = afterData?.chargePing;
  if (afterCharge && (!beforeCharge || afterCharge.timestamp !== beforeCharge.timestamp)) {
    const fcmToken = afterData.fcmToken;
    if (fcmToken) {
      const fromName = afterCharge.fromName || "Partnerin";
      await sendFcmPush(
        fcmToken,
        "🔋 Şarj Hatırlatması!",
        `${fromName} şarjını doldurmanı hatırlatıyor 💕`,
        { type: "chargePing" }
      );
    }
  }

  // 2. KALP (heartPing) GELDİ Mİ?
  const beforeHeart = beforeData?.heartPing;
  const afterHeart = afterData?.heartPing;
  if (afterHeart && (!beforeHeart || afterHeart.timestamp !== beforeHeart.timestamp)) {
    const fcmToken = afterData.fcmToken;
    if (fcmToken) {
      await sendFcmPush(
        fcmToken,
        "💖 Seni Düşünüyor!",
        "Partnerin şu an seni düşünüyor ve sana kalp gönderdi 💕",
        { type: "heartPing" }
      );
    }
  }

  // 3. KRİTİK DÜŞÜK PİL UYARISI (%15 altına indiğinde partnere haber ver)
  const beforeBattery = beforeData?.batteryLevel;
  const afterBattery = afterData?.batteryLevel;
  if (
    afterBattery !== undefined &&
    afterBattery !== null &&
    afterBattery <= 15 &&
    (beforeBattery === undefined || beforeBattery > 15)
  ) {
    const partnerUid = afterData.partnerUid;
    if (partnerUid) {
      const partnerDoc = await admin.firestore().collection("users").doc(partnerUid).get();
      const partnerToken = partnerDoc.data()?.fcmToken;
      if (partnerToken) {
        const userName = afterData.name || "Partnerinin";
        await sendFcmPush(
          partnerToken,
          "⚠️ Düşük Pil Uyarısı!",
          `${userName} cihazının şarjı %${afterBattery} seviyesine indi.`,
          { type: "lowBattery", battery: String(afterBattery) }
        );
      }
    }
  }

  return null;
});

/**
 * Canlı Sohbet (Messages) koleksiyonuna yeni mesaj düştüğünde partnere push bildirimi yollar
 */
exports.onNewMessage = onDocumentCreated("couples/{coupleId}/messages/{messageId}", async (event) => {
  const messageData = event.data.data();
  if (!messageData) return null;

  const senderId = messageData.senderId;
  const text = messageData.text || "Fotoğraf gönderdi 📷";
  const coupleId = event.params.coupleId;

  const coupleDoc = await admin.firestore().collection("couples").doc(coupleId).get();
  const coupleData = coupleDoc.data();
  if (!coupleData) return null;

  const partnerId = coupleMembers(coupleData).find((uid) => uid !== senderId);
  if (!partnerId) return null;

  const partnerDoc = await admin.firestore().collection("users").doc(partnerId).get();
  const partnerToken = partnerDoc.data()?.fcmToken;
  if (!partnerToken) return null;

  const senderDoc = await admin.firestore().collection("users").doc(senderId).get();
  const senderName = senderDoc.data()?.name || "Partnerin";

  await sendFcmPush(
    partnerToken,
    senderName,
    text,
    { type: "chatMessage", coupleId: coupleId }
  );

  return null;
});

async function sendFcmPush(token, title, body, dataPayload = {}) {
  try {
    const message = {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        title: title,
        body: body,
        ...dataPayload,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "lovera_partner",
          priority: "max",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
            sound: "default",
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log("FCM Push gönderildi:", response);
  } catch (error) {
    console.error("FCM Push gönderme hatası:", error);
  }
}

/**
 * Istemci `pushRequests` koleksiyonuna istek yazar; sunucu gondericinin aliciyla ayni ciftte
 * oldugunu dogrular, FCM gonderir ve istegi siler. Istemcide servis hesabi anahtari yoktur.
 */
exports.onPushRequest = onDocumentCreated("pushRequests/{requestId}", async (event) => {
  const ref = event.data.ref;
  const req = event.data.data();
  try {
    if (!req || !req.fromUid || !req.toUid) return null;
    const db = admin.firestore();
    const fromDoc = await db.collection("users").doc(req.fromUid).get();
    const coupleId = fromDoc.data()?.coupleId;
    if (!coupleId) return null;
    const coupleDoc = await db.collection("couples").doc(coupleId).get();
    const members = coupleMembers(coupleDoc.data());
    if (!members.includes(req.fromUid) || !members.includes(req.toUid)) return null;

    const toDoc = await db.collection("users").doc(req.toUid).get();
    const token = toDoc.data()?.fcmToken;
    if (!token) return null;

    const data = {};
    for (const [k, v] of Object.entries(req.data || {})) data[k] = String(v);

    if (req.silent) {
      await admin.messaging().send({
        token,
        data,
        android: { priority: "high" },
        apns: { headers: { "apns-priority": "5" }, payload: { aps: { contentAvailable: true } } },
      });
    } else {
      await sendFcmPush(token, String(req.title || "").slice(0, 100), String(req.body || "").slice(0, 300), data);
    }
  } catch (e) {
    console.error("onPushRequest hata:", e);
  } finally {
    await ref.delete().catch(() => {});
  }
  return null;
});

/**
 * Hesap silindiginde kullaniciya ait tum Firestore verisini temizler
 * (Apple 5.1.1(v) / Google Play hesap silme politikasi).
 */
const functionsV1 = require("firebase-functions/v1");
exports.onAccountDeleted = functionsV1.auth.user().onDelete(async (user) => {
  const db = admin.firestore();
  const uid = user.uid;
  try {
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const data = userSnap.data() || {};
    if (data.inviteCode) await db.collection("inviteCodes").doc(data.inviteCode).delete().catch(() => {});
    if (data.coupleId) {
      const coupleRef = db.collection("couples").doc(data.coupleId);
      const coupleSnap = await coupleRef.get();
      const partner = coupleMembers(coupleSnap.data()).find((u) => u !== uid);
      if (partner) {
        await db.collection("users").doc(partner).update({
          coupleId: admin.firestore.FieldValue.delete(),
          partnerUid: admin.firestore.FieldValue.delete(),
        }).catch(() => {});
      }
      await db.recursiveDelete(coupleRef);
    }
    await db.recursiveDelete(userRef);
    for (const col of ["blocks", "reports", "pushRequests"]) {
      for (const field of ["uid", "fromUid", "reporterUid", "blockerUid"]) {
        const snap = await db.collection(col).where(field, "==", uid).get();
        await Promise.all(snap.docs.map((d) => d.ref.delete()));
      }
    }
  } catch (e) {
    console.error("onAccountDeleted hata:", e);
  }
});
