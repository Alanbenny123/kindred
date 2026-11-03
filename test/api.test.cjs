const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

test('adult accounts only match mutually, chat only after a match, and blocks end chat', async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kindred-test-'));
  const child = spawn(process.execPath, ['server.cjs'], {
    cwd: path.resolve(__dirname, '..'),
    env: { ...process.env, PORT: '0', HOST: '127.0.0.1', KINDRED_DATA_DIR: path.join(root, 'data'), KINDRED_UPLOAD_DIR: path.join(root, 'uploads') },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => { child.kill(); fs.rmSync(root, { recursive: true, force: true }); });
  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Server did not start')), 5000);
    child.stdout.on('data', (chunk) => {
      const match = chunk.toString().match(/:(\d+)\s*$/);
      if (match) { clearTimeout(timer); resolve(Number(match[1])); }
    });
    child.on('error', reject);
    child.on('exit', (code) => reject(new Error(`Server exited: ${code}`)));
  });
  const url = `http://127.0.0.1:${port}`;
  async function call(route, method = 'GET', body, cookie) {
    const response = await fetch(`${url}${route}`, {
      method,
      headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(cookie ? { Cookie: cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, json: await response.json(), cookie: response.headers.get('set-cookie')?.split(';')[0] };
  }
  function profile(email, name, birthDate = '1996-05-05') {
    return { email, password: 'safe-password-123', name, birthDate, city: 'Bengaluru', gender: 'woman', lookingFor: 'everyone', intent: 'Long-term relationship', bio: 'Hello', prompt: 'Coffee?', interests: ['Coffee'], acceptTerms: true };
  }

  const minor = await call('/api/signup', 'POST', profile('minor@example.com', 'Minor', '2015-05-05'));
  assert.equal(minor.status, 400);

  const first = await call('/api/signup', 'POST', profile('one@example.com', 'One'));
  const second = await call('/api/signup', 'POST', profile('two@example.com', 'Two'));
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  const one = first.json.user.id;
  const two = second.json.user.id;
  assert.ok((await call('/api/discover', 'GET', undefined, first.cookie)).json.users.some((u) => u.id === two));
  assert.ok(!(await call('/api/discover', 'GET', undefined, first.cookie)).json.users.some((u) => u.demo));
  assert.equal((await call(`/api/messages/${two}`, 'POST', { text: 'Hello' }, first.cookie)).status, 403);
  assert.equal((await call(`/api/users/${two}/like`, 'POST', undefined, first.cookie)).json.match, false);
  assert.equal((await call(`/api/users/${one}/like`, 'POST', undefined, second.cookie)).json.match, true);
  assert.equal((await call(`/api/messages/${two}`, 'POST', { text: 'Hello' }, first.cookie)).status, 201);
  assert.equal((await call(`/api/messages/${one}`, 'GET', undefined, second.cookie)).json.messages[0].text, 'Hello');

  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=', 'base64');
  const uploaded = await fetch(`${url}/api/photo`, { method: 'POST', headers: { Cookie: first.cookie, 'Content-Type': 'image/png' }, body: png });
  assert.equal(uploaded.status, 200);
  assert.equal((await fetch(`${url}/api/photo/${one}`, { headers: { Cookie: second.cookie } })).status, 200);

  assert.equal((await call(`/api/users/${two}/block`, 'POST', undefined, first.cookie)).status, 200);
  assert.equal((await call(`/api/messages/${one}`, 'GET', undefined, second.cookie)).status, 403);
  assert.equal((await fetch(`${url}/api/photo/${one}`, { headers: { Cookie: second.cookie } })).status, 404);
  assert.equal((await call('/api/account', 'DELETE', { confirm: 'DELETE', password: 'safe-password-123' }, first.cookie)).status, 200);
  assert.equal((await call('/api/me', 'GET', undefined, first.cookie)).status, 401);
});
