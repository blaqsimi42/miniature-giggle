const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize admin app using default credentials or service account provided in environment.
try {
  admin.initializeApp();
} catch (e) {
  // already initialized
}

const db = admin.firestore();

function normalizePhone(phone) {
  if (!phone) return null;
  let p = phone.toString().trim();
  // remove spaces, dashes, parens
  p = p.replace(/[\s\-()]/g, '');
  // ensure leading + if country code present, otherwise keep as-is
  if (!p.startsWith('+') && p.length > 8) {
    p = '+' + p;
  }
  return p;
}

// Trigger whenever a user's private/account doc is created, updated, or deleted.
// We maintain a phone_index collection mapping normalizedPhone -> { uid, authEmail, createdAt }
exports.syncPhoneIndex = functions.firestore
  .document('users/{uid}/private/account')
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    const beforePhone = before && before.phone ? normalizePhone(before.phone) : null;
    const afterPhone = after && after.phone ? normalizePhone(after.phone) : null;
    const authEmail = after && after.authEmail ? after.authEmail : (before && before.authEmail ? before.authEmail : null);

    try {
      // If phone removed, delete old mapping if it pointed to this uid
      if (beforePhone && beforePhone !== afterPhone) {
        const oldRef = db.collection('phone_index').doc(beforePhone);
        const oldDoc = await oldRef.get();
        if (oldDoc.exists) {
          const data = oldDoc.data();
          if (data && data.uid === uid) {
            await oldRef.delete();
          }
        }
      }

      // If new phone present, set mapping
      if (afterPhone) {
        const newRef = db.collection('phone_index').doc(afterPhone);
        await newRef.set({
          uid: uid,
          authEmail: authEmail || null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return null;
    } catch (err) {
      console.error('syncPhoneIndex error for uid=', uid, err);
      return null;
    }
  });
