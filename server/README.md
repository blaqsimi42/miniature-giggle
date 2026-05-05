This is a minimal Cloudinary signing service for client-side signed uploads.

Usage

1. Copy `.env.example` to `.env` and set your Cloudinary credentials.

2. Install dependencies and start:

```bash
cd server
npm install
npm start
```

3. Sign request (example):

```bash
curl -X POST http://localhost:3000/sign \
  -H "Content-Type: application/json" \
  -d '{"folder":"matrimonial_app/profile_images/USERID"}'
```

Response:

```json
{
  "signature": "...",
  "timestamp": 168..., 
  "api_key": "your_api_key",
  "cloud_name": "your_cloud_name"
}
```

4. Client should include `timestamp` and `signature` fields (and optionally `folder`/`public_id`) when posting to Cloudinary API to perform a signed upload.

Security notes

- Never commit `.env` with secrets.
- Deploy this service to a trusted environment (Heroku, Vercel serverless function, Cloud Run, Firebase Functions, etc.).
- Use HTTPS in production.

Extending

- Add authentication so only your app can request signatures.
- Add rate-limits and logging.
- Implement server-side upload proxy if you prefer not to have the client post directly to Cloudinary.

Testing payments (mock)

- A mock payment endpoint is available for local testing without Stripe: `POST /mock-payment-success`.
- Example:

```bash
curl -X POST http://localhost:3000/mock-payment-success \
  -H "Content-Type: application/json" \
  -d '{"userId":"USER123","plan":"premium","amount":499}'
```

This returns a JSON payload similar to a real payment confirmation which you can use to exercise client-side premium unlock flows during development.
