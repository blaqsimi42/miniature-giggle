const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const crypto = require('crypto');
const cloudinary = require('cloudinary').v2;
const Stripe = require('stripe');
const https = require('https');
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const monitoring = require('./monitoring');

dotenv.config({ path: path.join(__dirname, '.env') });

function normalizePhone(phone) {
  if (!phone) return null;

  let cleaned = String(phone).trim().replace(/[^\d+]/g, '');
  const hasPlus = cleaned.startsWith('+');
  if (hasPlus) cleaned = cleaned.slice(1);
  cleaned = cleaned.replace(/\D/g, '');

  if (!cleaned) return null;
  if (!hasPlus && cleaned.length === 10) return `+1${cleaned}`;
  if (cleaned.length >= 10) return `+${cleaned}`;
  return null;
}

function normalizeServiceAccount(rawServiceAccount) {
  if (!rawServiceAccount || typeof rawServiceAccount !== 'object') {
    return rawServiceAccount;
  }

  const serviceAccount = { ...rawServiceAccount };
  if (typeof serviceAccount.private_key === 'string') {
    serviceAccount.private_key = serviceAccount.private_key
      .replace(/\\n/g, '\n')
      .trim();
  }

  return serviceAccount;
}

function createPasswordHash(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return { salt, hash };
}

function verifyPassword(password, salt, expectedHash) {
  if (!password || !salt || !expectedHash) return false;
  const actualHash = crypto.scryptSync(password, salt, 64);
  const expected = Buffer.from(expectedHash, 'hex');
  if (actualHash.length !== expected.length) return false;
  return crypto.timingSafeEqual(actualHash, expected);
}

function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 8) {
    return 'Password must be at least 8 characters';
  }
  if (!/[A-Z]/.test(password)) return 'Password must contain at least one uppercase letter';
  if (!/[0-9]/.test(password)) return 'Password must contain at least one digit';
  if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return 'Password must contain at least one special character';
  return null;
}

function isBoostPlan(plan) {
  return String(plan || '').toLowerCase() === 'boost';
}

async function applyPurchasedEntitlement({ userId, plan }) {
  if (!firestore || !userId) return;

  const userRef = firestore.collection('users').doc(userId);

  if (isBoostPlan(plan)) {
    const userSnap = await userRef.get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const currentBoost = userData.boostExpiresAt;
    const currentBoostMs =
      currentBoost && typeof currentBoost.toMillis === 'function'
        ? currentBoost.toMillis()
        : 0;
    const startMs = currentBoostMs > Date.now() ? currentBoostMs : Date.now();
    const boostExpiresAt = admin.firestore.Timestamp.fromMillis(
      startMs + 24 * 60 * 60 * 1000
    );

    await userRef.set(
      {
        boostExpiresAt,
        lastBoostPurchasedAt: admin.firestore.FieldValue.serverTimestamp(),
        activeBoostPlan: plan,
      },
      { merge: true }
    );
    return;
  }

  await userRef.set(
    {
      isPremium: true,
      premiumSince: admin.firestore.FieldValue.serverTimestamp(),
      premiumPlan: plan,
    },
    { merge: true }
  );
}

function purchaseNotificationTitle(plan) {
  return isBoostPlan(plan) ? 'Boost Activated' : 'Premium Unlocked';
}

function purchaseNotificationBody({ userId, plan }) {
  return isBoostPlan(plan)
    ? `User ${userId || 'unknown'} activated a profile boost`
    : `User ${userId || 'unknown'} upgraded to ${plan}`;
}

// Africa's Talking SMS client (recommended for Nigeria)
let atSms = null;
if (process.env.AFRICASTALKING_USERNAME && process.env.AFRICASTALKING_API_KEY) {
  try {
    const AfricasTalking = require('africastalking')({
      apiKey: process.env.AFRICASTALKING_API_KEY,
      username: process.env.AFRICASTALKING_USERNAME,
    });
    atSms = AfricasTalking.SMS;
    console.log("Africa's Talking client initialized");
  } catch (err) {
    console.warn("Africa's Talking init failed:", err && err.message ? err.message : err);
    atSms = null;
  }
} else {
  console.log("Africa's Talking not configured (AFRICASTALKING_USERNAME / AFRICASTALKING_API_KEY missing)");
}

const isAfricaTalkingSandbox =
  String(process.env.AFRICASTALKING_USERNAME || '').trim().toLowerCase() === 'sandbox';

const hasBrevoSms =
  typeof process.env.BREVO_API_KEY === 'string' &&
  process.env.BREVO_API_KEY.trim().length > 0;
const otpProviderPreference = String(process.env.OTP_SMS_PROVIDER || 'auto')
  .trim()
  .toLowerCase();

if (hasBrevoSms) {
  console.log(
    `Brevo SMS configured (sender=${String(process.env.BREVO_SMS_SENDER || '').trim() || 'none'}, providerMode=${otpProviderPreference || 'auto'})`
  );
} else {
  console.log('Brevo SMS not configured (BREVO_API_KEY missing)');
}

function getAfricaTalkingSender() {
  const sender = String(process.env.AFRICASTALKING_SENDER || '').trim();

  // Sandbox credentials do not use a custom sender ID.
  if (isAfricaTalkingSandbox) return undefined;
  if (!sender) return undefined;
  if (sender === 'YourSenderID') return undefined;

  return sender;
}

function getBrevoSender() {
  const sender = String(process.env.BREVO_SMS_SENDER || '').trim();
  if (!sender) return undefined;
  return sender;
}

function normalizePhoneForBrevo(phone) {
  return String(phone || '').replace(/^\+/, '');
}

