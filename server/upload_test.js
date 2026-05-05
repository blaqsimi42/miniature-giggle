const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const fetch = global.fetch || require('node-fetch');
const cloudinary = require('cloudinary').v2;

async function run() {
  try {
    const signerUrl = 'http://localhost:3000/sign';
    const filePath = path.join(__dirname, '..', 'assets', 'images', '1.jpg');
    if (!fs.existsSync(filePath)) {
      console.error('Test image not found at', filePath);
      process.exit(1);
    }

    const signRes = await fetch(signerUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder: 'test_uploads' }),
    });
    const sign = await signRes.json();
    console.log('Signer response:', sign);

    if (!sign.signature || !sign.timestamp || !sign.api_key || !sign.cloud_name) {
      console.error('Invalid signer response, aborting.');
      process.exit(1);
    }

    const cloudName = sign.cloud_name;
    const uploadUrl = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;

    const FormData = global.FormData || require('form-data');
    const form = new FormData();
    form.append('file', fs.createReadStream(filePath));
    form.append('timestamp', String(sign.timestamp));
    form.append('signature', sign.signature);
    form.append('api_key', sign.api_key);
    form.append('folder', 'test_uploads');

    console.log('Uploading to Cloudinary...');

    const resp = await fetch(uploadUrl, { method: 'POST', body: form, headers: form.getHeaders ? form.getHeaders() : {} });
    let json;
    try {
      json = await resp.json();
    } catch (e) {
      console.warn('Failed to parse Cloudinary response as JSON:', e.message || e);
      json = null;
    }
    console.log('Cloudinary response:', json || `(status ${resp.status})`);

    if (!json || json.error || !json.secure_url) {
      console.warn('Signed upload failed or returned no secure_url — attempting server-side upload fallback using Cloudinary SDK...');
      try {
        if (!process.env.CLOUDINARY_API_KEY || !process.env.CLOUDINARY_API_SECRET || !process.env.CLOUDINARY_CLOUD_NAME) {
          console.error('Missing Cloudinary env vars in upload_test.js process. Please ensure .env is present in server/ with CLOUDINARY_* values.');
          process.exit(1);
        }
        cloudinary.config({
          cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
          api_key: process.env.CLOUDINARY_API_KEY,
          api_secret: process.env.CLOUDINARY_API_SECRET,
        });
        const sdkResp = await cloudinary.uploader.upload(filePath, { folder: 'test_uploads' });
        console.log('Server-side SDK upload result:', sdkResp);
      } catch (err) {
        console.error('Server-side SDK upload also failed:', err && err.message ? err.message : err);
        process.exit(1);
      }
    }
  } catch (err) {
    console.error('Upload test failed:', err);
    process.exit(1);
  }
}

run();
