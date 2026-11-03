# Kindred cloud setup

This is a private pilot backend: Appwrite Cloud runs Auth, DocumentsDB, and one Function; Cloudflare R2 stores profile photos in a **private** bucket. The Flutter app uses Appwrite directly for sign-in and the Function for every dating action. No founder-owned computer has to stay on. Nothing is deployed until you connect your own accounts.

## 1. Create cloud resources

1. Create an Appwrite project and register Android (`com.example.kindred`) and, if needed, iOS (`com.example.kindred`) platforms. Replace these example package IDs before a store release.
2. Enable email/password Auth. Create a private setup API key with `documentsdb.read`, `documentsdb.write`, `documentsdb.collections.read`, `documentsdb.collections.write`, `documentsdb.documents.read`, and `documentsdb.documents.write`. Keep this key out of Git and revoke it if it is no longer needed.
3. Create one **private** R2 bucket. Create R2 API credentials limited to that bucket with object read/write access. R2 checkout may require payment details and overages can be billed.
4. Copy `function/.env.example` to `function/.env` locally and fill in the settings. `APPWRITE_SETUP_KEY` belongs only in this local file or your private shell environment, never in Flutter or the Function's runtime settings.

## 2. Create the database

From `cloud/function`, load the local `.env` values into your shell and run:

```bash
set -a
source .env
set +a
npm ci
node scripts/setup.mjs
```

The script creates a DocumentsDB database (`kindred` by default), eight private collections, and indexes. It is safe to rerun when a resource already exists. The collections have no client permissions; the Function accesses them with its scoped ephemeral key.

## 3. Deploy the Function from GitHub

Create one Appwrite Function with a Node.js runtime and connect your GitHub repository. In its Git configuration set:

| Setting | Value |
| --- | --- |
| Root directory | `cloud/function` |
| Entry point | `src/index.js` |
| Build command | `npm ci` |
| Execute access | signed-in users |

In the Function's **Scopes**, enable only DocumentsDB document read/write and Users write (for account deletion). In **Environment variables**, set `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`, `APPWRITE_DATABASE_ID`, `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, and `R2_SECRET_ACCESS_KEY`. Do **not** set `APPWRITE_SETUP_KEY` there. Redeploy after changing settings.

The Function verifies the invoking Appwrite user's JWT. A caller cannot supply another person's user ID. The R2 credentials stay in Function settings, not in the phone app.

## 4. Run Flutter against the cloud

From `mobile`:

```bash
flutter run -d c30481f5 \
  --dart-define=APPWRITE_ENDPOINT=https://YOUR-REGION.cloud.appwrite.io/v1 \
  --dart-define=APPWRITE_PROJECT_ID=YOUR_PROJECT_ID \
  --dart-define=APPWRITE_FUNCTION_ID=YOUR_FUNCTION_ID
```

These three values are public app configuration. Do not pass R2 keys or Appwrite API keys to Flutter. Without the three defines, the app still uses the local Node prototype.

## 5. Operate the private pilot

Review pending photos and open reports from a trusted machine when needed:

```bash
node scripts/moderate.mjs photos
node scripts/moderate.mjs approve-photo UPLOAD_ID
node scripts/moderate.mjs reject-photo UPLOAD_ID
node scripts/moderate.mjs reports
node scripts/moderate.mjs resolve-report REPORT_ID
node scripts/moderate.mjs suspend-user USER_ID
node scripts/moderate.mjs restore-user USER_ID
```

The moderation script uses the private setup key. A submitted photo stays hidden until approved. The pilot allows one pending photo per profile. A 350 KB client and server limit keeps ordinary photos small; a signed R2 upload URL can still receive an oversized body before the Function rejects it. Do not open public registration until upload size enforcement happens **before** R2 storage, and add a scheduled cleanup for abandoned objects.

## Checks and limits

Run `npm test` in `cloud/function` and `flutter analyze` in `mobile`. Cloud account integration has to be checked with two actual test accounts after deployment; local tests do not contact Appwrite or R2. Sign-up currently uses a date-of-birth gate, which is insufficient age assurance for a public dating service. Add contact verification, moderation coverage, abuse controls, and privacy/legal review before launch.

Official setup references: [Appwrite Functions](https://appwrite.io/docs/products/functions/deploy-from-git), [DocumentsDB](https://appwrite.io/docs/products/databases/documentsdb/collections), [Function identity/scopes](https://appwrite.io/docs/products/functions/develop), [R2 signed URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/).
