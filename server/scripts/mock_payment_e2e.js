#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const http = require('http');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.existsSync(envPath)
  ? fs
      .readFileSync(envPath, 'utf8')
      .split(/\r?\n/)
      .filter(Boolean)
      .reduce((acc, line) => {
        const idx = line.indexOf('=');
        if (idx > 0) acc[line.slice(0, idx)] = line.slice(idx + 1);
        return acc;
      }, {})
  : {};

const PORT = env.PORT || 3000;
const userId = process.argv[2] || 'test-user';
const amount = process.argv[3] || 499;

const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
const serviceAccountPathResolved = path.resolve(
  path.join(__dirname, '..', env.FIREBASE_SERVICE_ACCOUNT_PATH || 'service-account.json')
);
if (!fs.existsSync(serviceAccountPathResolved)) {
  console.error('Service account file missing at', serviceAccountPathResolved);
  process.exit(2);
}
const serviceAccount = require(serviceAccountPathResolved);
try {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
} catch (e) {
  // ignore if already initialized
}
const firestore = admin.firestore();

function postMockPayment() {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ userId, plan: 'premium', amount });
    const options = {
      hostname: 'localhost',
      port: PORT,
      path: '/mock-payment-success',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function pollForPremium(timeoutMs = 20000, intervalMs = 1000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const doc = await firestore.collection('users').doc(userId).get();
    const data = doc.exists ? doc.data() : null;
    if (data && data.isPremium) {
      return data;
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error('Timed out waiting for isPremium=true');
}

(async () => {
  try {
    console.log('Posting mock payment for user', userId);
    const resp = await postMockPayment();
    console.log('Server responded', resp.status, resp.body);
    console.log('Polling Firestore for isPremium...');
    const data = await pollForPremium();
    console.log('Success: user isPremium detected:', data);
    process.exit(0);
  } catch (err) {
    console.error('Error:', err.message || err);
    process.exit(2);
  }
})();
