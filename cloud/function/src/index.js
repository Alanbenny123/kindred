import { randomUUID } from 'node:crypto';
import { Account, Client, DocumentsDB, Query, Users } from 'node-appwrite';
import { S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { HttpError, text, validateProfile, idFor, pairId, eligible, publicProfile } from './core.js';

const COLLECTIONS = ['profiles', 'likes', 'passes', 'matches', 'messages', 'blocks', 'reports', 'uploads'];
const MAX_PHOTO = 350 * 1024;
const required = name => {
  const value = process.env[name];
  if (!value) throw new HttpError(500, `Missing Function setting: ${name}`);
  return value;
};
const notFound = error => error?.code === 404 || error?.status === 404;
const conflict = error => error?.code === 409 || error?.status === 409;
const validId = value => /^[a-zA-Z0-9._-]{1,36}$/.test(value || '');

function repository(db) {
  const databaseId = required('APPWRITE_DATABASE_ID');
  const collectionId = name => {
    if (!COLLECTIONS.includes(name)) throw new Error(`Unknown collection: ${name}`);
    return name;
  };
  return {
    async get(name, id) {
      try { return await db.getDocument({ databaseId, collectionId: collectionId(name), documentId: id }); }
      catch (error) { if (notFound(error)) return null; throw error; }
    },
    async list(name, queries = []) {
      const result = await db.listDocuments({ databaseId, collectionId: collectionId(name), queries });
      return result.documents;
    },
    async create(name, id, data) {
      return db.createDocument({ databaseId, collectionId: collectionId(name), documentId: id, data });
    },
    async put(name, id, data) {
      return db.upsertDocument({ databaseId, collectionId: collectionId(name), documentId: id, data });
    },
    async update(name, id, data) {
      return db.updateDocument({ databaseId, collectionId: collectionId(name), documentId: id, data });
    },
    async remove(name, id) {
      try { await db.deleteDocument({ databaseId, collectionId: collectionId(name), documentId: id }); }
      catch (error) { if (!notFound(error)) throw error; }
    },
  };
}

function storage() {
  return {
    bucket: required('R2_BUCKET'),
    client: new S3Client({
      region: 'auto',
      endpoint: `https://${required('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId: required('R2_ACCESS_KEY_ID'), secretAccessKey: required('R2_SECRET_ACCESS_KEY') },
    }),
  };
}

const privateProfile = (profile, account) => ({
  ...publicProfile(profile),
  email: account.email,
  birthDate: profile.birthDate,
  lookingFor: profile.lookingFor,
  photoPending: Boolean(profile.pendingPhotoKey),
});

async function blocked(repo, a, b) {
  const [forward, backward] = await Promise.all([
    repo.get('blocks', idFor('b', a, b)),
    repo.get('blocks', idFor('b', b, a)),
  ]);
  return Boolean(forward || backward);
}

async function matched(repo, a, b) {
  if (await blocked(repo, a, b)) return false;
  const [match, target] = await Promise.all([
    repo.get('matches', pairId(a, b)),
    repo.get('profiles', b),
  ]);
  return Boolean(match && target?.status === 'active');
}

async function photoUrl(repo, viewer, target) {
  if (!target?.photoKey) return null;
  if (viewer.$id !== target.$id && (!eligible(viewer, target) || await blocked(repo, viewer.$id, target.$id))) return null;
  const { client, bucket } = storage();
  return getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: target.photoKey }), { expiresIn: 90 });
}

async function listAll(repo, name, queries = []) {
  const documents = [];
  for (let offset = 0; offset < 1000; offset += 100) {
    const page = await repo.list(name, [...queries, Query.limit(100), Query.offset(offset)]);
    documents.push(...page);
    if (page.length < 100) break;
  }
  return documents;
}

async function deleteWhere(repo, name, queries) {
  for (;;) {
    const page = await repo.list(name, [...queries, Query.limit(100)]);
    if (!page.length) return;
    for (const item of page) await repo.remove(name, item.$id);
  }
}

async function dispatch({ method, path, body, user, repo, users }) {
  const own = await repo.get('profiles', user.$id);

  if (path === '/api/profile' && method === 'POST') {
    if (own) return { status: 200, data: { user: privateProfile(own, user) } };
    if (body.acceptTerms !== true) throw new HttpError(400, 'Accept the community rules and privacy notice.');
    const profile = validateProfile(body);
    const created = await repo.create('profiles', user.$id, {
      ...profile, status: 'active', color: 'coral', photoKey: '', pendingPhotoKey: '', joinedAt: new Date().toISOString(),
    });
    return { status: 201, data: { user: privateProfile(created, user) } };
  }

  if (!own) throw new HttpError(409, 'Finish profile setup before using Kindred.');
  if (own.status !== 'active' && path !== '/api/account') throw new HttpError(403, 'This account is not active.');

  if (path === '/api/me' && method === 'GET') return { data: { user: privateProfile(own, user) } };
  if (path === '/api/profile' && method === 'PATCH') {
    const updated = await repo.update('profiles', user.$id, validateProfile(body, own));
    return { data: { user: privateProfile(updated, user) } };
  }

  if (path === '/api/discover' && method === 'GET') {
    const candidates = await repo.list('profiles', [Query.equal('city', own.city), Query.equal('status', 'active'), Query.limit(100)]);
    const visible = [];
    for (const target of candidates) {
      if (!eligible(own, target)) continue;
      const [isBlocked, liked, passed] = await Promise.all([
        blocked(repo, user.$id, target.$id),
        repo.get('likes', idFor('l', user.$id, target.$id)),
        repo.get('passes', idFor('p', user.$id, target.$id)),
      ]);
      if (!isBlocked && !liked && !passed) visible.push(publicProfile(target));
      if (visible.length >= 20) break;
    }
    return { data: { users: visible } };
  }

  const action = path.match(/^\/api\/users\/([a-zA-Z0-9._-]{1,36})\/(like|pass|block|report)$/);
  if (action && method === 'POST') {
    const [, targetId, kind] = action;
    if (targetId === user.$id) throw new HttpError(400, 'Choose another profile.');
    const target = await repo.get('profiles', targetId);
    if (!target) throw new HttpError(404, 'Profile not found.');
    if (kind === 'report') {
      const reason = text(body.reason, 300);
      if (!reason) throw new HttpError(400, 'Tell us why you are reporting this profile.');
      await repo.create('reports', randomUUID(), { from: user.$id, to: targetId, reason, status: 'open', at: new Date().toISOString() });
      return { status: 201, data: { ok: true } };
    }
    if (kind === 'block') {
      await repo.put('blocks', idFor('b', user.$id, targetId), { from: user.$id, to: targetId, at: new Date().toISOString() });
      return { data: { ok: true } };
    }
    if (!eligible(own, target) || await blocked(repo, user.$id, targetId)) throw new HttpError(404, 'Profile not found.');
    if (kind === 'pass') {
      await repo.put('passes', idFor('p', user.$id, targetId), { from: user.$id, to: targetId, at: new Date().toISOString() });
      return { data: { ok: true } };
    }
    await repo.put('likes', idFor('l', user.$id, targetId), { from: user.$id, to: targetId, at: new Date().toISOString() });
    const reverse = await repo.get('likes', idFor('l', targetId, user.$id));
    if (reverse) {
      try {
        await repo.create('matches', pairId(user.$id, targetId), { members: [user.$id, targetId].sort(), at: new Date().toISOString() });
      } catch (error) { if (!conflict(error)) throw error; }
    }
    return { data: { match: Boolean(reverse), user: publicProfile(target) } };
  }

  if (path === '/api/matches' && method === 'GET') {
    const docs = await repo.list('matches', [Query.contains('members', [user.$id]), Query.limit(100)]);
    const result = [];
    for (const item of docs) {
      const targetId = item.members.find(id => id !== user.$id);
      if (!targetId || await blocked(repo, user.$id, targetId)) continue;
      const target = await repo.get('profiles', targetId);
      if (!target || target.status !== 'active') continue;
      const last = await repo.list('messages', [Query.equal('matchId', item.$id), Query.orderDesc('at'), Query.limit(1)]);
      result.push({ ...publicProfile(target), lastMessage: last[0] ? { text: last[0].text, at: last[0].at } : null });
    }
    return { data: { users: result } };
  }

  const message = path.match(/^\/api\/messages\/([a-zA-Z0-9._-]{1,36})$/);
  if (message && ['GET', 'POST'].includes(method)) {
    const targetId = message[1];
    if (!validId(targetId) || !await matched(repo, user.$id, targetId)) throw new HttpError(403, 'You can only message mutual matches.');
    const matchId = pairId(user.$id, targetId);
    if (method === 'GET') {
      const messages = await repo.list('messages', [Query.equal('matchId', matchId), Query.orderAsc('at'), Query.limit(100)]);
      return { data: { messages: messages.map(m => ({ id: m.$id, from: m.from, to: m.to, text: m.text, at: m.at })) } };
    }
    const messageText = text(body.text, 1000);
    if (!messageText) throw new HttpError(400, 'Write a message first.');
    const item = await repo.create('messages', randomUUID(), { matchId, from: user.$id, to: targetId, text: messageText, at: new Date().toISOString() });
    return { status: 201, data: { message: { id: item.$id, from: item.from, to: item.to, text: item.text, at: item.at } } };
  }

  if (path === '/api/blocks' && method === 'GET') {
    const docs = await repo.list('blocks', [Query.equal('from', user.$id), Query.limit(100)]);
    const profiles = await Promise.all(docs.map(x => repo.get('profiles', x.to)));
    return { data: { users: profiles.filter(Boolean).map(publicProfile) } };
  }
  const unblock = path.match(/^\/api\/blocks\/([a-zA-Z0-9._-]{1,36})$/);
  if (unblock && method === 'DELETE') {
    await repo.remove('blocks', idFor('b', user.$id, unblock[1]));
    return { data: { ok: true } };
  }

  if (path === '/api/photo/prepare' && method === 'POST') {
    if (own.pendingPhotoKey) throw new HttpError(409, 'Your previous photo is awaiting review.');
    const mime = body.mime;
    const bytes = Number(body.bytes);
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(mime) || !Number.isSafeInteger(bytes) || bytes < 1 || bytes > MAX_PHOTO) throw new HttpError(400, 'Use a JPEG, PNG, or WebP photo under 350 KB.');
    const pending = await repo.list('uploads', [Query.equal('owner', user.$id), Query.equal('status', 'prepared'), Query.limit(100)]);
    const { client, bucket } = storage();
    const active = [];
    for (const item of pending) {
      if (Date.now() - Date.parse(item.at) < 5 * 60 * 1000) active.push(item);
      else {
        await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: item.key }));
        await repo.remove('uploads', item.$id);
      }
    }
    if (active.length >= 2) throw new HttpError(429, 'Please finish an earlier photo upload first.');
    const uploadId = randomUUID();
    const key = `profiles/${user.$id}/${uploadId}.${mime === 'image/webp' ? 'webp' : mime === 'image/png' ? 'png' : 'jpg'}`;
    const url = await getSignedUrl(client, new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: mime }), { expiresIn: 60 });
    await repo.create('uploads', uploadId, { owner: user.$id, key, mime, bytes, status: 'prepared', at: new Date().toISOString() });
    return { data: { uploadId, url, mime } };
  }

  if (path === '/api/photo/complete' && method === 'POST') {
    if (own.pendingPhotoKey) throw new HttpError(409, 'Your previous photo is awaiting review.');
    const upload = validId(body.uploadId) ? await repo.get('uploads', body.uploadId) : null;
    if (!upload || upload.owner !== user.$id || upload.status !== 'prepared') throw new HttpError(404, 'Upload not found.');
    const { client, bucket } = storage();
    const object = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: upload.key }));
    if (!object.ContentLength || object.ContentLength > MAX_PHOTO || object.ContentLength !== upload.bytes || object.ContentType !== upload.mime) {
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: upload.key }));
      await repo.remove('uploads', upload.$id);
      throw new HttpError(400, 'Photo size or type is invalid.');
    }
    const objectBody = await client.send(new GetObjectCommand({ Bucket: bucket, Key: upload.key }));
    const bytes = await objectBody.Body.transformToByteArray();
    const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
    const png = Buffer.from(bytes.subarray(0, 8)).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    const webp = Buffer.from(bytes.subarray(0, 4)).toString() === 'RIFF' && Buffer.from(bytes.subarray(8, 12)).toString() === 'WEBP';
    if ((upload.mime === 'image/jpeg' && !jpeg) || (upload.mime === 'image/png' && !png) || (upload.mime === 'image/webp' && !webp)) {
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: upload.key }));
      await repo.remove('uploads', upload.$id);
      throw new HttpError(400, 'Photo content is invalid.');
    }
    // The signed PUT can be reused until expiry. Move verified bytes to a key
    // that was never signed, so a later PUT cannot replace a reviewed photo.
    const verifiedKey = `reviewed/${user.$id}/${randomUUID()}.${upload.mime === 'image/webp' ? 'webp' : upload.mime === 'image/png' ? 'png' : 'jpg'}`;
    await client.send(new PutObjectCommand({ Bucket: bucket, Key: verifiedKey, Body: bytes, ContentType: upload.mime }));
    await repo.update('uploads', upload.$id, { key: verifiedKey, status: 'pending_review' });
    const updated = await repo.update('profiles', user.$id, { pendingPhotoKey: verifiedKey });
    await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: upload.key }));
    return { data: { user: privateProfile(updated, user), pendingReview: true } };
  }

  const photo = path.match(/^\/api\/photo\/([a-zA-Z0-9._-]{1,36})$/);
  if (photo && method === 'GET') {
    const target = await repo.get('profiles', photo[1]);
    const url = await photoUrl(repo, own, target);
    if (!url) throw new HttpError(404, 'Photo not found.');
    return { data: { url } };
  }

  if (path === '/api/account' && method === 'DELETE') {
    if (body.confirm !== 'DELETE') throw new HttpError(400, 'Type DELETE to confirm.');
    const { client, bucket } = storage();
    const uploads = await listAll(repo, 'uploads', [Query.equal('owner', user.$id)]);
    for (const item of uploads) {
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: item.key }));
      await repo.remove('uploads', item.$id);
    }
    if (own.photoKey && !uploads.some(x => x.key === own.photoKey)) await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: own.photoKey }));
    const memberMatches = await listAll(repo, 'matches', [Query.contains('members', [user.$id])]);
    for (const item of memberMatches) {
      await deleteWhere(repo, 'messages', [Query.equal('matchId', item.$id)]);
      await repo.remove('matches', item.$id);
    }
    for (const table of ['likes', 'passes', 'blocks', 'reports']) {
      await deleteWhere(repo, table, [Query.equal('from', user.$id)]);
      await deleteWhere(repo, table, [Query.equal('to', user.$id)]);
    }
    await repo.remove('profiles', user.$id);
    await users.delete({ userId: user.$id });
    return { data: { ok: true } };
  }

  throw new HttpError(404, 'Not found.');
}

export default async function ({ req, res, error }) {
  try {
    const endpoint = required('APPWRITE_ENDPOINT');
    const project = required('APPWRITE_PROJECT_ID');
    const jwt = req.headers['x-appwrite-user-jwt'];
    const key = req.headers['x-appwrite-key'];
    if (!jwt || !key) throw new HttpError(401, 'Please sign in.');
    const userClient = new Client().setEndpoint(endpoint).setProject(project).setJWT(jwt);
    const user = await new Account(userClient).get();
    const adminClient = new Client().setEndpoint(endpoint).setProject(project).setKey(key);
    const repo = repository(new DocumentsDB(adminClient));
    const body = req.bodyJson && typeof req.bodyJson === 'object' && !Array.isArray(req.bodyJson) ? req.bodyJson : {};
    const result = await dispatch({ method: req.method, path: req.path, body, user, repo, users: new Users(adminClient) });
    return res.json(result.data, result.status || 200);
  } catch (cause) {
    if (!(cause instanceof HttpError) && cause?.code !== 401) error?.(String(cause));
    const status = cause instanceof HttpError ? cause.status : cause?.code === 401 ? 401 : 500;
    return res.json({ error: status === 500 ? 'Something went wrong.' : cause.message }, status);
  }
}

export { dispatch, repository };