function postJson(url, headers, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const parsed = new URL(url);

    const req = https.request(
      {
        protocol: parsed.protocol,
        hostname: parsed.hostname,
        port: parsed.port || 443,
        path: `${parsed.pathname}${parsed.search || ''}`,
        method: 'POST',
        headers: {
          accept: 'application/json',
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(payload),
          ...headers,
        },
      },
      (response) => {
        let raw = '';
        response.on('data', (chunk) => {
          raw += chunk;
        });
        response.on('end', () => {
          let parsedBody = null;
          try {
            parsedBody = raw ? JSON.parse(raw) : null;
          } catch (_) {
            parsedBody = raw;
          }
          resolve({
            statusCode: response.statusCode || 0,
            body: parsedBody,
            raw,
          });
        });
      }
    );

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function getJson(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);

    const req = https.request(
      {
        protocol: parsed.protocol,
        hostname: parsed.hostname,
        port: parsed.port || 443,
        path: `${parsed.pathname}${parsed.search || ''}`,
        method: 'GET',
        headers: {
          accept: 'application/json',
          ...headers,
        },
      },
      (response) => {
        let raw = '';
        response.on('data', (chunk) => {
          raw += chunk;
        });
        response.on('end', () => {
          let parsedBody = null;
          try {
            parsedBody = raw ? JSON.parse(raw) : null;
          } catch (_) {
            parsedBody = raw;
          }
          resolve({
            statusCode: response.statusCode || 0,
            body: parsedBody,
            raw,
          });
        });
      }
    );

    req.on('error', reject);
    req.end();
  });
}

async function sendOtpViaAfricaTalking({ uid, phone, otp }) {
  if (!atSms) {
    return {
      ok: false,
      provider: 'africastalking',
      skipped: true,
      reason: 'Africa\'s Talking not configured',
    };
  }

  const sendOptions = {
    to: [phone],
    message: `Your Qubool Nikah verification code is ${otp}`,
  };
  const sender = getAfricaTalkingSender();
  if (sender) sendOptions.from = sender;

  const smsResponse = await atSms.send(sendOptions);
  console.log(
    "[AFRICASTALKING SMS RESPONSE]",
    JSON.stringify(
      {
        uid,
        phone,
        sender: sender || null,
        response: smsResponse,
      },
      null,
      2
    )
  );

  const recipients = smsResponse?.SMSMessageData?.Recipients;
  const firstRecipient = Array.isArray(recipients) ? recipients[0] : null;
  const status = String(firstRecipient?.status || '').toLowerCase();
  const isAccepted =
    status === 'success' ||
    status === 'sent' ||
    Number(firstRecipient?.statusCode) === 101;

  return {
    ok: isAccepted,
    provider: 'africastalking',
    sender: sender || null,
    response: smsResponse,
    recipientStatus: firstRecipient?.status || null,
    recipientStatusCode: firstRecipient?.statusCode || null,
  };
}

async function sendOtpViaBrevo({ uid, phone, otp }) {
  if (!hasBrevoSms) {
    return {
      ok: false,
      provider: 'brevo',
      skipped: true,
      reason: 'Brevo not configured',
    };
  }

  const sender = getBrevoSender();
  const body = {
    recipient: normalizePhoneForBrevo(phone),
    content: `Your Qubool Nikah verification code is ${otp}`,
    type: 'transactional',
    tag: 'otp',
  };

  if (sender) {
    body.sender = sender;
  }
  if (process.env.BREVO_SMS_WEBHOOK_URL?.trim()) {
    body.webUrl = process.env.BREVO_SMS_WEBHOOK_URL.trim();
  }

  const response = await postJson(
    'https://api.brevo.com/v3/transactionalSMS/send',
    {
      'api-key': process.env.BREVO_API_KEY.trim(),
    },
    body
  );

  console.log(
    '[BREVO SMS RESPONSE]',
    JSON.stringify(
      {
        uid,
        phone,
        sender: sender || null,
        statusCode: response.statusCode,
        response: response.body,
      },
      null,
      2
    )
  );

  return {
    ok: response.statusCode >= 200 && response.statusCode < 300,
    provider: 'brevo',
    sender: sender || null,
    statusCode: response.statusCode,
    response: response.body,
  };
}

async function sendOtpMessage({ uid, phone, otp }) {
  const attempts = [];
  const providersInOrder =
    otpProviderPreference === 'brevo'
      ? ['brevo']
      : otpProviderPreference === 'africastalking'
        ? ['africastalking']
        : otpProviderPreference === 'none' || otpProviderPreference === 'console'
          ? ['console']
          : ['africastalking', 'brevo'];

  for (const provider of providersInOrder) {
    if (provider === 'brevo') {
      try {
        const brevoResult = await sendOtpViaBrevo({ uid, phone, otp });
        attempts.push(brevoResult);
        if (brevoResult.ok) {
          return { provider: 'brevo', attempts };
        }
      } catch (error) {
        attempts.push({
          ok: false,
          provider: 'brevo',
          error: error?.message || String(error),
        });
        console.warn('[BREVO SMS ERROR]', error?.message || error);
      }
      continue;
    }

    if (provider === 'africastalking') {
      try {
        const africaTalkingResult = await sendOtpViaAfricaTalking({ uid, phone, otp });
        attempts.push(africaTalkingResult);
        if (africaTalkingResult.ok) {
          return { provider: 'africastalking', attempts };
        }
      } catch (error) {
        attempts.push({
          ok: false,
          provider: 'africastalking',
          error: error?.message || String(error),
        });
        console.warn('[AFRICASTALKING SMS ERROR]', error?.message || error);
      }
      continue;
    }

    if (provider === 'console') {
      console.log(`[DEV OTP] uid=${uid} phone=${phone} otp=${otp}`);
      return {
        provider: 'console',
        attempts: [
          ...attempts,
          {
            ok: true,
            provider: 'console',
          },
        ],
      };
    }
  }

  if (!atSms && !hasBrevoSms) {
    console.log(`[DEV OTP] uid=${uid} phone=${phone} otp=${otp}`);
    return {
      provider: 'console',
      attempts: [
        ...attempts,
        {
          ok: true,
          provider: 'console',
        },
      ],
    };
  }

  const error = new Error('All OTP delivery providers failed.');
  error.attempts = attempts;
  throw error;
}

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;

