const admin = require('firebase-admin');
const functions = require('firebase-functions');
const crypto = require('crypto');
const { Resend } = require('resend');

if (!admin.apps.length) {
  admin.initializeApp();
}

// Notification types that should be delivered as push notifications.
// Keep this aligned with the `notifications` Firestore rule's allowed type
// list (firestore.rules:636) so a rule-blocked type never reaches push.
const PUSH_NOTIFICATION_TYPES = new Set([
  'friend_request',
  'friend_accept',
  'event_request',
  'event_accept',
  'event_reject',
  'event_created',
  'event_reminder',
  'mention',
  'friend_joined_event',
  'waitlist_spot_available',
  'post_event_recap',
  'shoutout',
  'chat_message',
]);

// ================= CONFIG =================
// All cooldowns are TEMPORARY by design — no permanent lockouts.
// See CLAUDE.md "OTP Rate Limit Spec".
const OTP_TTL_MS = 10 * 60 * 1000;             // OTP valid for 10 minutes
const OTP_RATE_WINDOW_MS = 60 * 60 * 1000;     // 1-hour sliding window
const OTP_RATE_LIMIT = 5;                       // max 5 resends per hour
const OTP_RESEND_COOLDOWN_MS = 30 * 1000;       // 30s between resends
const OTP_MAX_VERIFY_ATTEMPTS = 10;             // max 10 verify attempts per hour
const OTP_LOCKOUT_MS = 30 * 60 * 1000;          // 30-minute cooldown (auto-expires)
const VERIFY_HARD_LIMIT_MS = 4500;

// ================= REVIEWER BYPASS =================
// Google Play / App Store reviewers need a working test account to access
// restricted areas. This bypass accepts a fixed OTP for a fixed email so
// reviewers can sign in without receiving an actual email.
// IMPORTANT: do not share these credentials publicly. They live only in
// the Play Console "App access" declaration.
const REVIEWER_EMAIL = 'reviewer@yanegi.com';
const REVIEWER_OTP = '123456';

function isReviewerEmail(email) {
  return normalizeEmail(email) === REVIEWER_EMAIL;
}

// ================= HELPERS =================
function setCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
}

function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') {
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return Object.fromEntries(new URLSearchParams(req.body));
    }
  }
  return {};
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function otpDocId(email) {
  return email.replace(/\//g, '%2F');
}

function generateOtp() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

function hashOtp(otp) {
  return crypto.createHash('sha256').update(otp).digest('hex');
}

function getResendConfig() {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.RESEND_FROM_EMAIL;

  if (!apiKey) throw new Error('RESEND_API_KEY missing');
  if (!from) throw new Error('RESEND_FROM_EMAIL missing');

  return { apiKey, from };
}

function sendJson(res, statusCode, body) {
  res.status(statusCode).json(body);
}

function sendError(res, statusCode, code, message) {
  sendJson(res, statusCode, { success: false, code, error: message });
}

function withTimeout(promise, timeoutMs, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(`${label}_timeout`));
      }, timeoutMs);
    }),
  ]);
}

function withDeadline(promise, deadlineMs, label) {
  const remainingMs = Math.max(deadlineMs - Date.now(), 1);
  return withTimeout(promise, remainingMs, label);
}

// ================= EMAIL =================
async function sendOtpEmail({ email, otp }) {
  const { apiKey, from } = getResendConfig();
  const resend = new Resend(apiKey);

  const { data, error } = await resend.emails.send({
    from,
    to: email,
    subject: 'Your Yanegi login code',
    html: `
      <div style="font-family:sans-serif">
        <h2>Yanegi Login Code</h2>
        <p>Your OTP is:</p>
        <h1>${otp}</h1>
        <p>This code expires in 10 minutes.</p>
      </div>
    `,
  });

  if (error) {
    console.error('❌ RESEND ERROR:', error);
    throw new Error(error.message || 'Resend failed');
  }

  console.log('✅ EMAIL SENT:', data);
}

// ================= SEND OTP =================
exports.sendOtp = functions.https.onRequest(async (req, res) => {
  setCors(res);

  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST')
    return sendError(res, 405, 'INVALID_OTP', 'Use POST.');

  const body = parseBody(req);
  const email = normalizeEmail(body.email);

  if (!isValidEmail(email)) {
    return sendError(res, 400, 'INVALID_EMAIL', 'Enter a valid email.');
  }

  // Reviewer bypass: no real email sent, no rate limit. The fixed OTP
  // (REVIEWER_OTP) is accepted in verifyOtp without any Firestore lookup.
  if (isReviewerEmail(email)) {
    console.log('REVIEWER BYPASS: sendOtp skipped for', email);
    return sendJson(res, 200, { success: true });
  }

  const db = admin.firestore();
  const otpRef = db.collection('email_otps').doc(otpDocId(email));
  const now = Date.now();
  const otp = generateOtp();
  const otpHash = hashOtp(otp);

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(otpRef);
      const data = snap.exists ? snap.data() : {};

  const windowStart = data?.windowStartAt || 0;
  const sendCount = data?.sendCount || 0;
  const lastSentAt = data?.lastSentAt || 0;

      const sameWindow = now - windowStart < OTP_RATE_WINDOW_MS;

      if (lastSentAt && now - lastSentAt < OTP_RESEND_COOLDOWN_MS) {
        throw new Error('RESEND_COOLDOWN');
      }

      if (sameWindow && sendCount >= OTP_RATE_LIMIT) {
        throw new Error('RATE_LIMIT');
      }

      tx.set(
        otpRef,
        {
          email,
          otpHash,
          expiresAt: now + OTP_TTL_MS,
          attempts: 0,
          lockedUntil: null,
          used: false,
          usedAt: null,
          sessionToken: null,
          status: 'pending',
          lastSentAt: now,
          sendCount: sameWindow ? sendCount + 1 : 1,
          windowStartAt: sameWindow ? windowStart : now,
        },
        { merge: true }
      );
    });

    try {
      await sendOtpEmail({ email, otp });
      await otpRef.update({ status: 'sent' });
      return sendJson(res, 200, { success: true });
    } catch (e) {
      await otpRef.update({ status: 'failed' });

      return sendJson(res, 500, {
        success: false,
        code: 'INVALID_OTP',
        error: e.message,
      });
    }
  } catch (e) {
    if (e.message === 'RATE_LIMIT') {
      return sendError(res, 429, 'TOO_MANY_ATTEMPTS', 'Too many requests.');
    }

    if (e.message === 'RESEND_COOLDOWN') {
      return sendError(
        res,
        429,
        'RESEND_COOLDOWN',
        'Please wait before requesting another code.'
      );
    }

    return sendError(res, 500, 'INVALID_OTP', 'Failed to send OTP.');
  }
});

