const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = __dirname;
const PUBLIC = path.join(ROOT, 'public');
const DATA_DIR = process.env.KINDRED_DATA_DIR || path.join(ROOT, 'data');
const UPLOAD_DIR = process.env.KINDRED_UPLOAD_DIR || path.join(ROOT, 'uploads');
const DB_FILE = path.join(DATA_DIR, 'app.json');
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '127.0.0.1';
const SESSION_MS = 14 * 24 * 60 * 60 * 1000;
const MAX_JSON = 32 * 1024;
const MAX_PHOTO = 3 * 1024 * 1024;
const loginAttempts = new Map();

fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return `${salt}:${crypto.scryptSync(password, salt, 64).toString('hex')}`;
}

function checkPassword(password, stored) {
  if (!stored) return false;
  const [salt, hash] = stored.split(':');
  if (!salt || !hash) return false;
  const expected = Buffer.from(hash, 'hex');
  const actual = crypto.scryptSync(password, salt, expected.length);
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

function seedDb() {
  const demo = {
    id: 'demo', email: 'demo@example.com', password: hashPassword('DemoPass123!'),
    name: 'Alex', birthDate: '1997-04-12', city: 'Bengaluru', gender: 'man',
    lookingFor: 'everyone', intent: 'Long-term relationship',
    bio: 'Curious about people, good coffee, and weekend walks. Looking for a real connection.',
    interests: ['Coffee', 'Travel', 'Live music'], prompt: 'A perfect Sunday: a slow breakfast and no strict plans.',
    color: 'coral', demo: true, joinedAt: new Date().toISOString()
  };
  const samples = [
    ['aanya', 'Aanya', '1998-06-07', 'woman', 'Bookshops, live music, and conversations that run past closing time.', ['Books', 'Music', 'Coffee'], 'My ideal first date: a bookstore and a long walk.', 'rose'],
    ['meera', 'Meera', '1996-02-18', 'woman', 'I make excellent playlists and questionable pottery.', ['Art', 'Food', 'Travel'], 'A green flag: being kind to the waiter.', 'lilac'],
    ['sam', 'Sam', '1995-11-30', 'nonbinary', 'Design nerd, park wanderer, and enthusiastic amateur cook.', ['Design', 'Cooking', 'Nature'], 'The quickest way to my heart: teach me something new.', 'mint'],
    ['rohan', 'Rohan', '1994-09-03', 'man', 'Always planning my next hike. Equally happy with a quiet night in.', ['Hiking', 'Films', 'Dogs'], 'Together we could: find the best breakfast in town.', 'sky'],
    ['tara', 'Tara', '1999-01-26', 'woman', 'Trying to see more of the world, one train ride at a time.', ['Travel', 'Photography', 'Food'], 'I get excited about: tiny cafés and big ideas.', 'peach']
  ].map(([id, name, birthDate, gender, bio, interests, prompt, color]) => ({
    id, email: `${id}@example.invalid`, password: null, name, birthDate,
    city: 'Bengaluru', gender, lookingFor: 'everyone', intent: 'Long-term relationship',
    bio, interests, prompt, color, demo: true, joinedAt: new Date().toISOString()
  }));
  return {
    users: [demo, ...samples], sessions: [],
    likes: [{ from: 'aanya', to: 'demo', at: new Date().toISOString() }, { from: 'demo', to: 'meera', at: new Date().toISOString() }, { from: 'meera', to: 'demo', at: new Date().toISOString() }],
    passes: [], blocks: [], reports: [],
    messages: [{ id: crypto.randomUUID(), from: 'meera', to: 'demo', text: 'Hi Alex! Your Sunday plan sounds very good ☕', at: new Date(Date.now() - 60 * 60 * 1000).toISOString() }]
  };
}

let db;
if (fs.existsSync(DB_FILE)) {
  db = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
} else {
  db = seedDb();
  save();
}

function save() {
  const temp = `${DB_FILE}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(db, null, 2), { mode: 0o600 });
  fs.renameSync(temp, DB_FILE);
}

function send(res, status, data, headers = {}) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...headers
  });
  res.end(body);
}

function fail(res, status, message) { send(res, status, { error: message }); }

function ageOf(birthDate) {
  const date = new Date(`${birthDate}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate) || Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== birthDate) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  const birthday = new Date(Date.UTC(now.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  if (now < birthday) age--;
  return age;
}

function publicUser(user) {
  return {
    id: user.id, name: user.name, age: ageOf(user.birthDate), city: user.city,
    gender: user.gender, intent: user.intent, bio: user.bio, interests: user.interests,
    prompt: user.prompt, color: user.color || 'coral', photo: Boolean(user.photo), demo: Boolean(user.demo)
  };
}

function privateUser(user) {
  return { ...publicUser(user), email: user.email, birthDate: user.birthDate, lookingFor: user.lookingFor };
}

function cookieMap(req) {
  return Object.fromEntries((req.headers.cookie || '').split(';').map(part => part.trim().split('=')).filter(pair => pair.length === 2));
}

function currentUser(req) {
  const token = cookieMap(req).kindred_session;
  if (!token) return null;
  const digest = crypto.createHash('sha256').update(token).digest('hex');
  const session = db.sessions.find(s => s.token === digest && s.expires > Date.now());
  if (!session) return null;
  const user = db.users.find(u => u.id === session.userId);
  return user && !user.banned ? user : null;
}

function createSession(res, user) {
  const token = crypto.randomBytes(32).toString('base64url');
  db.sessions.push({ token: crypto.createHash('sha256').update(token).digest('hex'), userId: user.id, expires: Date.now() + SESSION_MS });
  db.sessions = db.sessions.filter(s => s.expires > Date.now());
  save();
  res.setHeader('Set-Cookie', `kindred_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_MS / 1000}${process.env.HTTPS === '1' ? '; Secure' : ''}`);
}

function clearSession(req, res) {
  const token = cookieMap(req).kindred_session;
  if (token) {
    const digest = crypto.createHash('sha256').update(token).digest('hex');
    db.sessions = db.sessions.filter(s => s.token !== digest);
    save();
  }
  res.setHeader('Set-Cookie', 'kindred_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');
}

async function readBody(req, limit = MAX_JSON) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw Object.assign(new Error('Upload is too large.'), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function jsonBody(req) {
  if (!(req.headers['content-type'] || '').startsWith('application/json')) throw Object.assign(new Error('Expected JSON.'), { status: 415 });
  try { return JSON.parse((await readBody(req)).toString('utf8')); }
  catch (error) { if (error.status) throw error; throw Object.assign(new Error('Invalid JSON.'), { status: 400 }); }
}

function cleanText(value, max = 200) {
  return String(value ?? '').trim().replace(/\s+/g, ' ').slice(0, max);
}

function hasBlocked(a, b) {
  return db.blocks.some(x => (x.from === a && x.to === b) || (x.from === b && x.to === a));
}

function isMatch(a, b) {
  return !hasBlocked(a, b) && db.likes.some(x => x.from === a && x.to === b) && db.likes.some(x => x.from === b && x.to === a);
}

function visibleTo(user, target) {
  return target && target.id !== user.id && !target.banned && Boolean(target.demo) === Boolean(user.demo) && !hasBlocked(user.id, target.id);
}

function matchesPreference(gender, lookingFor) {
  return lookingFor === 'everyone' || lookingFor === gender || (lookingFor === 'nonbinary' && gender === 'nonbinary');
}

function validateProfile(body, existing = null) {
  const name = cleanText(body.name, 40);
  const city = cleanText(body.city, 60);
  const bio = cleanText(body.bio, 500);
  const prompt = cleanText(body.prompt, 180);
  const gender = body.gender;
  const lookingFor = body.lookingFor;
  const intent = body.intent;
  const birthDate = existing ? existing.birthDate : body.birthDate;
  const interests = Array.isArray(body.interests) ? [...new Set(body.interests.map(x => cleanText(x, 24)).filter(Boolean))].slice(0, 6) : [];
  if (name.length < 2) throw Object.assign(new Error('Enter a name with at least 2 characters.'), { status: 400 });
  if (city.length < 2) throw Object.assign(new Error('Enter your city.'), { status: 400 });
  if (!['woman', 'man', 'nonbinary'].includes(gender)) throw Object.assign(new Error('Choose a gender.'), { status: 400 });
  if (!['everyone', 'woman', 'man', 'nonbinary'].includes(lookingFor)) throw Object.assign(new Error('Choose who you want to meet.'), { status: 400 });
  if (!['Long-term relationship', 'Open to possibilities', 'Getting to know people'].includes(intent)) throw Object.assign(new Error('Choose your dating intention.'), { status: 400 });
  const age = ageOf(birthDate);
  if (age === null || age < 18 || age > 100) throw Object.assign(new Error('You must be at least 18 to use Kindred.'), { status: 400 });
  return { name, city, bio, prompt, gender, lookingFor, intent, birthDate, interests };
}

function rateLimited(ip) {
  const now = Date.now();
  const record = loginAttempts.get(ip) || { count: 0, until: now + 15 * 60 * 1000 };
  if (now > record.until) { record.count = 0; record.until = now + 15 * 60 * 1000; }
  record.count++;
  loginAttempts.set(ip, record);
  return record.count > 20;
}

async function api(req, res, pathname) {
  const method = req.method;
  const origin = req.headers.origin;
  if (origin && origin !== `http://${req.headers.host}` && origin !== `https://${req.headers.host}`) return fail(res, 403, 'Cross-origin request blocked.');

  if (pathname === '/api/signup' && method === 'POST') {
    if (rateLimited(req.socket.remoteAddress)) return fail(res, 429, 'Too many attempts. Try again later.');
    const body = await jsonBody(req);
    const email = cleanText(body.email, 254).toLowerCase();
    const password = String(body.password || '');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return fail(res, 400, 'Enter a valid email address.');
    if (password.length < 10 || password.length > 128) return fail(res, 400, 'Password must be 10–128 characters.');
    if (body.acceptTerms !== true) return fail(res, 400, 'Accept the community rules and privacy notice.');
    if (db.users.some(u => u.email === email)) return fail(res, 409, 'An account with that email already exists.');
    const profile = validateProfile(body);
    const user = { id: crypto.randomUUID(), email, password: hashPassword(password), ...profile, color: 'coral', demo: false, joinedAt: new Date().toISOString() };
    db.users.push(user);
    createSession(res, user);
    return send(res, 201, { user: privateUser(user) });
  }

  if (pathname === '/api/login' && method === 'POST') {
    if (rateLimited(req.socket.remoteAddress)) return fail(res, 429, 'Too many attempts. Try again later.');
    const body = await jsonBody(req);
    const user = db.users.find(u => u.email === cleanText(body.email, 254).toLowerCase());
    if (!user || user.banned || !checkPassword(String(body.password || ''), user.password)) return fail(res, 401, 'Email or password is incorrect.');
    createSession(res, user);
    return send(res, 200, { user: privateUser(user) });
  }

  if (pathname === '/api/logout' && method === 'POST') { clearSession(req, res); return send(res, 200, { ok: true }); }

  const user = currentUser(req);
  if (!user) return fail(res, 401, 'Please sign in.');

  if (pathname === '/api/me' && method === 'GET') return send(res, 200, { user: privateUser(user) });

  if (pathname === '/api/profile' && method === 'PATCH') {
    const body = await jsonBody(req);
    Object.assign(user, validateProfile(body, user));
    save();
    return send(res, 200, { user: privateUser(user) });
  }

  if (pathname === '/api/photo' && method === 'POST') {
    const type = req.headers['content-type'];
    const ext = type === 'image/jpeg' ? '.jpg' : type === 'image/png' ? '.png' : type === 'image/webp' ? '.webp' : null;
    if (!ext) return fail(res, 415, 'Use a JPEG, PNG, or WebP image.');
    const bytes = await readBody(req, MAX_PHOTO);
    const valid = ext === '.jpg' ? bytes.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff])) : ext === '.png' ? bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) : bytes.subarray(0, 4).toString() === 'RIFF' && bytes.subarray(8, 12).toString() === 'WEBP';
    if (!valid) return fail(res, 400, 'The image file is invalid.');
    if (user.photo) { try { fs.unlinkSync(path.join(UPLOAD_DIR, user.photo)); } catch {} }
    user.photo = `${crypto.randomUUID()}${ext}`;
    fs.writeFileSync(path.join(UPLOAD_DIR, user.photo), bytes, { mode: 0o600 });
    save();
    return send(res, 200, { user: privateUser(user) });
  }

  const photoMatch = pathname.match(/^\/api\/photo\/([a-zA-Z0-9-]+)$/);
  if (photoMatch && method === 'GET') {
    const target = db.users.find(u => u.id === photoMatch[1]);
    if (!target || !target.photo || (target.id !== user.id && !visibleTo(user, target))) return fail(res, 404, 'Photo not found.');
    const filename = path.basename(target.photo);
    const file = path.join(UPLOAD_DIR, filename);
    if (!fs.existsSync(file)) return fail(res, 404, 'Photo not found.');
    res.writeHead(200, { 'Content-Type': filename.endsWith('.png') ? 'image/png' : filename.endsWith('.webp') ? 'image/webp' : 'image/jpeg', 'Cache-Control': 'private, max-age=300', 'X-Content-Type-Options': 'nosniff' });
    return fs.createReadStream(file).pipe(res);
  }

  if (pathname === '/api/discover' && method === 'GET') {
    const seen = new Set([...db.likes.filter(x => x.from === user.id).map(x => x.to), ...db.passes.filter(x => x.from === user.id).map(x => x.to)]);
    const users = db.users.filter(target => visibleTo(user, target) && !seen.has(target.id) && target.city.toLowerCase() === user.city.toLowerCase() && matchesPreference(target.gender, user.lookingFor) && matchesPreference(user.gender, target.lookingFor)).map(publicUser);
    return send(res, 200, { users });
  }

  const actionMatch = pathname.match(/^\/api\/users\/([a-zA-Z0-9-]+)\/(like|pass|block|report)$/);
  if (actionMatch && method === 'POST') {
    const [, targetId, action] = actionMatch;
    const target = db.users.find(u => u.id === targetId);
    if (!target || target.id === user.id || Boolean(target.demo) !== Boolean(user.demo)) return fail(res, 404, 'Profile not found.');
    if (action !== 'block' && action !== 'report' && !visibleTo(user, target)) return fail(res, 404, 'Profile not found.');
    if (action === 'like') {
      if (!db.likes.some(x => x.from === user.id && x.to === targetId)) db.likes.push({ from: user.id, to: targetId, at: new Date().toISOString() });
      save();
      return send(res, 200, { match: isMatch(user.id, targetId), user: publicUser(target) });
    }
    if (action === 'pass') {
      if (!db.passes.some(x => x.from === user.id && x.to === targetId)) db.passes.push({ from: user.id, to: targetId });
      save();
      return send(res, 200, { ok: true });
    }
    if (action === 'block') {
      if (!db.blocks.some(x => x.from === user.id && x.to === targetId)) db.blocks.push({ from: user.id, to: targetId, at: new Date().toISOString() });
      save();
      return send(res, 200, { ok: true });
    }
    const body = await jsonBody(req);
    const reason = cleanText(body.reason, 300);
    if (!reason) return fail(res, 400, 'Tell us why you are reporting this profile.');
    db.reports.push({ id: crypto.randomUUID(), from: user.id, to: targetId, reason, status: 'open', at: new Date().toISOString() });
    save();
    return send(res, 201, { ok: true });
  }

  if (pathname === '/api/matches' && method === 'GET') {
    const users = db.users.filter(target => visibleTo(user, target) && isMatch(user.id, target.id)).map(target => {
      const messages = db.messages.filter(m => (m.from === user.id && m.to === target.id) || (m.from === target.id && m.to === user.id));
      return { ...publicUser(target), lastMessage: messages.at(-1) || null };
    }).sort((a, b) => (b.lastMessage?.at || '').localeCompare(a.lastMessage?.at || ''));
    return send(res, 200, { users });
  }

  const messageMatch = pathname.match(/^\/api\/messages\/([a-zA-Z0-9-]+)$/);
  if (messageMatch) {
    const targetId = messageMatch[1];
    const target = db.users.find(u => u.id === targetId);
    if (!target || !visibleTo(user, target) || !isMatch(user.id, targetId)) return fail(res, 403, 'You can only message mutual matches.');
    if (method === 'GET') {
      const messages = db.messages.filter(m => (m.from === user.id && m.to === targetId) || (m.from === targetId && m.to === user.id));
      return send(res, 200, { messages });
    }
    if (method === 'POST') {
      const body = await jsonBody(req);
      const message = cleanText(body.text, 1000);
      if (!message) return fail(res, 400, 'Write a message first.');
      const item = { id: crypto.randomUUID(), from: user.id, to: targetId, text: message, at: new Date().toISOString() };
      db.messages.push(item);
      save();
      return send(res, 201, { message: item });
    }
  }

  if (pathname === '/api/blocks' && method === 'GET') {
    return send(res, 200, { users: db.blocks.filter(x => x.from === user.id).map(x => db.users.find(u => u.id === x.to)).filter(Boolean).map(publicUser) });
  }

  const unblockMatch = pathname.match(/^\/api\/blocks\/([a-zA-Z0-9-]+)$/);
  if (unblockMatch && method === 'DELETE') {
    db.blocks = db.blocks.filter(x => !(x.from === user.id && x.to === unblockMatch[1]));
    save();
    return send(res, 200, { ok: true });
  }

  if (pathname === '/api/account' && method === 'DELETE') {
    const body = await jsonBody(req);
    if (body.confirm !== 'DELETE' || !checkPassword(String(body.password || ''), user.password)) return fail(res, 400, 'Enter your password and type DELETE to confirm.');
    if (user.photo) { try { fs.unlinkSync(path.join(UPLOAD_DIR, user.photo)); } catch {} }
    db.users = db.users.filter(x => x.id !== user.id);
    db.sessions = db.sessions.filter(x => x.userId !== user.id);
    for (const field of ['likes', 'passes', 'blocks', 'reports', 'messages']) db[field] = db[field].filter(x => x.from !== user.id && x.to !== user.id);
    save();
    res.setHeader('Set-Cookie', 'kindred_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');
    return send(res, 200, { ok: true });
  }

  return fail(res, 404, 'Not found.');
}

function staticFile(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return fail(res, 405, 'Method not allowed.');
  const route = pathname === '/' ? '/index.html' : pathname;
  const file = path.resolve(PUBLIC, `.${route}`);
  if (!file.startsWith(`${PUBLIC}${path.sep}`) || !fs.existsSync(file) || !fs.statSync(file).isFile()) return fail(res, 404, 'Not found.');
  const ext = path.extname(file);
  const mime = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' }[ext] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': `${mime}; charset=utf-8`, 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'" });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(file).pipe(res);
}

const server = http.createServer(async (req, res) => {
  try {
    const pathname = new URL(req.url, `http://${req.headers.host || 'localhost'}`).pathname;
    if (pathname.startsWith('/api/')) return await api(req, res, pathname);
    return staticFile(req, res, pathname);
  } catch (error) {
    if (error.status && error.status < 500) return fail(res, error.status, error.message);
    console.error(error);
    return fail(res, 500, 'Something went wrong.');
  }
});

server.listen(PORT, HOST, () => console.log(`Kindred is running at http://${HOST}:${server.address().port}`));