if (!process.env.CLOUDINARY_CLOUD_NAME || !process.env.CLOUDINARY_API_KEY || !process.env.CLOUDINARY_API_SECRET) {
  console.warn('Warning: CLOUDINARY env vars not set. See .env.example');
}

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

// Initialize Stripe if key is provided
let stripe = null;
if (process.env.STRIPE_SECRET_KEY) {
  try {
    stripe = Stripe(process.env.STRIPE_SECRET_KEY);
  } catch (err) {
    console.warn('Stripe init failed:', err.message);
    stripe = null;
  }
} else {
  console.warn('STRIPE_SECRET_KEY not set. Stripe endpoints will be disabled.');
}

// Initialize Firebase Admin if credentials provided via env
let firestore = null;
let adminMessaging = null;
if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  try {
    const serviceAccount = normalizeServiceAccount(
      JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)
    );
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    firestore = admin.firestore();
    adminMessaging = admin.messaging();
    console.log('Firebase Admin initialized from JSON env var');
  } catch (err) {
    console.warn('Failed to init Firebase Admin from JSON:', err.message || err);
  }
} else if (process.env.FIREBASE_SERVICE_ACCOUNT_PATH && fs.existsSync(process.env.FIREBASE_SERVICE_ACCOUNT_PATH)) {
  try {
    const serviceAccount = normalizeServiceAccount(
      require(process.env.FIREBASE_SERVICE_ACCOUNT_PATH)
    );
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    firestore = admin.firestore();
    adminMessaging = admin.messaging();
    console.log('Firebase Admin initialized from file:', process.env.FIREBASE_SERVICE_ACCOUNT_PATH);
  } catch (err) {
    console.warn('Failed to init Firebase Admin from path:', err.message || err);
  }
} else {
  console.log('Firebase Admin not configured (no service account provided).');
}

async function setOtpForUser({ uid, phone }) {
  if (!firestore) throw new Error('Firestore not configured on server');

  const normalized = normalizePhone(phone);
  if (!normalized) throw new Error('Invalid phone number');

  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  const salt = crypto.randomBytes(12).toString('hex');
  const hash = crypto.createHash('sha256').update(salt + otp).digest('hex');
  const ttlMs = Number(process.env.OTP_TTL_MS || 10 * 60 * 1000);
  const expiresAt = Date.now() + ttlMs;

  await firestore.collection('users').doc(uid).set(
    {
      isVerified: false,
    },
    { merge: true }
  );

  await firestore.collection('users').doc(uid).collection('private').doc('account').set(
    {
      phone: normalized,
      otpHash: hash,
      otpSalt: salt,
      otpExpiresAt: admin.firestore.Timestamp.fromMillis(expiresAt),
    },
    { merge: true }
  );

  console.log(
    `[OTP GENERATED] uid=${uid} phone=${normalized} otp=${otp} expiresAt=${new Date(expiresAt).toISOString()} ttlSeconds=${Math.round(ttlMs / 1000)}`
  );

  const delivery = await sendOtpMessage({
    uid,
    phone: normalized,
    otp,
  });
  console.log(
    '[OTP DELIVERY RESULT]',
    JSON.stringify(
      {
        uid,
        phone: normalized,
        provider: delivery.provider,
        attempts: delivery.attempts,
      },
      null,
      2
    )
  );

  return { normalized, sentAt: new Date().toISOString() };
}

async function getPhoneAccount(normalizedPhone) {
  if (!firestore) throw new Error('Firestore not configured on server');
  if (!normalizedPhone) return null;

  const phoneIndexDoc = await firestore.collection('phone_index').doc(normalizedPhone).get();
  if (!phoneIndexDoc.exists) return null;

  const phoneIndex = phoneIndexDoc.data() || {};
  const uid = phoneIndex.uid;
  if (!uid) return null;

  const [userDoc, privateDoc] = await Promise.all([
    firestore.collection('users').doc(uid).get(),
    firestore.collection('users').doc(uid).collection('private').doc('account').get(),
  ]);

  return {
    uid,
    publicData: userDoc.exists ? userDoc.data() || {} : {},
    privateData: privateDoc.exists ? privateDoc.data() || {} : {},
    phoneIndex,
  };
}

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.get('/debug/brevo-sms-events', async (req, res) => {
  try {
    if (!hasBrevoSms) {
      return res.status(500).json({ error: 'Brevo SMS not configured' });
    }

    const params = new URLSearchParams();
    params.set('sort', String(req.query.sort || 'desc'));
    params.set('limit', String(req.query.limit || 20));
    params.set('offset', String(req.query.offset || 0));
    if (req.query.days) params.set('days', String(req.query.days));
    if (req.query.startDate) params.set('startDate', String(req.query.startDate));
    if (req.query.endDate) params.set('endDate', String(req.query.endDate));
    if (req.query.tag) params.set('tag', String(req.query.tag));
    if (req.query.event) params.set('event', String(req.query.event));
    if (req.query.phoneNumber) {
      params.set('phoneNumber', String(req.query.phoneNumber).replace(/^\+/, ''));
    }

    const response = await getJson(
      `https://api.brevo.com/v3/transactionalSMS/statistics/events?${params.toString()}`,
      {
        'api-key': process.env.BREVO_API_KEY.trim(),
      }
    );

    return res.status(response.statusCode).json({
      ok: response.statusCode >= 200 && response.statusCode < 300,
      statusCode: response.statusCode,
      data: response.body,
    });
  } catch (err) {
    console.error('debug/brevo-sms-events error', err);
    return res.status(500).json({ error: err.message || 'Failed to fetch Brevo SMS events' });
  }
});