// ================= VERIFY OTP =================
exports.verifyOtp = functions.https.onRequest(async (req, res) => {
  setCors(res);

  const respond = (statusCode, payload) =>
    sendJson(res, statusCode, {
      success: false,
      isNewUser: false,
      ...payload,
    });

  try {
    console.log('VERIFY START');
    const deadlineMs = Date.now() + VERIFY_HARD_LIMIT_MS;

    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST')
      return respond(405, { code: 'INVALID_OTP', error: 'Use POST.' });

    const body = parseBody(req);
    const email = normalizeEmail(body.email);
    const otp = String(body.otp || '');

    if (!isValidEmail(email))
      return respond(400, { code: 'INVALID_EMAIL', error: 'Invalid email' });

    if (!/^\d{6}$/.test(otp))
      return respond(400, { code: 'INVALID_OTP', error: 'Invalid OTP' });

    // ===== Reviewer bypass =====
    // Accept REVIEWER_OTP for REVIEWER_EMAIL without touching Firestore OTPs.
    // Returns a custom token and ensures the reviewer account is marked
    // premium via a custom claim so all premium gates unlock.
    if (isReviewerEmail(email) && otp === REVIEWER_OTP) {
      console.log('REVIEWER BYPASS: verifyOtp accepted for', email);
      let reviewerUser;
      let reviewerIsNew = false;
      try {
        reviewerUser = await admin.auth().getUserByEmail(email);
      } catch (e) {
        if (e.code === 'auth/user-not-found') {
          reviewerUser = await admin
            .auth()
            .createUser({ email, displayName: 'App Reviewer' });
          reviewerIsNew = true;
        } else {
          throw e;
        }
      }

      // Mark as premium reviewer via custom claim so the client can unlock
      // premium UI without a paid subscription record.
      await admin
        .auth()
        .setCustomUserClaims(reviewerUser.uid, { isReviewer: true, premium: true });

      // Also mirror premium=true onto the user doc so client code that
      // reads from Firestore (rather than from the token claim) unlocks too.
      // Seed a complete profile so the reviewer skips onboarding entirely.
      try {
        const reviewerDocRef = admin
          .firestore()
          .collection('users')
          .doc(reviewerUser.uid);
        const reviewerDocSnap = await reviewerDocRef.get();
        const existingData = reviewerDocSnap.exists
          ? reviewerDocSnap.data() || {}
          : {};

        await reviewerDocRef.set(
          {
            uid: reviewerUser.uid,
            email,
            name: existingData.name || 'App Reviewer',
            username: existingData.username || 'reviewer',
            usernameLower: existingData.usernameLower || 'reviewer',
            bio: existingData.bio || 'App Reviewer Account',
            photoUrl: existingData.photoUrl || '',
            vibes: existingData.vibes || [],
            hasCompletedProfile: true,
            isReviewer: true,
            premium: true,
            isPremium: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt:
              existingData.createdAt ||
              admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        // Reserve the `reviewer` username lookup doc so onboarding flows
        // don't trip uniqueness checks. Use the same uid so collisions
        // with a real user named "reviewer" can't happen post-deploy.
        await admin
          .firestore()
          .collection('usernames')
          .doc('reviewer')
          .set(
            { uid: reviewerUser.uid },
            { merge: true }
          );
      } catch (e) {
        console.error('Reviewer user-doc seed failed:', e);
      }

      const reviewerToken = await admin
        .auth()
        .createCustomToken(reviewerUser.uid, { isReviewer: true, premium: true });

      return sendJson(res, 200, {
        success: true,
        token: reviewerToken,
        isNewUser: reviewerIsNew,
      });
    }

    const db = admin.firestore();
    const otpRef = db.collection('email_otps').doc(otpDocId(email));
    const snap = await withDeadline(
      otpRef.get(),
      deadlineMs,
      'otp_read'
    );

    if (!snap.exists)
      return respond(400, { code: 'INVALID_OTP', error: 'OTP not found' });

    const data = snap.data() ?? {};
    const now = Date.now();
    const attempts = Number(data.attempts || 0);
    const lockedUntil = Number(data.lockedUntil || 0);
    const used = data.used === true;
    const usedAt = Number(data.usedAt || 0);
    const otpMatched = data.otpHash === hashOtp(otp);

    console.log('ATTEMPTS COUNT', attempts);

    if (Number(data.expiresAt || 0) > 0 && now > data.expiresAt) {
      await withDeadline(otpRef.delete(), deadlineMs, 'otp_delete');
      return respond(400, { code: 'INVALID_OTP', error: 'OTP expired' });
    }

    if (used) {
      const sessionToken = (data.sessionToken || '').toString().trim();
      if (sessionToken && sessionToken.length > 0) {
        return sendJson(res, 200, {
          success: true,
          token: sessionToken,
          isNewUser: false,
        });
      }

      return respond(400, {
        code: 'OTP_USED',
        error: 'Code already used',
      });
    }

    if (!otpMatched) {
      console.log('OTP FAILED');
      if (lockedUntil && now < lockedUntil) {
        return respond(429, {
          code: 'TOO_MANY_ATTEMPTS',
          error: 'Too many attempts. Please try again later.',
          lockedUntil,
        });
      }

      // If a previous lockout has expired, the cooldown was served — reset
      // the attempts counter so this is a temporary cooldown, never permanent.
      const effectiveAttempts =
        lockedUntil && now >= lockedUntil ? 0 : attempts;
      const nextAttempts = effectiveAttempts + 1;
      const shouldLock = nextAttempts >= OTP_MAX_VERIFY_ATTEMPTS;
      const nextLockedUntil = shouldLock ? now + OTP_LOCKOUT_MS : null;
      await withDeadline(
        otpRef.update({
          attempts: nextAttempts,
          lockedUntil: nextLockedUntil,
        }),
        deadlineMs,
        'otp_attempt_update'
      );

      if (shouldLock) {
        return respond(429, {
          code: 'TOO_MANY_ATTEMPTS',
          error: 'Too many attempts. Please try again later.',
          lockedUntil: nextLockedUntil,
        });
      }

      return respond(401, { code: 'INVALID_OTP', error: 'Invalid code' });
    }

    console.log('OTP MATCHED');
    console.log('OTP VALIDATED');
    try {
      await withDeadline(
        db.runTransaction(async (tx) => {
          const latestSnap = await tx.get(otpRef);
          const latestData = latestSnap.data() ?? {};
          if (latestData.used === true) {
            throw new Error('OTP_USED');
          }
          if (latestData.otpHash !== hashOtp(otp)) {
            throw new Error('INVALID_OTP');
          }
          tx.update(otpRef, {
            used: true,
            usedAt: now,
          });
        }),
        deadlineMs,
        'otp_verify_transaction'
      );
    } catch (e) {
      if (e.message === 'OTP_USED') {
        return respond(400, { code: 'OTP_USED', error: 'Code already used' });
      }
      if (e.message === 'INVALID_OTP') {
        return respond(401, { code: 'INVALID_OTP', error: 'Invalid code' });
      }
      throw e;
    }

    let user;
    let isNewUser = false;
    try {
      user = await withDeadline(
        admin.auth().getUserByEmail(email),
        deadlineMs,
        'user_lookup'
      );
    } catch (e) {
      if (e.code && e.code !== 'auth/user-not-found') {
        throw e;
      }
      user = await withDeadline(
        admin.auth().createUser({ email }),
        deadlineMs,
        'user_create'
      );
      isNewUser = true;
    }

    console.log('CREATING TOKEN');
    let token;
    try {
      token = await withDeadline(
        admin.auth().createCustomToken(user.uid),
        deadlineMs,
        'token_creation'
      );
    } catch (e) {
      console.log('VERIFY FAILED');
      console.error('verifyOtp token creation failed:', e);
      return sendJson(res, 500, {
        success: false,
        isNewUser,
        code: 'INVALID_OTP',
        error: 'Unable to create sign-in token',
      });
    }
    await withDeadline(
      otpRef.update({ sessionToken: token }),
      deadlineMs,
      'otp_session_update'
    );
    console.log('TOKEN CREATED');
    console.log('VERIFY SUCCESS');

    return sendJson(res, 200, { success: true, token, isNewUser });
  } catch (e) {
    console.log('VERIFY FAILED');
    console.error('verifyOtp internal error:', e);
    return res.status(500).json({
      success: false,
      isNewUser: false,
      code: 'INVALID_OTP',
      error: 'Internal error',
    });
  }
});

// ================= PUSH FAN-OUT =================
// Triggered when a `notifications/{id}` document is created. Enqueues a
// `push_queue` entry written as the service account so client rules can keep
// `push_queue` write-locked. Honors the recipient's `pushNotifications`
// setting and drops notifications whose source entity is gone.
exports.onNotificationCreate = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data() || {};
    const notificationId = context.params.notificationId;

    const userId = String(data.userId || '').trim();
    const senderId = String(data.senderId || '').trim();
    const type = String(data.type || '').trim();
    const title = String(data.title || data.message || '').trim();
    const body = String(data.body || data.message || '').trim();
    const eventId = String(data.eventId || '').trim();
    const chatId = String(data.chatId || '').trim();
    const dedupeKey = String(data.dedupeKey || '').trim();
    const senderName = String(data.senderName || '').trim();
    const senderAvatar = String(data.senderAvatar || '').trim();

    if (!userId || !type) {
      console.warn('onNotificationCreate: missing userId or type', {
        notificationId,
      });
      return null;
    }

    if (!PUSH_NOTIFICATION_TYPES.has(type)) {
      // Notification type is valid for in-app feed but not for push.
      return null;
    }

    const db = admin.firestore();

    // Honor the recipient's push-notification and nearbyActivity preferences.
    // nearbyActivity is checked here (server-side) because the client cannot
    // read other users' settings docs (owner-only Firestore rules).
    const isNearbyNotification = dedupeKey.startsWith('nearby_event:');
    try {
      const settingsSnap = await db
        .doc(`users/${userId}/settings/main`)
        .get();
      const settings = settingsSnap.exists ? settingsSnap.data() || {} : {};
      const pushEnabled = settings.pushNotifications;
      if (pushEnabled === false) {
        return null;
      }
      if (isNearbyNotification && settings.nearbyActivity === false) {
        return null;
      }
    } catch (e) {
      console.warn('onNotificationCreate: settings read failed', {
        userId,
        error: e && e.message,
      });
      // Fall through with default-enabled behavior.
    }

    // Drop the push if the source entity has been deleted before delivery.
    try {
      if (eventId) {
        const eventSnap = await db.doc(`events/${eventId}`).get();
        if (!eventSnap.exists) return null;
        const ev = eventSnap.data() || {};
        if (ev.isDeleted === true) return null;
      }
      if (chatId) {
        const chatSnap = await db.doc(`chats/${chatId}`).get();
        if (!chatSnap.exists) return null;
      }
      if (senderId) {
        const senderSnap = await db.doc(`users/${senderId}`).get();
        if (!senderSnap.exists) return null;
        const sender = senderSnap.data() || {};
        if (sender.isDeleted === true) return null;
      }
    } catch (e) {
      console.warn('onNotificationCreate: source check failed', {
        notificationId,
        error: e && e.message,
      });
      // Continue — better to attempt delivery than to drop on a transient read.
    }

    const queuePayload = {
      notificationId,
      userId,
      senderId,
      senderName,
      senderAvatar,
      type,
      title,
      body,
      eventId,
      chatId,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
      // Deterministic ID prevents duplicates if the trigger retries.
      await db.collection('push_queue').doc(notificationId).set(queuePayload);
    } catch (e) {
      console.error('onNotificationCreate: push_queue write failed', {
        notificationId,
        error: e && e.message,
      });
    }

    return null;
  });

