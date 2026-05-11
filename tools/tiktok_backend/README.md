TikTok Backend Sample
=====================

This folder contains a minimal Node.js example that exchanges a TikTok OAuth
authorization code for an access token and mints a Firebase Custom Token using
the Firebase Admin SDK. Use this as a starting point for your secure backend.

Environment variables required:

- `TIKTOK_CLIENT_KEY` — your TikTok app client key
- `TIKTOK_CLIENT_SECRET` — your TikTok app client secret
- `TIKTOK_REDIRECT_URI` — the redirect URI used in the OAuth flow
- `GOOGLE_APPLICATION_CREDENTIALS` — path to your Firebase service account JSON

Run locally:

```bash
cd tools/tiktok_backend
npm install
export TIKTOK_CLIENT_KEY=... \
  TIKTOK_CLIENT_SECRET=... \
  TIKTOK_REDIRECT_URI=your.app://auth \
  GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
npm start
```

Notes:

- This sample is intentionally minimal. In production, secure the endpoint,
  validate inputs, and store secrets safely (e.g., environment variables, vault).
- TikTok API endpoints and response shapes may change; consult TikTok's
  developer docs when implementing the exchange.
