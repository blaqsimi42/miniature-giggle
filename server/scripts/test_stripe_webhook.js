const http = require('http');
const payload = JSON.stringify({
  type: 'payment_intent.succeeded',
  data: {
    object: {
      id: 'pi_test_123',
      amount: 49900,
      metadata: { userId: process.argv[2] || 'test-user', plan: 'premium' }
    }
  }
});

const options = {
  hostname: 'localhost',
  port: process.env.PORT || 3000,
  path: '/stripe-webhook-test',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
  }
};

const req = http.request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => data += chunk);
  res.on('end', () => {
    console.log('Response status:', res.statusCode);
    console.log('Response body:', data);
  });
});

req.on('error', (e) => console.error('Request error', e));
req.write(payload);
req.end();
