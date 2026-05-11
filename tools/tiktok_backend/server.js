const express = require('express');
const axios = require('axios');
const admin = require('firebase-admin');
const bodyParser = require('body-parser');

// This sample shows a simple exchange endpoint. For production, secure this
// endpoint (authentication, rate-limiting, input validation) and keep
// client secrets out of source control (use environment variables).

const TIKTOK_CLIENT_KEY = process.env.TIKTOK_CLIENT_KEY;
const TIKTOK_CLIENT_SECRET = process.env.TIKTOK_CLIENT_SECRET;
const TIKTOK_REDIRECT_URI = process.env.TIKTOK_REDIRECT_URI;

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.warn('Set GOOGLE_APPLICATION_CREDENTIALS to your Firebase service account JSON path');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const app = express();
app.use(bodyParser.json());

app.post('/tiktok/exchange', async (req, res) => {
  try {
    const { code } = req.body;
    if (!code) return res.status(400).json({ error: 'Missing code' });

    // Exchange the authorization code for an access token (TikTok API may
    // have specific endpoint variations; check the current TikTok docs).
    const tokenResp = await axios.post('https://open-api.tiktok.com/platform/oauth/access_token/', {
      client_key: TIKTOK_CLIENT_KEY,
      client_secret: TIKTOK_CLIENT_SECRET,
      code: code,
      grant_type: 'authorization_code',
      redirect_uri: TIKTOK_REDIRECT_URI,
    });

    // The response shape can vary; inspect tokenResp.data to find an id.
    const tiktokUserId = tokenResp.data?.data?.open_id || tokenResp.data?.open_id;
    if (!tiktokUserId) return res.status(500).json({ error: 'Could not extract TikTok user id' });

    // Create (or use) a stable Firebase uid based on TikTok id.
    const firebaseUid = `tiktok:${tiktokUserId}`;

    // Optionally create/update the user record here using admin.auth().getUser/createUser

    // Mint a Firebase custom token for the uid
    const customToken = await admin.auth().createCustomToken(firebaseUid);
    return res.json({ firebaseCustomToken: customToken });
  } catch (err) {
    console.error('Exchange error', err?.response?.data || err.message || err);
    return res.status(500).json({ error: 'Exchange failed', details: err?.response?.data || err.message });
  }
});

const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`TikTok backend sample running on ${port}`));
