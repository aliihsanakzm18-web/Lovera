const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

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
  if (!coupleData || !coupleData.users) return null;

  const partnerId = coupleData.users.find((uid) => uid !== senderId);
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
