import { Client, DocumentsDB, DocumentsDBIndexType } from 'node-appwrite';

const endpoint = process.env.APPWRITE_ENDPOINT;
const project = process.env.APPWRITE_PROJECT_ID;
const key = process.env.APPWRITE_SETUP_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'kindred';
if (!endpoint || !project || !key) {
  console.error('Set APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, and APPWRITE_SETUP_KEY.');
  process.exit(1);
}

const db = new DocumentsDB(new Client().setEndpoint(endpoint).setProject(project).setKey(key));
async function create(label, run) {
  try { await run(); console.log(`Created ${label}`); }
  catch (error) { if (error.code === 409) console.log(`Exists: ${label}`); else throw error; }
}

await create(`database ${databaseId}`, () => db.create({ databaseId, name: 'Kindred' }));
const collections = ['profiles', 'likes', 'passes', 'matches', 'messages', 'blocks', 'reports', 'uploads'];
for (const name of collections) {
  // No client permissions: only the Function's scoped server key can access documents.
  await create(`collection ${name}`, () => db.createCollection({ databaseId, collectionId: name, name, permissions: [], documentSecurity: false }));
}

const indexes = {
  profiles: [['city_status', ['city', 'status']]],
  likes: [['from', ['from']], ['to', ['to']]],
  passes: [['from', ['from']], ['to', ['to']]],
  matches: [['members', ['members']]],
  messages: [['match_at', ['matchId', 'at']]],
  blocks: [['from', ['from']], ['to', ['to']]],
  reports: [['from', ['from']], ['to', ['to']], ['status', ['status']]],
  uploads: [['owner_status', ['owner', 'status']], ['status', ['status']]],
};
for (const [collectionId, entries] of Object.entries(indexes)) {
  for (const [name, attributes] of entries) {
    await create(`index ${collectionId}.${name}`, () => db.createIndex({ databaseId, collectionId, key: name, type: DocumentsDBIndexType.Key, attributes }));
  }
}
console.log('Appwrite schema is ready.');
