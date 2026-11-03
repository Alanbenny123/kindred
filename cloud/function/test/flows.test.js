import test from 'node:test';
import assert from 'node:assert/strict';
import { dispatch } from '../src/index.js';
import { HttpError } from '../src/core.js';

function memoryRepo() {
  const tables = new Map();
  const table = name => {
    if (!tables.has(name)) tables.set(name, new Map());
    return tables.get(name);
  };
  return {
    get: async (name, id) => table(name).get(id) || null,
    create: async (name, id, data) => {
      if (table(name).has(id)) throw Object.assign(new Error('Conflict'), { code: 409 });
      const item = { $id: id, ...data };
      table(name).set(id, item);
      return item;
    },
    put: async (name, id, data) => {
      const item = { $id: id, ...data };
      table(name).set(id, item);
      return item;
    },
    update: async (name, id, data) => {
      const item = { ...table(name).get(id), ...data };
      table(name).set(id, item);
      return item;
    },
    remove: async (name, id) => { table(name).delete(id); },
    list: async name => [...table(name).values()],
  };
}

const profile = (name, birthDate = '1995-01-01') => ({
  name, city: 'Bengaluru', birthDate, gender: 'woman', lookingFor: 'everyone',
  intent: 'Long-term relationship', bio: 'Hello', prompt: 'Coffee?', interests: [], acceptTerms: true,
});
const call = (repo, id, method, path, body = {}) => dispatch({
  repo, user: { $id: id, email: `${id}@example.com` }, users: {}, method, path, body,
});

test('profile creation enforces adult age and keeps email private', async () => {
  const repo = memoryRepo();
  await assert.rejects(call(repo, 'u1', 'POST', '/api/profile', profile('Young', '2015-01-01')),
    error => error instanceof HttpError && error.status === 400);
  const result = await call(repo, 'u1', 'POST', '/api/profile', profile('Asha'));
  assert.equal(result.status, 201);
  assert.equal(result.data.user.email, 'u1@example.com');
  assert.equal(result.data.user.age > 18, true);
  assert.equal(result.data.user.birthDate, '1995-01-01');
});

test('only mutual likes allow messaging; blocking revokes it', async () => {
  const repo = memoryRepo();
  await call(repo, 'u1', 'POST', '/api/profile', profile('Asha'));
  await call(repo, 'u2', 'POST', '/api/profile', profile('Mira'));
  const first = await call(repo, 'u1', 'POST', '/api/users/u2/like');
  assert.equal(first.data.match, false);
  assert.equal('email' in first.data.user, false);
  assert.equal('birthDate' in first.data.user, false);
  await assert.rejects(call(repo, 'u1', 'POST', '/api/messages/u2', { text: 'Hi' }),
    error => error.status === 403);
  const second = await call(repo, 'u2', 'POST', '/api/users/u1/like');
  assert.equal(second.data.match, true);
  const sent = await call(repo, 'u1', 'POST', '/api/messages/u2', { text: 'Hi' });
  assert.equal(sent.data.message.text, 'Hi');
  await call(repo, 'u2', 'POST', '/api/users/u1/block');
  await assert.rejects(call(repo, 'u1', 'POST', '/api/messages/u2', { text: 'Again' }),
    error => error.status === 403);
});