// ================= PUSH QUEUE CONSUMER =================
// Triggered when onNotificationCreate writes a push_queue/{notificationId}
// document. Atomically claims the job (pending → processing), loads the
// recipient's FCM token, sends the push notification, and marks the doc
// sent or failed. Stale tokens are cleared from the users doc automatically.
//
// Idempotency: the transaction below flips status before sending. If the
// function is retried (Cloud Functions auto-retries on unhandled throw),
// the fresh snapshot check ensures we don't double-deliver.
exports.processPushQueue = functions.firestore
  .document('push_queue/{notificationId}')
  .onCreate(async (snapshot, context) => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    const notificationId = context.params.notificationId;
    const raw = snapshot.data() || {};

    const userId      = String(raw.userId      || '').trim();
    const senderId    = String(raw.senderId    || '').trim();
    const senderName  = String(raw.senderName  || '').trim();
    const type        = String(raw.type        || '').trim();
    const title       = String(raw.title       || '').trim();
    const body        = String(raw.body        || '').trim();
    const eventId     = String(raw.eventId     || '').trim();
    const chatId      = String(raw.chatId      || '').trim();

    if (!userId || !type) {
      console.warn('[push_queue] missing userId or type', { notificationId });
      return null;
    }

    // Atomically flip status from pending → processing.
    // If status is already processing/sent/failed a previous attempt claimed
    // it — bail out to avoid double delivery.
    let claimed = false;
    try {
      await db.runTransaction(async (txn) => {
        const fresh = await txn.get(snapshot.ref);
        if (!fresh.exists || fresh.data().status !== 'pending') return;
        txn.update(snapshot.ref, {
          status: 'processing',
          processingAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        claimed = true;
      });
    } catch (e) {
      console.error('[push_queue] claim transaction failed', { notificationId, error: e.message });
      throw e; // Trigger retry — claim error is transient.
    }

    if (!claimed) {
      console.log('[push_queue] already claimed, skipping', { notificationId });
      return null;
    }

    // Load recipient FCM token.
    let fcmToken;
    try {
      const userSnap = await db.collection('users').doc(userId).get();
      if (!userSnap.exists) {
        await snapshot.ref.update({
          status: 'failed',
          failReason: 'user_not_found',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return null;
      }
      fcmToken = (userSnap.data().fcmToken || '').toString().trim();
    } catch (e) {
      console.error('[push_queue] user fetch failed', { userId, error: e.message });
      await snapshot.ref.update({
        status: 'failed',
        failReason: e.message || 'user_fetch_error',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {});
      throw e; // Transient Firestore error — allow retry.
    }

    if (!fcmToken) {
      await snapshot.ref.update({
        status: 'failed',
        failReason: 'no_fcm_token',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log('[push_queue] no FCM token for user', { userId });
      return null;
    }

    // FCM data payload — all values must be strings.
    const fcmData = { type, click_action: 'FLUTTER_NOTIFICATION_CLICK' };
    if (senderId)   fcmData.senderId   = senderId;
    if (senderName) fcmData.senderName = senderName;
    if (eventId)    fcmData.eventId    = eventId;
    if (chatId) {
      fcmData.chatId  = chatId;
      fcmData.isGroup = String(chatId.startsWith('grp_'));
    }

    const STALE_ERRORS = new Set([
      'messaging/registration-token-not-registered',
      'messaging/invalid-registration-token',
    ]);

    try {
      await messaging.send({
        token: fcmToken,
        notification: {
          title: title || 'New Activity',
          body:  body  || '',
        },
        data: fcmData,
        android: {
          priority: 'high',
          notification: {
            channelId: 'yanegi_activity',
            priority:  'high',
            sound:     'default',
          },
        },
        apns: {
          payload: { aps: { sound: 'default', badge: 1 } },
        },
      });

      await snapshot.ref.update({
        status: 'sent',
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`[push_queue] ✓ delivered type=${type} to userId=${userId}`);
    } catch (e) {
      if (STALE_ERRORS.has(e.code)) {
        // Stale token — clear it so future sends skip this user until they
        // reopen the app and refresh their token.
        await db.collection('users').doc(userId)
          .update({ fcmToken: '' })
          .catch(() => {});
        await snapshot.ref.update({
          status: 'failed',
          failReason: 'stale_token',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[push_queue] stale token cleared userId=${userId}`);
      } else {
        await snapshot.ref.update({
          status: 'failed',
          failReason: e.message || e.code || 'fcm_error',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // Log to push_notification_failures so failures are observable.
        await db.collection('push_notification_failures').add({
          notificationId,
          userId,
          type,
          errorCode:    e.code    || '',
          errorMessage: e.message || 'unknown',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(() => {});
        console.error(`[push_queue] FCM error type=${type} userId=${userId}`, e.code || e.message);
      }
    }

    return null;
  });

// ================= EVENT LABEL SYNONYMS =================
// Mirrors lib/utils/event_label.dart so notification copy matches in-app text.
const EVENT_LABEL_WORDS = [
  'hangout', 'meetup', 'gathering', 'outing', 'get-together',
  'catch-up', 'link-up', 'session', 'rendezvous', 'adventure', 'plan', 'sesh',
];

function eventLabelFor(eventId) {
  if (!eventId) return 'event';
  const hash = [...eventId].reduce((acc, c) => acc + c.charCodeAt(0), 0);
  return EVENT_LABEL_WORDS[hash % EVENT_LABEL_WORDS.length];
}

function eventLabelCapitalized(eventId) {
  const w = eventLabelFor(eventId);
  return w.charAt(0).toUpperCase() + w.slice(1);
}

// ================= EVENT REMINDERS =================
// Runs every 30 minutes. Sends FCM push notifications to active participants
// of events that start in approximately 24 hours and 1 hour.
//
// Deduplication: reminder_sent/{eventId}_{type} prevents double-firing when
// the function runs multiple times inside the same target window.
// Stale FCM tokens are cleaned up automatically on delivery failure.
exports.sendEventReminders = functions.pubsub
  .schedule('every 30 minutes')
  .timeZone('UTC')
  .onRun(async (_context) => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    const now = Date.now();

    // Each window: fires once per event per reminder type.
    // halfWindowMs = 16 min so two consecutive 30-min ticks always cover the
    // target (16 + 14 overlap means no event slips through the gap).
    const REMINDER_WINDOWS = [
      {
        type: '24h',
        targetMs: 24 * 60 * 60 * 1000,
        halfWindowMs: 16 * 60 * 1000,
        buildTitle: (title) => `📅 Tomorrow: ${title}`,
        buildBody: (eventId) => `Your ${eventLabelFor(eventId)} starts tomorrow. Don't miss it!`,
      },
      {
        type: '1h',
        targetMs: 60 * 60 * 1000,
        halfWindowMs: 16 * 60 * 1000,
        buildTitle: (title) => `⏰ Starting soon: ${title}`,
        buildBody: (eventId) => `Your ${eventLabelFor(eventId)} starts in about 1 hour. Get ready!`,
      },
    ];

    for (const win of REMINDER_WINDOWS) {
      const targetTime = new Date(now + win.targetMs);
      const windowStart = new Date(targetTime.getTime() - win.halfWindowMs);
      const windowEnd   = new Date(targetTime.getTime() + win.halfWindowMs);

      let eventsSnap;
      try {
        eventsSnap = await db.collection('events')
          .where('status', '==', 'active')
          .where('startAt', '>=', windowStart)
          .where('startAt', '<=', windowEnd)
          .get();
      } catch (e) {
        console.error(`[reminders:${win.type}] event query failed:`, e.message);
        continue;
      }

      console.log(`[reminders:${win.type}] ${eventsSnap.size} event(s) in window`);

      for (const eventDoc of eventsSnap.docs) {
        const eventId   = eventDoc.id;
        const eventData = eventDoc.data();
        if (eventData.isDeleted === true) continue;

        const eventTitle = (eventData.title || 'Your event').trim();

        // ── Deduplication ────────────────────────────────────────────────
        const dedupeId  = `${eventId}_${win.type}`;
        const dedupeRef = db.collection('reminder_sent').doc(dedupeId);
        try {
          const snap = await dedupeRef.get();
          if (snap.exists) continue;          // already sent
          // Write BEFORE sending — stops retries from double-firing.
          await dedupeRef.set({
            eventId,
            type: win.type,
            eventTitle,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.warn(`[reminders:${win.type}] dedupe failed for ${dedupeId}:`, e.message);
          continue;   // safer to skip than to double-send
        }

        // ── Participants ─────────────────────────────────────────────────
        let participantsSnap;
        try {
          participantsSnap = await db
            .collection('event_participants')
            .doc(eventId)
            .collection('users')
            .where('status', 'in', ['joined', 'active'])
            .get();
        } catch (e) {
          console.error(`[reminders:${win.type}] participants fetch failed for ${eventId}:`, e.message);
          continue;
        }

        const uids = participantsSnap.docs
          .map((d) => {
            const data = d.data();
            return (data.userId || d.id || '').toString().trim();
          })
          .filter(Boolean);

        if (uids.length === 0) continue;

        const notifTitle = win.buildTitle(eventTitle);
        const notifBody  = win.buildBody(eventId);

        // ── Send FCM in chunks of 10 (whereIn limit) ────────────────────
        for (let i = 0; i < uids.length; i += 10) {
          const chunk = uids.slice(i, i + 10);

          let usersSnap;
          try {
            usersSnap = await db.collection('users')
              .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
              .get();
          } catch (e) {
            console.error(`[reminders:${win.type}] user fetch failed:`, e.message);
            continue;
          }

          await Promise.allSettled(
            usersSnap.docs.map(async (userDoc) => {
              const uid      = userDoc.id;
              const userData = userDoc.data();
              const token    = (userData.fcmToken || '').toString().trim();
              if (!token) return;

              // Honour per-user push-notification setting.
              try {
                const settingsSnap = await db.doc(`users/${uid}/settings/main`).get();
                const settings = settingsSnap.exists ? (settingsSnap.data() || {}) : {};
                if (settings.pushNotifications === false) return;
              } catch (_) { /* default: enabled */ }

              // ── FCM send ─────────────────────────────────────────────
              try {
                await messaging.send({
                  token,
                  notification: { title: notifTitle, body: notifBody },
                  data: {
                    type: 'event_reminder',
                    eventId,
                    reminderType: win.type,
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                  },
                  android: {
                    priority: 'high',
                    notification: {
                      channelId: 'yanegi_activity',
                      priority: 'high',
                      sound: 'default',
                    },
                  },
                  apns: {
                    payload: { aps: { sound: 'default', badge: 1 } },
                  },
                });
                console.log(`[reminders:${win.type}] ✓ sent to ${uid}`);
              } catch (e) {
                const stale = [
                  'messaging/registration-token-not-registered',
                  'messaging/invalid-registration-token',
                ];
                if (stale.includes(e.code)) {
                  // Token expired — clear it so future sends don't waste quota.
                  await db.collection('users').doc(uid)
                    .update({ fcmToken: '' })
                    .catch(() => {});
                } else {
                  console.warn(`[reminders:${win.type}] FCM failed for ${uid}:`, e.code || e.message);
                }
              }
            })
          );
        }

        console.log(`[reminders:${win.type}] processed "${eventTitle}" (${uids.length} participant(s))`);
      }
    }

    return null;
  });

// ================= POST-EVENT RECAP =================
// Runs every 30 minutes. Sends a "How was your event?" FCM push to every
// active participant of events that ended ~30 minutes ago.
//
// Dedup: recap_sent/{eventId} prevents double-firing.
// Skip: participants who already submitted a recap (recapSubmittedAt set).
exports.sendPostEventRecaps = functions.pubsub
  .schedule('every 30 minutes')
  .timeZone('UTC')
  .onRun(async (_context) => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    const now = Date.now();

    // Window: events that ended 30 ± 16 minutes ago.
    const targetMs = 30 * 60 * 1000;
    const halfWindowMs = 16 * 60 * 1000;
    const targetTime = new Date(now - targetMs);
    const windowStart = new Date(targetTime.getTime() - halfWindowMs);
    const windowEnd   = new Date(targetTime.getTime() + halfWindowMs);

    let eventsSnap;
    try {
      eventsSnap = await db.collection('events')
        .where('status', '==', 'active')
        .where('endAt', '>=', windowStart)
        .where('endAt', '<=', windowEnd)
        .get();
    } catch (e) {
      console.error('[recap] event query failed:', e.message);
      return null;
    }

    console.log(`[recap] ${eventsSnap.size} event(s) in recap window`);

    for (const eventDoc of eventsSnap.docs) {
      const eventId   = eventDoc.id;
      const eventData = eventDoc.data();
      if (eventData.isDeleted === true) continue;

      const eventTitle = (eventData.title || 'Your event').trim();

      // ── Deduplication ──────────────────────────────────────────────────────
      const dedupeRef = db.collection('recap_sent').doc(eventId);
      try {
        const dedupeSnap = await dedupeRef.get();
        if (dedupeSnap.exists) continue;
        await dedupeRef.set({
          eventId, eventTitle,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.warn(`[recap] dedupe failed for ${eventId}:`, e.message);
        continue;
      }

      // ── Participants ────────────────────────────────────────────────────────
      let participantsSnap;
      try {
        participantsSnap = await db
          .collection('event_participants').doc(eventId).collection('users')
          .where('status', 'in', ['joined', 'active'])
          .get();
      } catch (e) {
        console.error(`[recap] participants fetch failed for ${eventId}:`, e.message);
        continue;
      }

      const uids = participantsSnap.docs
        .filter(d => !d.data().recapSubmittedAt)
        .map(d => (d.data().userId || d.id).toString().trim())
        .filter(Boolean);

      if (uids.length === 0) continue;

      // ── FCM in chunks of 10 ────────────────────────────────────────────────
      for (let i = 0; i < uids.length; i += 10) {
        const chunk = uids.slice(i, i + 10);
        let usersSnap;
        try {
          usersSnap = await db.collection('users')
            .where(admin.firestore.FieldPath.documentId(), 'in', chunk).get();
        } catch (e) { continue; }

        await Promise.allSettled(
          usersSnap.docs.map(async (userDoc) => {
            const uid      = userDoc.id;
            const userData = userDoc.data();
            const token    = (userData.fcmToken || '').toString().trim();
            if (!token) return;

            try {
              const settingsSnap = await db.doc(`users/${uid}/settings/main`).get();
              const settings = settingsSnap.exists ? (settingsSnap.data() || {}) : {};
              if (settings.pushNotifications === false) return;
            } catch (_) {}

            try {
              await messaging.send({
                token,
                notification: {
                  title: `How was ${eventTitle}? 🎉`,
                  body: 'Share your recap and tag someone who made it great!',
                },
                data: {
                  type: 'post_event_recap', eventId, eventTitle,
                  click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
                android: {
                  priority: 'high',
                  notification: { channelId: 'yanegi_activity', priority: 'high', sound: 'default' },
                },
                apns: { payload: { aps: { sound: 'default', badge: 1 } } },
              });
            } catch (e) {
              const stale = ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'];
              if (stale.includes(e.code)) {
                await db.collection('users').doc(uid).update({ fcmToken: '' }).catch(() => {});
              }
            }
          })
        );
      }
      console.log(`[recap] processed "${eventTitle}" (${uids.length} participant(s))`);
    }
    return null;
  });

// ================= EVENT PREVIEW (Open Graph / Social Sharing SSR) =================
//
// Root cause of the bug being fixed:
//   /event/** was rewritten to link.html — a STATIC file. Social crawlers
//   (WhatsApp, Telegram, Discord, Facebook, X, LinkedIn) do NOT execute
//   JavaScript, so the client-side Firestore fetch in link.html was invisible
//   to them. They only saw the static <head> meta tags:
//     og:site_name = "Yanegi"
//     og:description = "Join events, meet people, live local."
//   → every event URL rendered the same generic Yanegi card.
//
// Fix:
//   firebase.json now routes /event/** to this Cloud Function.
//   The function fetches event data from Firestore and returns a complete HTML
//   page whose <head> contains per-event OG/Twitter meta tags — readable by
//   crawlers without executing JavaScript.
//
// Preview fields:
//   og:title       → event title
//   og:description → "18 Jun · 5:00 PM · Ranchi University · 14 going · Hosted by Rahul"
//   og:image       → event bannerUrl (or omitted if no cover — still better than generic)
//   twitter:card   → summary_large_image
//
// Fallback: if Firestore is unreachable or event doesn't exist → redirect to /link.html.

function _htmlEsc(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function _buildOgDescription(data, hostName) {
  const parts = [];
  if (data.startAt && typeof data.startAt.toDate === 'function') {
    try {
      const dt = data.startAt.toDate();
      const datePart = new Intl.DateTimeFormat('en-IN', {
        weekday: 'short', day: 'numeric', month: 'short',
        timeZone: 'Asia/Kolkata',
      }).format(dt);
      const timePart = new Intl.DateTimeFormat('en-IN', {
        hour: 'numeric', minute: '2-digit', hour12: true,
        timeZone: 'Asia/Kolkata',
      }).format(dt);
      parts.push(`${datePart} · ${timePart}`);
    } catch (_) {}
  }
  const loc = (data.locationName || '').trim();
  if (loc) parts.push(loc);
  const pCount = parseInt(data.participantsCount || 0, 10);
  if (pCount > 0) parts.push(`${pCount} going`);
  if (hostName) parts.push(`Hosted by ${hostName}`);
  return parts.length ? parts.join(' · ') : 'Join this event on Yanegi.';
}

exports.eventPreview = functions.https.onRequest(async (req, res) => {
  const urlPath  = req.path;
  const segments = urlPath.split('/').filter(Boolean);
  const eventId  = decodeURIComponent(segments[1] || '');

  if (!eventId) {
    res.redirect(301, '/link.html');
    return;
  }

  const BASE_URL = 'https://yanegi-684f9.web.app';
  const eventUrl = `${BASE_URL}/event/${encodeURIComponent(eventId)}`;

  let ogTitle       = 'Event on Yanegi';
  let ogDescription = 'Join this event on Yanegi.';
  let ogImage       = '';      // empty = no og:image tag (still better than generic)
  let previewHtml   = '';

  try {
    const db        = admin.firestore();
    const eventDoc  = await db.collection('events').doc(eventId).get();

    if (!eventDoc.exists || eventDoc.data().isDeleted) {
      res.redirect(301, '/link.html');
      return;
    }

    const d          = eventDoc.data();
    const eventTitle = (d.title || '').trim() || 'Event on Yanegi';
    const bannerUrl  = (d.bannerUrl || d.bannerImagePath || '').trim();
    const locName    = (d.locationName || '').trim();
    const pCount     = parseInt(d.participantsCount || 0, 10);
    let   hostName   = '';

    // Fetch host display name for the "Hosted by" line
    const hostId = (d.hostId || d.host_id || '').toString().trim();
    if (hostId) {
      try {
        const hostDoc = await db.collection('users').doc(hostId).get();
        if (hostDoc.exists) {
          const hd = hostDoc.data();
          hostName = (hd.name || hd.displayName || hd.username || '').trim();
        }
      } catch (_) {}
    }

    ogTitle       = eventTitle;
    ogDescription = _buildOgDescription(d, hostName);
    if (bannerUrl) ogImage = bannerUrl;

    // Pre-render event card — visible to humans viewing in a browser and to
    // crawlers that render page body (LinkedIn, Slack).
    let dateLine = '';
    if (d.startAt && typeof d.startAt.toDate === 'function') {
      try {
        const dt       = d.startAt.toDate();
        const datePart = new Intl.DateTimeFormat('en-IN', {
          weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Kolkata',
        }).format(dt);
        const timePart = new Intl.DateTimeFormat('en-IN', {
          hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Kolkata',
        }).format(dt);
        dateLine = `${datePart} · ${timePart}`;
      } catch (_) {}
    }

    const calSvg    = `<svg class="ic" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`;
    const pinSvg    = `<svg class="ic" viewBox="0 0 24 24"><path d="M17.657 16.657L13.414 20.9a2 2 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/><path d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/></svg>`;
    const peopleSvg = `<svg class="ic" viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87m-4-12a4 4 0 010 7.75"/></svg>`;
    const hostSvg   = `<svg class="ic" viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`;

    previewHtml = `
      ${bannerUrl
        ? `<img class="ev-banner" src="${_htmlEsc(bannerUrl)}" alt="${_htmlEsc(eventTitle)}" />`
        : `<div class="ev-banner-ph"><svg viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="width:40px;height:40px"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg></div>`
      }
      <div class="ev-body">
        <div class="ev-label">Event</div>
        <div class="ev-title">${_htmlEsc(eventTitle)}</div>
        ${dateLine  ? `<div class="ev-row">${calSvg}${_htmlEsc(dateLine)}</div>`           : ''}
        ${locName   ? `<div class="ev-row">${pinSvg}${_htmlEsc(locName)}</div>`            : ''}
        ${pCount > 0 ? `<div class="ev-row">${peopleSvg}${pCount} going</div>`            : ''}
        ${hostName  ? `<div class="ev-row">${hostSvg}Hosted by ${_htmlEsc(hostName)}</div>` : ''}
      </div>
    `;
  } catch (err) {
    console.error('[eventPreview] error:', err.message || err);
    // Fall through — serve with defaults
  }

  if (!previewHtml) {
    previewHtml = `<div class="ev-body"><div class="ev-label">Event</div><div class="ev-title">${_htmlEsc(ogTitle)}</div><div class="ev-row" style="justify-content:center;color:rgba(255,255,255,0.4)">Open in Yanegi to see details</div></div>`;
  }

  const safeEventId = eventId.replace(/\\/g, '\\\\').replace(/'/g, "\\'");

  res.set('Cache-Control', 'public, max-age=300, s-maxage=300');
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  <title>${_htmlEsc(ogTitle)} · Yanegi</title>

  <!-- ── Open Graph ── WhatsApp · Telegram · Discord · Facebook · iMessage ── -->
  <meta property="og:site_name"   content="Yanegi" />
  <meta property="og:type"        content="website" />
  <meta property="og:url"         content="${_htmlEsc(eventUrl)}" />
  <meta property="og:title"       content="${_htmlEsc(ogTitle)}" />
  <meta property="og:description" content="${_htmlEsc(ogDescription)}" />
  ${ogImage ? `<meta property="og:image" content="${_htmlEsc(ogImage)}" />` : ''}

  <!-- ── Twitter / X ── -->
  <meta name="twitter:card"        content="summary_large_image" />
  <meta name="twitter:title"       content="${_htmlEsc(ogTitle)}" />
  <meta name="twitter:description" content="${_htmlEsc(ogDescription)}" />
  ${ogImage ? `<meta name="twitter:image" content="${_htmlEsc(ogImage)}" />` : ''}

  <meta name="description" content="${_htmlEsc(ogDescription)}" />
  <meta name="theme-color" content="#0D1520" />

  <style>
    *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
    :root{--bg:#0D1520;--sf:#131A27;--bd:rgba(255,255,255,.08);--pr:#3B82F6;--tx:#fff;--mu:rgba(255,255,255,.5);--r:16px}
    body{background:var(--bg);color:var(--tx);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px}
    .card{background:var(--sf);border:1px solid var(--bd);border-radius:var(--r);max-width:380px;width:100%;overflow:hidden}
    .brand{display:flex;align-items:center;gap:10px;padding:20px 20px 16px}
    .brand-logo{width:36px;height:36px;border-radius:10px;background:linear-gradient(135deg,#3B82F6,#1E40AF);display:flex;align-items:center;justify-content:center;font-size:18px;font-weight:900;color:#fff;flex-shrink:0}
    .brand-name{font-size:13px;font-weight:700;color:rgba(255,255,255,.5);letter-spacing:.5px;text-transform:uppercase}
    .ev-banner{width:100%;height:180px;object-fit:cover;display:block}
    .ev-banner-ph{width:100%;height:100px;background:rgba(255,255,255,.04);display:flex;align-items:center;justify-content:center;border-top:1px solid var(--bd)}
    .ev-body{padding:16px 20px 20px;border-top:1px solid var(--bd)}
    .ev-label{font-size:11px;font-weight:700;color:var(--pr);text-transform:uppercase;letter-spacing:.8px;margin-bottom:8px}
    .ev-title{font-size:19px;font-weight:700;line-height:1.3;margin-bottom:12px}
    .ev-row{display:flex;align-items:center;gap:8px;color:var(--mu);font-size:13px;margin-top:6px;line-height:1.4}
    .ic{width:13px;height:13px;flex-shrink:0;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
    .actions{padding:16px 20px;border-top:1px solid var(--bd);display:flex;flex-direction:column;gap:10px}
    .btn{display:block;width:100%;padding:14px;border:none;border-radius:12px;font-size:15px;font-weight:700;cursor:pointer;text-decoration:none;text-align:center;transition:opacity .15s}
    .btn:active{opacity:.82}
    .btn-p{background:var(--pr);color:#fff}
    .btn-s{background:rgba(255,255,255,.08);color:var(--tx)}
    .foot{margin-top:24px;color:rgba(255,255,255,.25);font-size:12px}
    .foot a{color:rgba(255,255,255,.35);text-decoration:none}
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">
      <div class="brand-logo">Y</div>
      <div class="brand-name">Yanegi</div>
    </div>
    ${previewHtml}
    <div class="actions">
      <a class="btn btn-p" id="btn-open" href="#">Open in Yanegi App</a>
      <a class="btn btn-s" id="btn-store" href="#" target="_blank">Download Yanegi</a>
    </div>
  </div>
  <div class="foot">
    <a href="https://yanegi.com">yanegi.com</a>&nbsp;·&nbsp;<a href="https://yanegi.com/privacy">Privacy</a>
  </div>

  <script>
    var eid      = '${safeEventId}';
    var isIOS    = /iPad|iPhone|iPod/.test(navigator.userAgent);
    var isAndroid= /Android/.test(navigator.userAgent);
    var storeUrl = isIOS
      ? 'https://apps.apple.com/app/yanegi/id0000000000'
      : 'https://play.google.com/store/apps/details?id=com.yanegi.app';

    document.getElementById('btn-store').href = storeUrl;

    function tryOpen() {
      if (isAndroid) {
        var pkg = 'com.yanegi.app';
        window.location.href = 'intent://event/' + encodeURIComponent(eid)
          + '#Intent;scheme=yanegi;package=' + pkg
          + ';S.browser_fallback_url=' + encodeURIComponent(storeUrl) + ';end';
      } else if (isIOS) {
        window.location.href = 'yanegi://event/' + encodeURIComponent(eid);
        setTimeout(function(){ window.location.href = storeUrl; }, 1500);
      }
    }

    document.getElementById('btn-open').addEventListener('click', function(e){
      e.preventDefault(); tryOpen();
    });
    setTimeout(tryOpen, 300);
  </script>
</body>
</html>`);
});

// ================= RE-ENGAGEMENT SYSTEM =================
// Four trigger types — each targets a different psychological lever.
// All use reengagement_sent/{uid}_{type} for per-type dedup with expiry checks.

// ── Shared helpers ────────────────────────────────────────────────────────────

async function isDormant(db, uid, minHours, maxHours) {
  try {
    const snap = await db.collection('user_presence').doc(uid).get();
    if (!snap.exists) return false;
    const lastSeen = snap.data().lastSeen;
    if (!lastSeen) return false;
    const ageMs = Date.now() - lastSeen.toMillis();
    return ageMs >= minHours * 3600000 && ageMs <= maxHours * 3600000;
  } catch (_) { return false; }
}

async function getUserData(db, uid) {
  try {
    const snap = await db.collection('users').doc(uid).get();
    return snap.exists ? (snap.data() || {}) : null;
  } catch (_) { return null; }
}

async function isPushEnabled(db, uid) {
  try {
    const snap = await db.doc(`users/${uid}/settings/main`).get();
    const s = snap.exists ? (snap.data() || {}) : {};
    return s.pushNotifications !== false;
  } catch (_) { return true; }
}

async function checkAndMarkDedup(db, uid, type, cooldownMs) {
  const ref = db.collection('reengagement_sent').doc(`${uid}_${type}`);
  try {
    const snap = await ref.get();
    if (snap.exists) {
      const sentAt = snap.data().sentAt;
      if (sentAt && Date.now() - sentAt.toMillis() < cooldownMs) return false;
    }
    await ref.set({ uid, type, sentAt: admin.firestore.FieldValue.serverTimestamp() });
    return true;
  } catch (_) { return false; }
}

async function sendReEngagementFCM(messaging, db, uid, token, title, body, eventId) {
  try {
    await messaging.send({
      token,
      notification: { title, body },
      data: {
        type: 're_engagement',
        eventId: eventId || '',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: { channelId: 'yanegi_activity', priority: 'normal', sound: 'default' },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    return true;
  } catch (e) {
    const stale = ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'];
    if (stale.includes(e.code)) {
      await db.collection('users').doc(uid).update({ fcmToken: '' }).catch(() => {});
    }
    return false;
  }
}

function vibeMatchScore(userVibes, eventData) {
  const eVibes = (Array.isArray(eventData.vibes) ? eventData.vibes : []).map(v => v.toLowerCase());
  const eType  = (eventData.activityType || '').toLowerCase();
  return userVibes.filter(v => eVibes.includes(v) || eType.includes(v)).length;
}

// ── Trigger 1: Dormancy + Personalised Events (daily 09:00 UTC) ─────────────
// Psychology: personalisation + FOMO ("you're missing events matched to you")
exports.sendDormancyReEngagement = functions.pubsub
  .schedule('0 9 * * *')
  .timeZone('UTC')
  .onRun(async (_ctx) => {
    const db = admin.firestore(), messaging = admin.messaging();
    const now = Date.now();
    const twoDaysAgo   = new Date(now - 2  * 86400000);
    const sevenDaysAgo = new Date(now - 7  * 86400000);
    const sevenDaysOut = new Date(now + 7  * 86400000);

    // Upcoming public events
    let eventsSnap;
    try {
      eventsSnap = await db.collection('events')
        .where('status', '==', 'active')
        .where('visibility', '==', 'public')
        .where('startAt', '>=', new Date(now))
        .where('startAt', '<=', sevenDaysOut)
        .limit(60).get();
    } catch (e) { console.error('[dormancy] events query failed:', e.message); return null; }

    const eventDocs = eventsSnap.docs.filter(d => !d.data().isDeleted);
    if (!eventDocs.length) { console.log('[dormancy] no upcoming events'); return null; }

    // Dormant users: lastSeen 48h–7days ago
    let presenceSnap;
    try {
      presenceSnap = await db.collection('user_presence')
        .where('lastSeen', '>=', sevenDaysAgo)
        .where('lastSeen', '<=', twoDaysAgo)
        .limit(200).get();
    } catch (e) { console.error('[dormancy] presence query failed:', e.message); return null; }

    let sent = 0;
    for (const pd of presenceSnap.docs) {
      const uid = pd.id;
      if (!await checkAndMarkDedup(db, uid, 'dormancy', 48 * 3600000)) continue;

      const userData = await getUserData(db, uid);
      if (!userData) { continue; }
      const token = (userData.fcmToken || '').trim();
      if (!token || !await isPushEnabled(db, uid)) { continue; }

      const userVibes = (Array.isArray(userData.vibes) ? userData.vibes : []).map(v => v.toLowerCase());

      // Score and sort events by vibe match
      const scored = eventDocs
        .map(d => ({ doc: d, score: vibeMatchScore(userVibes, d.data()) }))
        .sort((a, b) => b.score - a.score || (b.doc.data().participantsCount || 0) - (a.doc.data().participantsCount || 0));

      const top = scored.slice(0, 3);
      if (!top.length) { continue; }

      const hasVibeMatch = top[0].score > 0;
      const titles = top.map(t => t.doc.data().title || 'an event');
      const firstId = top[0].doc.id;

      const title = hasVibeMatch ? 'Events matching your vibe 🔥' : 'Events happening near you this week';
      const body  = titles.length === 1
        ? `"${titles[0]}" is coming up — don't miss it!`
        : `"${titles[0]}", "${titles[1]}"${titles[2] ? ' and more' : ''} — happening soon!`;

      if (await sendReEngagementFCM(messaging, db, uid, token, title, body, firstId)) sent++;
    }

    console.log(`[dormancy] ${sent} notification(s) sent to ${presenceSnap.size} dormant user(s)`);
    return null;
  });

// ── Trigger 2: Scarcity Alert (every 2 hours) ────────────────────────────────
// Psychology: urgency + loss aversion ("only X spots left — act now")
// Inspired by: Zomato "offer ends in 2h" + BGMI rank decay warning
exports.sendScarcityAlerts = functions.pubsub
  .schedule('0 */2 * * *')
  .timeZone('UTC')
  .onRun(async (_ctx) => {
    const db = admin.firestore(), messaging = admin.messaging();
    const now = Date.now();
    const twoHoursOut   = new Date(now + 2  * 3600000);
    const fortyEightOut = new Date(now + 48 * 3600000);

    // Events starting in 2–48h with ≤ 3 spots left
    let eventsSnap;
    try {
      eventsSnap = await db.collection('events')
        .where('status', '==', 'active')
        .where('visibility', '==', 'public')
        .where('startAt', '>=', twoHoursOut)
        .where('startAt', '<=', fortyEightOut)
        .limit(30).get();
    } catch (e) { console.error('[scarcity] events query failed:', e.message); return null; }

    const scarceEvents = eventsSnap.docs.filter(d => {
      const ed = d.data();
      if (ed.isDeleted) return false;
      const maxCap = parseInt(ed.maxCapacity || 0);
      const pCount = parseInt(ed.participantsCount || 0);
      return maxCap > 0 && (maxCap - pCount) <= 3 && (maxCap - pCount) > 0;
    });

    if (!scarceEvents.length) { console.log('[scarcity] no scarce events'); return null; }

    // For each scarce event notify up to 20 dormant users with matching vibes
    let sent = 0;
    for (const eventDoc of scarceEvents) {
      const ed       = eventDoc.data();
      const eventId  = eventDoc.id;
      const spots    = parseInt(ed.maxCapacity || 0) - parseInt(ed.participantsCount || 0);
      const eVibes   = (Array.isArray(ed.vibes) ? ed.vibes : []).map(v => v.toLowerCase());
      const eType    = (ed.activityType || '').toLowerCase();
      const title    = ed.title || 'an event';

      // Dormant users: inactive 24h–14 days
      let presenceSnap;
      try {
        presenceSnap = await db.collection('user_presence')
          .where('lastSeen', '>=', new Date(now - 14 * 86400000))
          .where('lastSeen', '<=', new Date(now - 86400000))
          .limit(50).get();
      } catch (_) { continue; }

      for (const pd of presenceSnap.docs) {
        const uid = pd.id;
        if (!await checkAndMarkDedup(db, uid, `scarcity_${eventId}`, 4 * 3600000)) continue;

        const userData = await getUserData(db, uid);
        if (!userData) continue;
        const token = (userData.fcmToken || '').trim();
        if (!token || !await isPushEnabled(db, uid)) continue;

        // Only notify if user vibes match (scarcity is more intrusive — require relevance)
        const userVibes = (Array.isArray(userData.vibes) ? userData.vibes : []).map(v => v.toLowerCase());
        const matches   = userVibes.some(v => eVibes.includes(v) || eType.includes(v));
        if (!matches && userVibes.length > 0) continue;

        const notifTitle = `⚡ Only ${spots} spot${spots === 1 ? '' : 's'} left!`;
        const notifBody  = `"${title}" is almost full — grab your spot before it's gone!`;

        if (await sendReEngagementFCM(messaging, db, uid, token, notifTitle, notifBody, eventId)) sent++;
      }
    }

    console.log(`[scarcity] ${sent} notification(s) sent for ${scarceEvents.length} scarce event(s)`);
    return null;
  });

// ── Trigger 3: Social FOMO (daily 18:00 UTC) ─────────────────────────────────
// Psychology: social proof + belonging ("friends are active — where are you?")
// Inspired by: BGMI "your squad is waiting" + Facebook "friends posted while you were away"
exports.sendSocialFomoAlerts = functions.pubsub
  .schedule('0 18 * * *')
  .timeZone('UTC')
  .onRun(async (_ctx) => {
    const db = admin.firestore(), messaging = admin.messaging();
    const now        = Date.now();
    const twoDaysAgo = new Date(now - 2  * 86400000);
    const fourDaysAgo= new Date(now - 4  * 86400000);
    const fortyEightHoursAgo = new Date(now - 2 * 86400000);

    // Find recently active event participants (joined in last 48h)
    let recentJoinsSnap;
    try {
      recentJoinsSnap = await db.collectionGroup('users')
        .where('status', 'in', ['active', 'joined'])
        .where('joinedAt', '>=', fortyEightHoursAgo)
        .limit(100).get();
    } catch (e) { console.error('[social-fomo] recent joins query failed:', e.message); return null; }

    if (recentJoinsSnap.empty) { console.log('[social-fomo] no recent joins'); return null; }

    // Map: activeUserId → [eventId]
    const activeUserEvents = {};
    for (const doc of recentJoinsSnap.docs) {
      const d = doc.data();
      const userId  = (d.userId || '').trim();
      const eventId = (d.eventId || '').trim();
      if (!userId || !eventId) continue;
      if (!activeUserEvents[userId]) activeUserEvents[userId] = [];
      activeUserEvents[userId].push(eventId);
    }

    const activeUserIds = Object.keys(activeUserEvents);
    if (!activeUserIds.length) return null;

    // Dormant users: inactive 48h–4 days
    let presenceSnap;
    try {
      presenceSnap = await db.collection('user_presence')
        .where('lastSeen', '>=', fourDaysAgo)
        .where('lastSeen', '<=', twoDaysAgo)
        .limit(150).get();
    } catch (e) { console.error('[social-fomo] presence query failed:', e.message); return null; }

    let sent = 0;
    for (const pd of presenceSnap.docs) {
      const uid = pd.id;
      if (!await checkAndMarkDedup(db, uid, 'social_fomo', 24 * 3600000)) continue;

      // Get this user's friends
      let friendIds = [];
      try {
        const friendsSnap = await db.collection('friends').doc(uid).collection('list').get();
        friendIds = friendsSnap.docs.map(d => d.id);
      } catch (_) { continue; }

      // Which of their friends are in activeUserEvents?
      const activeFriendIds = friendIds.filter(fid => activeUserEvents[fid]);
      if (!activeFriendIds.length) continue;

      const userData = await getUserData(db, uid);
      if (!userData) continue;
      const token = (userData.fcmToken || '').trim();
      if (!token || !await isPushEnabled(db, uid)) continue;

      // Fetch friend display names (batch, max 3)
      const sampleFriendIds = activeFriendIds.slice(0, 3);
      const friendNames = [];
      try {
        const friendUsersSnap = await db.collection('users')
          .where(admin.firestore.FieldPath.documentId(), 'in', sampleFriendIds).get();
        for (const d of friendUsersSnap.docs) {
          const n = (d.data().name || d.data().username || 'Someone').trim();
          friendNames.push(n);
        }
      } catch (_) {}

      if (!friendNames.length) continue;

      const count = activeFriendIds.length;
      const firstEventId = activeUserEvents[activeFriendIds[0]][0] || '';
      const notifTitle = count === 1
        ? `${friendNames[0]} is going to an event 👀`
        : `${count} of your friends joined events this week`;
      const notifBody  = count === 1
        ? `${friendNames[0]} joined an event — see what you're missing!`
        : `${friendNames.slice(0, 2).join(' & ')} and ${count - 2 > 0 ? `${count - 2} others` : 'friends'} are going to events. Join them!`;

      if (await sendReEngagementFCM(messaging, db, uid, token, notifTitle, notifBody, firstEventId)) sent++;
    }

    console.log(`[social-fomo] ${sent} notification(s) sent`);
    return null;
  });

// ── Trigger 4: Weekend Hook (every Friday 15:00 UTC) ─────────────────────────
// Psychology: fresh-start effect + anticipation ("weekend is your reset")
// Inspired by: Zomato "weekend special deals" + BGMI "new event this weekend"
exports.sendWeekendHook = functions.pubsub
  .schedule('0 15 * * 5')   // Friday 15:00 UTC
  .timeZone('UTC')
  .onRun(async (_ctx) => {
    const db = admin.firestore(), messaging = admin.messaging();
    const now = Date.now();

    // Events happening Sat–Sun (next 48–72h)
    const satStart = new Date(now + 24 * 3600000);
    const sunEnd   = new Date(now + 72 * 3600000);

    let eventsSnap;
    try {
      eventsSnap = await db.collection('events')
        .where('status', '==', 'active')
        .where('visibility', '==', 'public')
        .where('startAt', '>=', satStart)
        .where('startAt', '<=', sunEnd)
        .limit(20).get();
    } catch (e) { console.error('[weekend] events query failed:', e.message); return null; }

    const weekendEvents = eventsSnap.docs.filter(d => !d.data().isDeleted);
    if (!weekendEvents.length) { console.log('[weekend] no weekend events'); return null; }

    // All users inactive ≥ 24h (broader audience for weekly hook)
    let presenceSnap;
    try {
      presenceSnap = await db.collection('user_presence')
        .where('lastSeen', '<=', new Date(now - 86400000))
        .limit(300).get();
    } catch (e) { console.error('[weekend] presence query failed:', e.message); return null; }

    let sent = 0;
    for (const pd of presenceSnap.docs) {
      const uid = pd.id;
      // 7-day cooldown — only once per weekend
      if (!await checkAndMarkDedup(db, uid, 'weekend_hook', 7 * 86400000)) continue;

      const userData = await getUserData(db, uid);
      if (!userData) continue;
      const token = (userData.fcmToken || '').trim();
      if (!token || !await isPushEnabled(db, uid)) continue;

      // Personalise by vibe match
      const userVibes = (Array.isArray(userData.vibes) ? userData.vibes : []).map(v => v.toLowerCase());
      const scored = weekendEvents
        .map(d => ({ doc: d, score: vibeMatchScore(userVibes, d.data()) }))
        .sort((a, b) => b.score - a.score);

      const top = scored.slice(0, 2);
      const titles = top.map(t => t.doc.data().title || 'an event');
      const firstId = top[0].doc.id;

      const notifTitle = '🌅 Your weekend starts tomorrow';
      const notifBody  = titles.length >= 2
        ? `"${titles[0]}" and "${titles[1]}" are happening near you. No plans yet?`
        : `"${titles[0]}" is happening this weekend. Come join!`;

      if (await sendReEngagementFCM(messaging, db, uid, token, notifTitle, notifBody, firstId)) sent++;
    }

    console.log(`[weekend] ${sent} notification(s) sent`);
    return null;
  });

// ================= FEATURE 12: WEEKLY EVENT DIGEST =================
// Sends a personalised "here's what's happening this week" push every Monday
// at 09:00 UTC.  Inspired by Spotify Discover Weekly and Airbnb weekly email.
//
// Psychological levers:
//   • Fresh-start effect — Monday = new week, clean slate, motivation to plan
//   • Personalisation — vibe-matched events feel curated, not broadcast
//   • Social proof fallback — "X people going" when no vibe match
//   • Scarcity variant — "filling up fast" when top events have ≤5 spots left
//
// Edge cases handled:
//   1. No events next 7 days            → no push (skip silently)
//   2. < 2 events available for user    → no push (digest needs depth)
//   3. User joined ALL upcoming events  → skip (they already know)
//   4. User active in last 2h           → skip (already engaged)
//   5. User dormant > 30 days           → skip (re-engagement owns them)
//   6. Push notifications disabled      → skip
//   7. Stale FCM token                  → clear it
//   8. No user vibes                    → popular-events fallback
//   9. Top events all full              → scarce variant copy
//  10. 7-day per-user dedup             → never more than once per week

exports.sendWeeklyEventDigest = functions.pubsub
  .schedule('0 9 * * 1')   // Every Monday 09:00 UTC
  .timeZone('UTC')
  .onRun(async (_ctx) => {
    const db        = admin.firestore();
    const messaging = admin.messaging();
    const now       = Date.now();

    const sevenDaysOut  = new Date(now + 7  * 86400000);
    const twoHoursAgo   = new Date(now - 2  * 3600000);   // "active" threshold
    const thirtyDaysAgo = new Date(now - 30 * 86400000);  // "reachable" threshold

    // ── Step 1: Collect upcoming public events (next 7 days) ─────────────────
    let eventsSnap;
    try {
      eventsSnap = await db.collection('events')
        .where('status', '==', 'active')
        .where('visibility', '==', 'public')
        .where('startAt', '>=', new Date(now))
        .where('startAt', '<=', sevenDaysOut)
        .orderBy('startAt', 'asc')
        .limit(80)
        .get();
    } catch (e) {
      console.error('[digest] events query failed:', e.message);
      return null;
    }

    const allEvents = eventsSnap.docs.filter(d => !d.data().isDeleted);

    if (allEvents.length < 2) {
      console.log('[digest] fewer than 2 events this week — skipping digest run');
      return null;
    }

    console.log(`[digest] ${allEvents.length} event(s) available this week`);

    // ── Step 2: Reachable users — active 2h–30d ago ──────────────────────────
    let presenceSnap;
    try {
      presenceSnap = await db.collection('user_presence')
        .where('lastSeen', '>=', thirtyDaysAgo)
        .where('lastSeen', '<=', twoHoursAgo)
        .limit(400)
        .get();
    } catch (e) {
      console.error('[digest] presence query failed:', e.message);
      return null;
    }

    if (presenceSnap.empty) {
      console.log('[digest] no reachable users');
      return null;
    }

    let sent = 0;

    for (const pd of presenceSnap.docs) {
      const uid = pd.id;

      // ── 7-day per-user dedup ────────────────────────────────────────────────
      if (!await checkAndMarkDedup(db, uid, 'weekly_digest', 7 * 86400000)) continue;

      // ── User data + token ───────────────────────────────────────────────────
      const userData = await getUserData(db, uid);
      if (!userData) continue;

      const token = (userData.fcmToken || '').toString().trim();
      if (!token) continue;
      if (!await isPushEnabled(db, uid)) continue;

      // ── User vibes ──────────────────────────────────────────────────────────
      const userVibes = (Array.isArray(userData.vibes) ? userData.vibes : [])
        .map(v => v.toLowerCase());

      // ── Events the user already joined ─────────────────────────────────────
      let joinedIds = new Set();
      try {
        const joinedSnap = await db.collection('event_participants')
          .where('userId', '==', uid)
          .where('status', 'in', ['joined', 'active', 'pending'])
          .get();
        joinedSnap.forEach(d => {
          const eid = (d.data().eventId || d.id || '').toString().trim();
          if (eid) joinedIds.add(eid);
        });
      } catch (_) {}

      // ── Filter + score ──────────────────────────────────────────────────────
      const candidates = allEvents
        .filter(d => !joinedIds.has(d.id))
        .map(d => ({
          doc:    d,
          data:   d.data(),
          score:  vibeMatchScore(userVibes, d.data()),
          pCount: parseInt(d.data().participantsCount || 0),
          maxCap: parseInt(d.data().maxCapacity || 0),
        }))
        .sort((a, b) => b.score - a.score || b.pCount - a.pCount);

      // Edge case 3: user already RSVP'd to everything
      if (candidates.length === 0) continue;

      // Edge case 2: need at least 2 distinct events for a meaningful digest
      if (candidates.length < 2) continue;

      // ── Determine notification variant ──────────────────────────────────────
      const top3    = candidates.slice(0, 3);
      const titles  = top3.map(c => (c.data.title || 'an event').trim());
      const hasVibeMatch = top3[0].score > 0;

      // Edge case 9: check if all top events are full or nearly full (≤5 spots)
      const allScarce = top3.every(c => {
        const spots = c.maxCap > 0 ? c.maxCap - c.pCount : 999;
        return spots <= 5 && c.maxCap > 0;
      });

      const totalAvailable = candidates.length;

      let notifTitle, notifBody;

      if (allScarce) {
        // Variant 4: scarcity
        notifTitle = '🗓 This week\'s events are filling up!';
        notifBody  = `Spots going fast — "${titles[0]}"${titles[1] ? ` and "${titles[1]}"` : ''} won't last. Grab yours!`;
      } else if (hasVibeMatch && totalAvailable >= 3) {
        // Variant 1: strong vibe match, plenty of choice
        notifTitle = `🗓 Your week, curated — ${totalAvailable} event${totalAvailable === 1 ? '' : 's'} picked for you`;
        notifBody  = titles.length >= 3
          ? `"${titles[0]}", "${titles[1]}" and ${totalAvailable - 2} more this week!`
          : `"${titles[0]}" and "${titles[1]}" match your vibe this week!`;
      } else if (hasVibeMatch) {
        // Variant 2: vibe match, only 2 events
        notifTitle = '🗓 2 events matched your vibe this week';
        notifBody  = `"${titles[0]}" and "${titles[1]}" — don't miss out!`;
      } else {
        // Variant 3: fallback, popular events
        notifTitle = `🗓 ${totalAvailable} event${totalAvailable === 1 ? '' : 's'} happening near you this week`;
        notifBody  = titles.length >= 2
          ? `Browse what's on: "${titles[0]}", "${titles[1]}"${titles[2] ? ' and more' : ''}`
          : `"${titles[0]}" is coming up — see what's happening!`;
      }

      // ── Send FCM ─────────────────────────────────────────────────────────────
      try {
        await messaging.send({
          token,
          notification: { title: notifTitle, body: notifBody },
          data: {
            type:         'weekly_digest',
            digestCount:  String(totalAvailable),
            topEventId:   top3[0].doc.id,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'yanegi_activity',
              priority:  'normal',
              sound:     'default',
            },
          },
          apns: { payload: { aps: { sound: 'default' } } },
        });
        sent++;
      } catch (e) {
        const stale = [
          'messaging/registration-token-not-registered',
          'messaging/invalid-registration-token',
        ];
        if (stale.includes(e.code)) {
          await db.collection('users').doc(uid).update({ fcmToken: '' }).catch(() => {});
        }
      }
    }

    console.log(`[digest] ${sent} weekly digest notification(s) sent to ${presenceSnap.size} reachable user(s)`);
    return null;
  });
