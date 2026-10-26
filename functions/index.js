const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// Cift belgelerinde uyeler user1/user2 alanlarinda (eski surumlerde users dizisi) tutulur.
function coupleMembers(c) {
  if (!c) return [];
  const list = Array.isArray(c.users) ? c.users : [];
  return [...new Set([...list, c.user1, c.user2].filter(Boolean))];
}

function extractFirstName(name) {
  if (!name) return "";
  const parts = name.trim().split(/\s+/);
  if (parts.length > 1) {
    return parts.slice(0, parts.length - 1).join(" ");
  }
  return name.trim();
}

function isNotifAllowed(userData, key) {
  if (!userData) return true;
  if (userData.notificationSettings && userData.notificationSettings[key] !== undefined) {
    return userData.notificationSettings[key] !== false;
  }
  if (userData[key] !== undefined) {
    return userData[key] !== false;
  }
  return true;
}

/**
 * Kullanıcı belgesi güncellendiğinde (Şarj pingi, Kalp pingi veya Düşük Pil)
 * partnerin kapalı olan telefonuna doğrudan Google FCM HTTP v1 üzerinden Push Bildirimi yollar.
 * Alıcının diline ('en' veya 'tr') göre bildirim başlık ve gövdesini otomatik ayarlar.
 */
exports.onUserUpdated = onDocumentUpdated("users/{userId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (!afterData) return null;

  // 1. ŞARJ HATIRLATMASI (chargePing) GELDİ Mİ?
  const beforeCharge = beforeData?.chargePing;
  const afterCharge = afterData?.chargePing;
  if (afterCharge && (!beforeCharge || afterCharge.timestamp !== beforeCharge.timestamp)) {
    if (!isNotifAllowed(afterData, "notif_battery")) {
      console.log("chargePing: alıcı pil bildirimlerini kapatmış, gönderilmedi.");
    } else {
      const fcmToken = afterData.fcmToken;
      if (fcmToken) {
        const isEn = afterData.language === "en";
        const fromName = extractFirstName(afterCharge.fromName) || (isEn ? "Partner" : "Partnerin");
        const titleTr = "🔋 Şarj Hatırlatması!";
        const titleEn = "🔋 Battery Reminder!";
        const bodyTr = `${fromName} şarjını doldurmanı hatırlatıyor 💕`;
        const bodyEn = `${fromName} reminds you to charge your phone 💕`;
        await sendFcmPush(
          fcmToken,
          isEn ? titleEn : titleTr,
          isEn ? bodyEn : bodyTr,
          {
            type: "chargePing",
            title_tr: titleTr,
            title_en: titleEn,
            body_tr: bodyTr,
            body_en: bodyEn,
          }
        );
      }
    }
  }

  // 2. KALP (heartPing) GELDİ Mİ?
  const beforeHeart = beforeData?.heartPing;
  const afterHeart = afterData?.heartPing;
  if (afterHeart && (!beforeHeart || afterHeart.timestamp !== beforeHeart.timestamp)) {
    if (!isNotifAllowed(afterData, "notif_heart")) {
      console.log("heartPing: alıcı kalp bildirimlerini kapatmış, gönderilmedi.");
    } else {
      const fcmToken = afterData.fcmToken;
      if (fcmToken) {
        const isEn = afterData.language === "en";
        const titleTr = "💖 Seni Düşünüyor!";
        const titleEn = "💖 Thinking of You!";
        const bodyTr = "Partnerin şu an seni düşünüyor ve sana kalp gönderdi 💕";
        const bodyEn = "Your partner is thinking of you and sent you a heart 💕";
        await sendFcmPush(
          fcmToken,
          isEn ? titleEn : titleTr,
          isEn ? bodyEn : bodyTr,
          {
            type: "heartPing",
            title_tr: titleTr,
            title_en: titleEn,
            body_tr: bodyTr,
            body_en: bodyEn,
          }
        );
      }
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
      const partnerData = partnerDoc.data();
      if (!isNotifAllowed(partnerData, "notif_battery")) {
        console.log("lowBattery: alıcı pil bildirimlerini kapatmış, gönderilmedi.");
      } else {
        const partnerToken = partnerData?.fcmToken;
        if (partnerToken) {
          const isEn = partnerData?.language === "en";
          const userName = extractFirstName(afterData.name) || (isEn ? "Partner" : "Partnerin");
          const titleTr = "⚠️ Düşük Pil Uyarısı!";
          const titleEn = "⚠️ Low Battery Warning!";
          const bodyTr = `${userName} cihazının şarjı %${afterBattery} seviyesine indi.`;
          const bodyEn = `${userName}'s battery dropped to ${afterBattery}%.`;
          await sendFcmPush(
            partnerToken,
            isEn ? titleEn : titleTr,
            isEn ? bodyEn : bodyTr,
            {
              type: "lowBattery",
              battery: String(afterBattery),
              title_tr: titleTr,
              title_en: titleEn,
              body_tr: bodyTr,
              body_en: bodyEn,
            }
          );
        }
      }
    }
  }

  return null;
});