app.post('/auth/register-phone', async (req, res) => {
  try {
    if (!firestore) return res.status(500).json({ error: 'Firestore not configured on server' });

    const { fullName, phone, password } = req.body || {};
    const normalizedPhone = normalizePhone(phone);
    const passwordError = validatePassword(password);

    if (!normalizedPhone) return res.status(400).json({ error: 'A valid phone number is required' });
    if (passwordError) return res.status(400).json({ error: passwordError });

    const existing = await firestore.collection('phone_index').doc(normalizedPhone).get();
    if (existing.exists) {
      return res.status(409).json({ error: 'This phone number is already registered' });
    }

    const userRecord = await admin.auth().createUser({
      displayName: String(fullName || '').trim() || 'Member',
    });

    const { salt, hash } = createPasswordHash(password);
    const publicProfile = {
      uid: userRecord.uid,
      fullName: String(fullName || '').trim() || 'Member',
      isVerified: false,
      isPremium: false,
      isOnline: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const privateAccount = {
      phone: normalizedPhone,
      passwordSalt: salt,
      passwordHash: hash,
      authProvider: 'phone_password',
      passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const batch = firestore.batch();
    batch.set(firestore.collection('users').doc(userRecord.uid), publicProfile, { merge: true });
    batch.set(
      firestore.collection('users').doc(userRecord.uid).collection('private').doc('account'),
      privateAccount,
      { merge: true }
    );
    batch.set(
      firestore.collection('phone_index').doc(normalizedPhone),
      {
        uid: userRecord.uid,
        authProvider: 'phone_password',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await batch.commit();

    const customToken = await admin.auth().createCustomToken(userRecord.uid);
    return res.status(201).json({
      uid: userRecord.uid,
      customToken,
      phone: normalizedPhone,
      fullName: publicProfile.fullName,
      isVerified: false,
    });
  } catch (err) {
    console.error('register-phone error', err);
    return res.status(500).json({ error: err.message || String(err) });
  }
});

app.post('/auth/login-phone', async (req, res) => {
  try {
    if (!firestore) return res.status(500).json({ error: 'Firestore not configured on server' });

    const { phone, password } = req.body || {};
    const normalizedPhone = normalizePhone(phone);
    if (!normalizedPhone || !password) {
      return res.status(400).json({ error: 'Phone and password are required' });
    }

    const account = await getPhoneAccount(normalizedPhone);
    if (!account) return res.status(404).json({ error: 'No account found for this phone number' });

    const privateData = account.privateData || {};
    if (!privateData.passwordHash || !privateData.passwordSalt) {
      return res.status(400).json({ error: 'This account does not support phone-password login yet' });
    }

    const valid = verifyPassword(password, privateData.passwordSalt, privateData.passwordHash);
    if (!valid) return res.status(401).json({ error: 'Invalid phone number or password' });

    const customToken = await admin.auth().createCustomToken(account.uid);
    return res.json({
      uid: account.uid,
      customToken,
      phone: normalizedPhone,
      fullName: account.publicData.fullName || 'Member',
      isVerified: account.publicData.isVerified === true,
    });
  } catch (err) {
    console.error('login-phone error', err);
    return res.status(500).json({ error: err.message || String(err) });
  }
});

app.post('/auth/request-password-reset', async (req, res) => {
  try {
    const { phone } = req.body || {};
    const normalizedPhone = normalizePhone(phone);
    if (!normalizedPhone) return res.status(400).json({ error: 'A valid phone number is required' });

    const account = await getPhoneAccount(normalizedPhone);
    if (!account) return res.status(404).json({ error: 'No account found for this phone number' });

    const result = await setOtpForUser({ uid: account.uid, phone: normalizedPhone });
    return res.json({ success: true, uid: account.uid, phone: normalizedPhone, sentAt: result.sentAt });
  } catch (err) {
    console.error('request-password-reset error', err);
    return res.status(500).json({ error: err.message || String(err) });
  }
});

app.post('/auth/reset-password', async (req, res) => {
  try {
    if (!firestore) return res.status(500).json({ error: 'Firestore not configured on server' });

    const { phone, code, newPassword } = req.body || {};
    const normalizedPhone = normalizePhone(phone);
    const passwordError = validatePassword(newPassword);

    if (!normalizedPhone) return res.status(400).json({ error: 'A valid phone number is required' });
    if (!code) return res.status(400).json({ error: 'Verification code is required' });
    if (passwordError) return res.status(400).json({ error: passwordError });

    const account = await getPhoneAccount(normalizedPhone);
    if (!account) return res.status(404).json({ error: 'No account found for this phone number' });

    const privateData = account.privateData || {};
    const { otpHash, otpSalt, otpExpiresAt } = privateData;
    if (!otpHash || !otpSalt || !otpExpiresAt) {
      return res.status(400).json({ error: 'No OTP available for this account' });
    }

    const expires = otpExpiresAt.toMillis ? otpExpiresAt.toMillis() : Number(otpExpiresAt);
    if (Date.now() > expires) return res.status(400).json({ error: 'OTP expired' });

    const computed = crypto.createHash('sha256').update(otpSalt + String(code)).digest('hex');
    if (computed !== otpHash) return res.status(400).json({ error: 'Invalid code' });

    const { salt, hash } = createPasswordHash(newPassword);
    await firestore.collection('users').doc(account.uid).collection('private').doc('account').set(
      {
        passwordSalt: salt,
        passwordHash: hash,
        passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        otpHash: admin.firestore.FieldValue.delete(),
        otpSalt: admin.firestore.FieldValue.delete(),
        otpExpiresAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );

    return res.json({ success: true });
  } catch (err) {
    console.error('reset-password error', err);
    return res.status(500).json({ error: err.message || String(err) });
  }
});

// Sign upload parameters for client-side signed uploads
app.post('/sign', (req, res) => {
  try {
    const { public_id, folder, eager } = req.body || {};
    const timestamp = Math.floor(Date.now() / 1000);
    const paramsToSign = { timestamp };
    if (folder) paramsToSign.folder = folder;
    if (public_id) paramsToSign.public_id = public_id;
    if (eager) paramsToSign.eager = eager;

    // Build the string to sign (keys sorted lexicographically)
    const toSign = Object.keys(paramsToSign)
      .sort()
      .map((k) => `${k}=${paramsToSign[k]}`)
      .join('&');

    const signature = crypto
      .createHash('sha1')
      .update(toSign + (process.env.CLOUDINARY_API_SECRET || ''))
      .digest('hex');

    res.json({
      signature,
      timestamp,
      api_key: process.env.CLOUDINARY_API_KEY,
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    });
  } catch (err) {
    console.error('Sign error', err);
    res.status(500).json({ error: err.message });
  }
});

// Optional: delete an asset by public_id (requires API secret). Use with caution.
app.post('/delete', async (req, res) => {
  try {
    const { public_id, resource_type = 'image' } = req.body || {};
    if (!public_id) return res.status(400).json({ error: 'public_id required' });

    const result = await cloudinary.uploader.destroy(public_id, { resource_type });
    res.json(result);
  } catch (err) {
    console.error('Delete error', err);
    res.status(500).json({ error: err.message });
  }
});

// Create a Stripe PaymentIntent (minimal implementation)
app.post('/create-payment-intent', async (req, res) => {
  if (!stripe) return res.status(500).json({ error: 'Stripe not configured' });

  try {
    const { amount, currency = 'usd', metadata = {} } = req.body || {};

    if (!amount || isNaN(amount) || Number(amount) <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    // Stripe expects amount in cents (integer)
    const amountInt = Math.round(Number(amount));

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInt,
      currency,
      metadata,
      automatic_payment_methods: { enabled: true },
    });

    res.json({ clientSecret: paymentIntent.client_secret, id: paymentIntent.id });
  } catch (err) {
    console.error('PaymentIntent error', err);
    res.status(500).json({ error: err.message });
  }
});

// Stripe webhook endpoint for production-ready payment confirmation.
// This verifies Stripe signatures and performs the same post-payment
// tasks as the mock endpoint: audit log, set `isPremium`, and send FCM.
app.post('/stripe-webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  if (!stripe) return res.status(400).send('Stripe not configured');
  if (!process.env.STRIPE_WEBHOOK_SECRET) return res.status(400).send('Webhook secret not configured');

  const sig = req.headers['stripe-signature'];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('Stripe webhook signature verification failed:', err.message || err);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  // Handle relevant event types
  try {
    const type = event.type;
    const obj = event.data.object || {};

    // Determine a userId from metadata if the client provided it when creating
    // the PaymentIntent / Checkout Session. Fallbacks are defensive — production
    // integrations should ensure `metadata.userId` is set.
    const metadata = obj.metadata || {};
    const userId = metadata.userId || metadata.uid || null;
    const plan = metadata.plan || 'premium';
    const amount = obj.amount || obj.amount_total || 0;
    const paymentId = event.id || (obj.id || `stripe_${Date.now()}`);

    if (type === 'payment_intent.succeeded' || type === 'checkout.session.completed' || type === 'charge.succeeded') {
      if (firestore) {
        try {
          await firestore.collection('premium_payments').doc(paymentId).set({
            stripeEvent: type,
            paymentId: paymentId,
            userId: userId || null,
            plan,
            amount,
            raw: obj,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            source: 'stripe',
          });
          console.log('Stripe audit log created for', paymentId);
        } catch (err) {
          console.error('Failed to write stripe audit log:', err);
        }

        if (userId) {
          try {
            await applyPurchasedEntitlement({ userId, plan });
            console.log('User entitlement updated via Stripe webhook:', userId, plan);
          } catch (err) {
            console.error('Failed to update user entitlement from webhook:', err);
          }
        }
      }

      // Send FCM notification (admin SDK preferred)
      if (adminMessaging) {
        try {
          const message = {
            topic: 'premium-updates',
            notification: {
              title: purchaseNotificationTitle(plan),
              body: purchaseNotificationBody({ userId, plan }),
            },
            data: { userId: userId || '', plan: plan, amount: String(amount) },
          };
          const resp = await adminMessaging.send(message);
          console.log('Admin FCM sent (webhook):', resp);
        } catch (err) {
          console.error('Failed to send admin FCM from webhook:', err);
        }
      } else if (process.env.FCM_SERVER_KEY) {
        try {
          const payload = JSON.stringify({
            to: '/topics/premium-updates',
            notification: {
              title: purchaseNotificationTitle(plan),
              body: purchaseNotificationBody({ userId, plan }),
            },
            data: { userId: userId || '', plan: plan, amount: String(amount) },
          });

          const options = {
            hostname: 'fcm.googleapis.com',
            path: '/fcm/send',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `key=${process.env.FCM_SERVER_KEY}`,
              'Content-Length': Buffer.byteLength(payload),
            },
          };

          const reqFcm = https.request(options, (fcmRes) => {
            let data = '';
            fcmRes.on('data', (chunk) => (data += chunk));
            fcmRes.on('end', () => console.log('FCM response (webhook):', data));
          });

          reqFcm.on('error', (err) => console.error('FCM send error (webhook)', err));
          reqFcm.write(payload);
          reqFcm.end();
        } catch (err) {
          console.error('Failed to send fallback FCM from webhook:', err);
        }
      }
    }

    // Acknowledge receipt
    res.json({ received: true });
  } catch (err) {
    console.error('Error processing stripe webhook:', err);
    try { monitoring.alertWebhookFailure({ error: String(err), event: (event && event.type) || null }); } catch (_) {}
    res.status(500).send('Webhook handler error');
  }
});

// Insecure test endpoint to simulate webhook events locally when
// STRIPE_WEBHOOK_SECRET is not available. Enabled only when
// DEV_ALLOW_INSECURE_WEBHOOKS env var is set to 'true'.
app.post('/stripe-webhook-test', async (req, res) => {
  if (process.env.DEV_ALLOW_INSECURE_WEBHOOKS !== 'true') {
    return res.status(403).json({ error: 'Insecure webhook testing disabled' });
  }

  const event = req.body || {};
  // Reuse the same processing logic as the verified handler by
  // constructing a minimal event shape expected by the handler.
  try {
    const fakeEvent = { type: event.type || 'payment_intent.succeeded', data: { object: event.data || event }, id: `test_${Date.now()}` };
    // Call the same processing block by emulating the request handling
    // (duplicate minimal logic to avoid pulling out a common function).
    const type = fakeEvent.type;
    const obj = fakeEvent.data.object || {};
    const metadata = obj.metadata || {};
    const userId = metadata.userId || metadata.uid || null;
    const plan = metadata.plan || 'premium';
    const amount = obj.amount || obj.amount_total || 0;
    const paymentId = fakeEvent.id || (obj.id || `stripe_test_${Date.now()}`);

    if (type === 'payment_intent.succeeded' || type === 'checkout.session.completed' || type === 'charge.succeeded') {
      if (firestore) {
        try {
          await firestore.collection('premium_payments').doc(paymentId).set({
            stripeEvent: type,
            paymentId: paymentId,
            userId: userId || null,
            plan,
            amount,
            raw: obj,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            source: 'stripe_test',
          });
        } catch (err) {
          console.error('Test webhook: failed to write audit log', err);
        }

        if (userId) {
          try {
            await applyPurchasedEntitlement({ userId, plan });
          } catch (err) {
            console.error('Test webhook: failed to update user', err);
          }
        }
      }

      if (adminMessaging) {
        try {
          const message = {
            topic: 'premium-updates',
            notification: {
              title: `${purchaseNotificationTitle(plan)} (test)`,
              body: purchaseNotificationBody({ userId, plan }),
            },
            data: { userId: userId || '', plan: plan, amount: String(amount) },
          };
          await adminMessaging.send(message);
        } catch (err) {
          console.error('Test webhook: failed to send FCM', err);
        }
      }
    }

    res.json({ received: true, test: true });
  } catch (err) {
    console.error('Test webhook handler error', err);
    res.status(500).json({ error: 'test webhook handler error' });
  }
});

// Mock payment endpoint for testing without Stripe integration
app.post('/mock-payment-success', (req, res) => {
  const { userId, plan = 'premium', amount = 0 } = req.body || {};
  const paymentId = `mock_${Date.now()}`;

  // Return a simulated payment success payload
  res.json({
    status: 'succeeded',
    id: paymentId,
    userId,
    plan,
    amount,
    timestamp: Date.now(),
  });

  // Post-payment background tasks: update Firestore, write audit log, and send FCM via Admin SDK when available
  (async () => {
    try {
      if (firestore) {
        // Audit log
        try {
          await firestore.collection('premium_payments').doc(paymentId).set({
            userId: userId || null,
            plan,
            amount,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            source: 'mock',
          });
          console.log('Audit log created for payment', paymentId);
        } catch (err) {
          console.error('Failed to create audit log:', err);
        }

        if (userId) {
          try {
            const userRef = firestore.collection('users').doc(userId);
            await applyPurchasedEntitlement({ userId, plan });
            console.log('Firestore updated for user', userId, plan);
          } catch (err) {
            console.error('Failed to update user entitlement:', err);
          }
        }
      }

      if (adminMessaging) {
        const message = {
          topic: 'premium-updates',
          notification: {
            title: purchaseNotificationTitle(plan),
            body: purchaseNotificationBody({ userId, plan }),
          },
          data: { userId: userId || '', plan: plan, amount: String(amount) },
        };
        const resp = await adminMessaging.send(message);
        console.log('Admin FCM sent:', resp);
      } else if (process.env.FCM_SERVER_KEY) {
        // fallback to raw FCM HTTP API if admin SDK not configured
        try {
          const payload = JSON.stringify({
            to: '/topics/premium-updates',
            notification: {
              title: purchaseNotificationTitle(plan),
              body: purchaseNotificationBody({ userId, plan }),
            },
            data: { userId: userId || '', plan: plan, amount: String(amount) },
          });

          const options = {
            hostname: 'fcm.googleapis.com',
            path: '/fcm/send',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `key=${process.env.FCM_SERVER_KEY}`,
              'Content-Length': Buffer.byteLength(payload),
            },
          };

          const reqFcm = https.request(options, (fcmRes) => {
            let data = '';
            fcmRes.on('data', (chunk) => (data += chunk));
            fcmRes.on('end', () => {
              console.log('FCM response:', data);
            });
          });

          reqFcm.on('error', (err) => console.error('FCM send error', err));
          reqFcm.write(payload);
          reqFcm.end();
        } catch (err) {
          console.error('Failed to send FCM notification (fallback)', err);
        }
      }
    } catch (err) {
      console.error('Post-payment background task failed:', err);
    }
  })();
});

// Simple server-side upload proxy (fallback) accepting base64 payloads.
app.post('/upload-proxy', async (req, res) => {
  try {
    const { fileBase64, folder } = req.body || {};
    if (!fileBase64) return res.status(400).json({ error: 'fileBase64 is required' });

    // Cloudinary accepts data URIs (data:<mime>;base64,<data>) or raw base64 string.
    const uploadResult = await cloudinary.uploader.upload(fileBase64, { folder: folder || 'uploads' });
    return res.json(uploadResult);
  } catch (err) {
    console.error('Proxy upload error', err);
    return res.status(500).json({ error: err.message || String(err) });
  }
});

// Expose minimal Stripe config for clients (publishable key only)
app.get('/stripe-config', (req, res) => {
  res.json({
    publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || null,
    stripeEnabled: !!process.env.STRIPE_SECRET_KEY,
  });
});

// Matches endpoint (basic implementation). Returns mock data when Firestore
// admin SDK is not configured locally to allow frontend development.
app.post('/matches', async (req, res) => {
  try {
    console.log('[matches] incoming', { time: new Date().toISOString(), ip: req.ip, headers: { authorization: req.headers.authorization ? 'present' : 'missing' }, body: req.body });
    if (!firestore) {
      // Return mocked matches for development when Firestore admin not available.
      const items = [
        {
          uid: 'm1',
          profile: {
            fullName: 'Aisha',
            age: 27,
            occupation: 'Product Designer',
            locationLabel: 'Lahore, Pakistan',
            profilePictureUrl: null,
          },
          score: 85,
        },
        {
          uid: 'm2',
          profile: {
            fullName: 'Bilal',
            age: 30,
            occupation: 'Software Engineer',
            locationLabel: 'Karachi, Pakistan',
            profilePictureUrl: null,
          },
          score: 78,
        },
      ];
      return res.json({ total: items.length, items, nextPageToken: null });
    }

    // Basic authenticated flow: verify token if present
    let callerUid = null;
    const authHeader = req.headers.authorization || req.headers.Authorization;
    if (authHeader && typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
      const idToken = authHeader.split('Bearer ')[1].trim();
      try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        callerUid = decoded.uid;
      } catch (err) {
        console.warn('verifyIdToken failed', err && err.message ? err.message : err);
      }
    }

    // Simple query: return up to 20 users excluding caller
    const filters = (req.body && req.body.filters) || {};
    const pageSize = Math.min(Number(req.body && req.body.pageSize) || 20, 100);

    const snap = await firestore.collection('users').limit(100).get();
    const docs = snap.docs || [];
    const items = [];

    // Parse filters from request
    const f = (req.body && req.body.filters) || {};
    const minAge = f.minAge != null ? Number(f.minAge) : null;
    const maxAge = f.maxAge != null ? Number(f.maxAge) : null;
    const minHeight = f.minHeight != null ? Number(f.minHeight) : null;
    const maxHeight = f.maxHeight != null ? Number(f.maxHeight) : null;
    const religionFilter = f.religion || null;
    const locationFilter = f.location || null; // { lat: <num>, lng: <num>, radiusKm: <num> }

    const haversineKm = (lat1, lon1, lat2, lon2) => {
      if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return null;
      const toRad = (deg) => (deg * Math.PI) / 180;
      const R = 6371; // km
      const dLat = toRad(lat2 - lat1);
      const dLon = toRad(lon2 - lon1);
      const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      return R * c;
    };

    const requiredFields = ['fullName', 'age', 'bio', 'profilePictureUrl', 'location'];

    for (const d of docs) {
      if (d.id === callerUid) continue;
      const p = d.data() || {};

      // Apply simple filters (exclude if mismatch)
      if (minAge != null && (p.age == null || Number(p.age) < minAge)) continue;
      if (maxAge != null && (p.age == null || Number(p.age) > maxAge)) continue;
      if (minHeight != null && (p.height == null || Number(p.height) < minHeight)) continue;
      if (maxHeight != null && (p.height == null || Number(p.height) > maxHeight)) continue;
      if (religionFilter != null && p.religion != null && String(p.religion).toLowerCase() !== String(religionFilter).toLowerCase()) continue;

      // Location radius filter
      if (locationFilter && locationFilter.lat != null && locationFilter.lng != null && locationFilter.radiusKm != null) {
        const userLoc = p.location || p.homeLocation || null;
        const dist = userLoc ? haversineKm(locationFilter.lat, locationFilter.lng, Number(userLoc.lat), Number(userLoc.lng)) : null;
        if (dist == null || dist > Number(locationFilter.radiusKm)) continue;
      }

      // Compute heuristic score (0..100)
      let score = 40;
      if (p.profilePictureUrl) score += 20;

      // completeness
      let present = 0;
      for (const k of requiredFields) {
        if (p[k] != null) present += 1;
      }
      const completeness = present / requiredFields.length; // 0..1
      score += Math.round(15 * completeness);

      // premium boost
      if (p.isPremium) score += 10;

      const boostExpiresAt = p.boostExpiresAt;
      const boostMs =
        boostExpiresAt && typeof boostExpiresAt.toMillis === 'function'
          ? boostExpiresAt.toMillis()
          : 0;
      if (boostMs > Date.now()) score += 18;

      // Age closeness bonus if filter range provided
      if (minAge != null && maxAge != null && p.age != null) {
        const mid = (minAge + maxAge) / 2;
        const halfRange = Math.max(1, (maxAge - minAge) / 2);
        const dist = Math.abs(Number(p.age) - mid);
        const ageBonus = Math.max(0, 10 * (1 - dist / halfRange));
        score += Math.round(ageBonus);
      }

      // Height closeness small bonus
      if (minHeight != null && maxHeight != null && p.height != null) {
        const mid = (minHeight + maxHeight) / 2;
        const halfRange = Math.max(1, (maxHeight - minHeight) / 2);
        const dist = Math.abs(Number(p.height) - mid);
        const heightBonus = Math.max(0, 5 * (1 - dist / halfRange));
        score += Math.round(heightBonus);
      }

      // Religion match bonus (if filter provided)
      if (religionFilter != null && p.religion != null && String(p.religion).toLowerCase() === String(religionFilter).toLowerCase()) {
        score += 5;
      }

      // Location proximity bonus
      if (locationFilter && locationFilter.lat != null && locationFilter.lng != null && p.location) {
        const userLoc = p.location;
        const dist = haversineKm(locationFilter.lat, locationFilter.lng, Number(userLoc.lat), Number(userLoc.lng));
        if (dist != null && locationFilter.radiusKm != null) {
          const proximity = Math.max(0, 1 - dist / Number(locationFilter.radiusKm));
          score += Math.round(10 * proximity);
        }
      }

      // Recent activity bonus
      if (p.lastActive) {
        try {
          const last = p.lastActive.toDate ? p.lastActive.toDate() : new Date(p.lastActive);
          const ageMs = Date.now() - last.getTime();
          const days = ageMs / (1000 * 60 * 60 * 24);
          if (days <= 7) score += 5;
        } catch (e) {}
      }

      // Clamp
      score = Math.max(0, Math.min(100, Math.round(score)));

      const locationLabel = [
        p.location && p.location.city ? p.location.city : null,
        p.location && p.location.country ? p.location.country : null,
      ]
        .filter(Boolean)
        .join(', ');

      items.push({
        uid: d.id,
        profile: {
          fullName: p.fullName || null,
          age: p.age || null,
          occupation: p.occupation || null,
          locationLabel: locationLabel || null,
          profilePictureUrl: p.profilePictureUrl || null,
        },
        score,
      });
      if (items.length >= pageSize) break;
    }

    return res.json({ total: items.length, items, nextPageToken: null });
  } catch (err) {
    console.error('Matches handler failed', err);
    return res.status(500).json({ error: 'Matches handler failed', details: String(err) });
  }
});

