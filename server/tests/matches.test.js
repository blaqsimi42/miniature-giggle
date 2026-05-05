const request = require('supertest');

// Mock firebase-admin before requiring the app
jest.mock('firebase-admin', () => {
  const docs = [
    { id: 'u1', data: () => ({ fullName: 'Alice', age: 28, gender: 'female', religion: 'islam', location: { region: 'lahore' }, hobbies: ['music'], lastActiveAt: { toDate: () => new Date(Date.now() - 2 * 60 * 60 * 1000) } }) },
    { id: 'u2', data: () => ({ fullName: 'Bob', age: 30, gender: 'male', religion: 'islam', location: { region: 'lahore' }, hobbies: ['cricket'], lastActiveAt: { toDate: () => new Date(Date.now() - 30 * 60 * 60 * 1000) } }) },
    { id: 'caller', data: () => ({ fullName: 'Caller', age: 29 }) },
  ];

  const collection = (name) => {
    const obj = {
      where: function () { return this; },
      limit: function () { return { get: async () => ({ docs }) }; },
      get: async function () { return { docs }; },
      doc: function (id) { return { collection: () => ({ get: async () => ({ docs: [] }) }) }; },
    };
    return obj;
  };

  return {
    initializeApp: () => {},
    credential: { cert: () => ({}) },
    auth: () => ({
      verifyIdToken: async (token) => {
        if (token === 'valid-token') return { uid: 'caller' };
        throw new Error('invalid token');
      },
    }),
    messaging: () => ({ send: async () => {} }),
    firestore: () => ({
      collection,
    }),
  };
});

const app = require('../index');

describe('POST /matches', () => {
  test('rejects missing token', async () => {
    const res = await request(app).post('/matches').send({});
    expect(res.status).toBe(401);
    expect(res.body.error).toBeDefined();
  });

  test('returns matches for valid token', async () => {
    const res = await request(app)
      .post('/matches')
      .set('Authorization', 'Bearer valid-token')
      .send({ filters: { religion: 'islam', minAge: 18, maxAge: 40 }, pageSize: 10 });

    expect(res.status).toBe(200);
    expect(res.body.items).toBeInstanceOf(Array);
    expect(res.body.items.length).toBeGreaterThan(0);
    // items should not include caller
    expect(res.body.items.find((i) => i.uid === 'caller')).toBeUndefined();
  });
});
