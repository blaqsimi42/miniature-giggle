const request = require('supertest');
const child = require('child_process');
const path = require('path');

// Give Jest more time for starting the server in CI/slow hosts
jest.setTimeout(20000);

// Spawn the server as a child process for tests
const serverPath = path.resolve(__dirname, '..', 'index.js');
let serverProc;

beforeAll((done) => {
  // Start server with DEV_ALLOW_INSECURE_WEBHOOKS=true so /stripe-webhook-test is enabled
  serverProc = child.spawn('node', [serverPath], {
    env: { ...process.env, DEV_ALLOW_INSECURE_WEBHOOKS: 'true', PORT: '4000' },
    stdio: ['ignore', 'inherit', 'inherit'],
  });

  // give server a moment to start
  setTimeout(done, 2200);
});

afterAll(() => {
  if (serverProc) serverProc.kill();
});

test('stripe-webhook-test returns received true and sets up processing', async () => {
  const payload = {
    type: 'payment_intent.succeeded',
    data: { object: { id: 'pi_test_123', amount: 49900, metadata: { userId: 'test-user' } } }
  };

  const res = await request('http://localhost:4000')
    .post('/stripe-webhook-test')
    .send(payload)
    .set('Accept', 'application/json');

  expect(res.statusCode).toBe(200);
  expect(res.body).toHaveProperty('received', true);
  expect(res.body).toHaveProperty('test', true);
});