/**
 * Canlı Sohbet (Messages) koleksiyonuna yeni mesaj düştüğünde partnere push bildirimi yollar.
 * Alıcının diline ('en' veya 'tr') göre uygun bildirim metnini seçer.
 */
exports.onNewMessage = onDocumentCreated("couples/{coupleId}/messages/{messageId}", async (event) => {
  const messageData = event.data.data();
  if (!messageData) return null;

  const senderId = messageData.senderId;
  const coupleId = event.params.coupleId;

  const coupleDoc = await admin.firestore().collection("couples").doc(coupleId).get();
  const coupleData = coupleDoc.data();
  if (!coupleData) return null;

  const partnerId = coupleMembers(coupleData).find((uid) => uid !== senderId);
  if (!partnerId) return null;

  const partnerDoc = await admin.firestore().collection("users").doc(partnerId).get();
  const partnerData = partnerDoc.data();
  if (!isNotifAllowed(partnerData, "notif_chat_messages")) {
    console.log("onNewMessage: alıcı sohbet bildirimlerini kapatmış, gönderilmedi.");
    return null;
  }
  const partnerToken = partnerData?.fcmToken;
  if (!partnerToken) return null;

  const isEn = partnerData?.language === "en";
  const senderDoc = await admin.firestore().collection("users").doc(senderId).get();
  const senderName = extractFirstName(senderDoc.data()?.name) || (isEn ? "Partner" : "Partnerin");
  const defaultPhotoText = isEn ? "Sent a photo 📷" : "Fotoğraf gönderdi 📷";
  const text = messageData.text || defaultPhotoText;

  await sendFcmPush(
    partnerToken,
    senderName,
    text,
    {
      type: "chatMessage",
      coupleId: coupleId,
      title_tr: senderName,
      title_en: senderName,
      body_tr: messageData.text || "Fotoğraf gönderdi 📷",
      body_en: messageData.text || "Sent a photo 📷",
    }
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
    const toData = toDoc.data();
    const token = toData?.fcmToken;
    if (!token) return null;

    const isEn = toData?.language === "en";
    const data = {};
    for (const [k, v] of Object.entries(req.data || {})) data[k] = String(v);

    const finalTitle = isEn ? (req.titleEn || req.title || "") : (req.titleTr || req.title || "");
    const finalBody = isEn ? (req.bodyEn || req.body || "") : (req.bodyTr || req.body || "");

    if (req.silent) {
      await admin.messaging().send({
        token,
        data,
        android: { priority: "high" },
        apns: { headers: { "apns-priority": "5" }, payload: { aps: { contentAvailable: true } } },
      });
    } else {
      await sendFcmPush(token, String(finalTitle).slice(0, 100), String(finalBody).slice(0, 300), data);
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
