# Upload Kindred to GitHub

The root [`.gitignore`](.gitignore) excludes user data, uploaded photos, credentials, dependencies, and build output. Keep the repository **private** while the pilot is being built.

## Upload these

- `mobile/` Flutter source, Android/iOS project files, `pubspec.yaml`, and `pubspec.lock`.
- `cloud/function/src/`, `cloud/function/scripts/`, `cloud/function/test/`, `package.json`, `package-lock.json`, and `.env.example`.
- Root `README.md`, `ARCHITECTURE.md`, `GITHUB_UPLOAD.md`, `.gitignore`, and the optional local prototype (`server.cjs`, `admin.cjs`, `scripts/`, `test/`, root `package.json`).

## Never upload these

- Real `.env` files, Appwrite API keys, R2 access/secret keys, signing keys, or Android/iOS release certificates.
- `data/app.json` (contains account data), `uploads/` (contains user photos), `node_modules/`, `.dart_tool/`, and `build/`.
- Generated APK/IPA files unless deliberately published as a release artifact.

Project ID, Function ID, and the Appwrite endpoint are public app configuration and may be passed with `--dart-define`. **Appwrite setup keys and R2 keys must stay in Function settings or a local, ignored `.env` file.** Do not put them in Flutter source or `--dart-define`.

## First push

From the `date app` folder, after creating an empty private GitHub repository:

```bash
git init
git add .
git status --short
git diff --cached --name-only
git commit -m "Add Kindred Flutter app and cloud function"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
git push -u origin main
```

Before `git commit`, check that `data/app.json`, `uploads/`, `.env`, `node_modules/`, and signing keys are absent from the staged file list. This folder is not currently an initialized Git repository, so no push has happened yet.
