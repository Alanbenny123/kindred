import { Client, DocumentsDB, Query } from 'node-appwrite';
import { S3Client, DeleteObjectCommand } from '@aws-sdk/client-s3';

const [command, id] = process.argv.slice(2);
const required = name => { if (!process.env[name]) throw new Error(`Missing ${name}`); return process.env[name]; };
const endpoint = required('APPWRITE_ENDPOINT');
const project = required('APPWRITE_PROJECT_ID');
const key = required('APPWRITE_SETUP_KEY');
const databaseId = required('APPWRITE_DATABASE_ID');
const db = new DocumentsDB(new Client().setEndpoint(endpoint).setProject(project).setKey(key));
const ref = (collectionId, documentId) => ({ databaseId, collectionId, documentId });

if (command === 'reports') {
  const result = await db.listDocuments({ databaseId, collectionId: 'reports', queries: [Query.equal('status', 'open'), Query.limit(100)] });
  for (const report of result.documents) console.log(`${report.$id} | ${report.from} → ${report.to} | ${report.reason}`);
  if (!result.documents.length) console.log('No open reports.');
} else if (command === 'photos') {
  const result = await db.listDocuments({ databaseId, collectionId: 'uploads', queries: [Query.equal('status', 'pending_review'), Query.limit(100)] });
  for (const upload of result.documents) console.log(`${upload.$id} | owner ${upload.owner} | ${upload.key} | ${upload.bytes} bytes`);
  if (!result.documents.length) console.log('No photos awaiting review.');
} else if (command === 'approve-photo' && id) {
  const upload = await db.getDocument(ref('uploads', id));
  if (upload.status !== 'pending_review') throw new Error('Photo is not awaiting review.');
  const profile = await db.getDocument(ref('profiles', upload.owner));
  if (profile.pendingPhotoKey !== upload.key) throw new Error('This is no longer the latest submitted photo.');
  await db.updateDocument({ ...ref('profiles', upload.owner), data: { photoKey: upload.key, pendingPhotoKey: '' } });
  await db.updateDocument({ ...ref('uploads', id), data: { status: 'approved' } });
  if (profile.photoKey && profile.photoKey !== upload.key) {
    const r2 = new S3Client({ region: 'auto', endpoint: `https://${required('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com`, credentials: { accessKeyId: required('R2_ACCESS_KEY_ID'), secretAccessKey: required('R2_SECRET_ACCESS_KEY') } });
    await r2.send(new DeleteObjectCommand({ Bucket: required('R2_BUCKET'), Key: profile.photoKey }));
  }
  console.log(`Approved photo ${id}.`);
} else if (command === 'reject-photo' && id) {
  const upload = await db.getDocument(ref('uploads', id));
  if (upload.status !== 'pending_review') throw new Error('Photo is not awaiting review.');
  const r2 = new S3Client({ region: 'auto', endpoint: `https://${required('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com`, credentials: { accessKeyId: required('R2_ACCESS_KEY_ID'), secretAccessKey: required('R2_SECRET_ACCESS_KEY') } });
  await r2.send(new DeleteObjectCommand({ Bucket: required('R2_BUCKET'), Key: upload.key }));
  const profile = await db.getDocument(ref('profiles', upload.owner));
  if (profile.pendingPhotoKey === upload.key) await db.updateDocument({ ...ref('profiles', upload.owner), data: { pendingPhotoKey: '' } });
  await db.updateDocument({ ...ref('uploads', id), data: { status: 'rejected' } });
  console.log(`Rejected photo ${id}.`);
} else if (command === 'resolve-report' && id) {
  await db.updateDocument({ ...ref('reports', id), data: { status: 'resolved', resolvedAt: new Date().toISOString() } });
  console.log(`Resolved report ${id}.`);
} else if (command === 'suspend-user' && id) {
  await db.updateDocument({ ...ref('profiles', id), data: { status: 'suspended' } });
  console.log(`Suspended user ${id}.`);
} else if (command === 'restore-user' && id) {
  await db.updateDocument({ ...ref('profiles', id), data: { status: 'active' } });
  console.log(`Restored user ${id}.`);
} else {
  console.log('Usage: node scripts/moderate.mjs reports|photos|approve-photo ID|reject-photo ID|resolve-report ID|suspend-user USER_ID|restore-user USER_ID');
  process.exit(1);
}
