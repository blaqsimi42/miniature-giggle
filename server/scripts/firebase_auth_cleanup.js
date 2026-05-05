const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');
const admin = require('firebase-admin');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      out[key] = true;
    } else {
      out[key] = next;
      i += 1;
    }
  }
  return out;
}

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

function syntheticAuthEmail(normalizedPhone) {
  return `${normalizedPhone.replaceAll('+', '')}@phone.qubool`;
}

function initAdmin() {
  if (admin.apps.length) return admin.app();

  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    return admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }

  const configuredPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './service-account.json';
  const resolvedPath = path.resolve(path.join(__dirname, '..'), configuredPath);
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Service account not found at ${resolvedPath}`);
  }
  const serviceAccount = require(resolvedPath);
  return admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

async function inspectPhone(normalizedPhone) {
  const db = admin.firestore();
  const auth = admin.auth();
  const authEmail = syntheticAuthEmail(normalizedPhone);

  let authUser = null;
  try {
    authUser = await auth.getUserByEmail(authEmail);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
  }

  const phoneIndexDoc = await db.collection('phone_index').doc(normalizedPhone).get();
  let profileUid = phoneIndexDoc.exists ? phoneIndexDoc.data()?.uid ?? null : null;

  let privateMatches = [];
  if (!profileUid) {
    const snap = await db
      .collectionGroup('private')
      .where('phone', '==', normalizedPhone)
      .get();
    privateMatches = snap.docs.map((doc) => ({
      path: doc.ref.path,
      uid: doc.ref.parent.parent ? doc.ref.parent.parent.id : null,
      data: doc.data(),
    }));
    if (privateMatches.length === 1) {
      profileUid = privateMatches[0].uid;
    }
  }

  let privateAccount = null;
  let publicProfile = null;
  if (profileUid) {
    const [publicDoc, privateDoc] = await Promise.all([
      db.collection('users').doc(profileUid).get(),
      db.collection('users').doc(profileUid).collection('private').doc('account').get(),
    ]);
    publicProfile = publicDoc.exists ? publicDoc.data() : null;
    privateAccount = privateDoc.exists ? privateDoc.data() : null;
  }

  return {
    normalizedPhone,
    authEmail,
    authUser: authUser
      ? {
          uid: authUser.uid,
          email: authUser.email,
          displayName: authUser.displayName,
          phoneNumber: authUser.phoneNumber,
          disabled: authUser.disabled,
        }
      : null,
    phoneIndex: phoneIndexDoc.exists ? phoneIndexDoc.data() : null,
    profileUid,
    publicProfile,
    privateAccount,
    privateMatches,
  };
}

async function deletePhoneData(summary) {
  const db = admin.firestore();
  const auth = admin.auth();
  const batch = db.batch();

  if (summary.phoneIndex) {
    batch.delete(db.collection('phone_index').doc(summary.normalizedPhone));
  }

  if (summary.profileUid) {
    batch.delete(db.collection('users').doc(summary.profileUid));
    batch.delete(
      db.collection('users').doc(summary.profileUid).collection('private').doc('account'),
    );
  }

  await batch.commit();

  if (summary.authUser?.uid) {
    await auth.deleteUser(summary.authUser.uid);
  }
}

async function main() {
  initAdmin();

  const args = parseArgs(process.argv.slice(2));
  const normalizedPhone = normalizePhone(args.phone);

  if (!normalizedPhone) {
    throw new Error(
      'Provide a phone number with --phone, for example: node scripts/firebase_auth_cleanup.js --phone +2348012345678',
    );
  }

  const summary = await inspectPhone(normalizedPhone);
  console.log(JSON.stringify(summary, null, 2));

  if (args.delete) {
    await deletePhoneData(summary);
    console.log(`Deleted auth/profile/index data for ${normalizedPhone}`);
  } else {
    console.log('Dry run only. Re-run with --delete to remove the auth user and related Firestore docs.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