app.listen(PORT, () => {
  console.log(`Cloudinary signer running on port ${PORT}`);
});

// OTP endpoints (custom server-side OTP flow)
// POST /send-otp { uid, phone }
app.post('/send-otp', async (req, res) => {
  try {
    const { uid, phone } = req.body || {};
    if (!uid || !phone) return res.status(400).json({ error: 'uid and phone are required' });
    const result = await setOtpForUser({ uid, phone });
    return res.json({ success: true, sentAt: result.sentAt, phone: result.normalized });
  } catch (err) {
    console.error('send-otp error', err);
    const resp = { error: String(err) };
    if (err && err.attempts) resp.attempts = err.attempts;
    return res.status(500).json(resp);
  }
});

// POST /verify-otp { uid, code }
app.post('/verify-otp', async (req, res) => {
  try {
    if (!firestore) return res.status(500).json({ error: 'Firestore not configured on server' });
    const { uid, code } = req.body || {};
    if (!uid || !code) return res.status(400).json({ error: 'uid and code are required' });

    const privateDoc = await firestore.collection('users').doc(uid).collection('private').doc('account').get();
    if (!privateDoc.exists) return res.status(404).json({ error: 'User not found' });
    const data = privateDoc.data() || {};
    const { otpHash, otpSalt, otpExpiresAt } = data;
    if (!otpHash || !otpSalt || !otpExpiresAt) return res.status(400).json({ error: 'No OTP available for this user' });

    const expires = otpExpiresAt.toMillis ? otpExpiresAt.toMillis() : (otpExpiresAt._seconds ? otpExpiresAt._seconds * 1000 : Number(otpExpiresAt));
    if (Date.now() > expires) return res.status(400).json({ error: 'OTP expired' });

    const computed = crypto.createHash('sha256').update(otpSalt + String(code)).digest('hex');
    if (computed !== otpHash) return res.status(400).json({ error: 'Invalid code' });

    // Mark number verified and remove OTP fields
    const batch = firestore.batch();
    batch.set(
      firestore.collection('users').doc(uid),
      {
        isVerified: true,
      },
      { merge: true }
    );
    batch.set(
      firestore.collection('users').doc(uid).collection('private').doc('account'),
      {
        otpHash: admin.firestore.FieldValue.delete(),
        otpSalt: admin.firestore.FieldValue.delete(),
        otpExpiresAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );
    await batch.commit();

    return res.json({ success: true });
  } catch (err) {
    console.error('verify-otp error', err);
    return res.status(500).json({ error: String(err) });
  }
});
