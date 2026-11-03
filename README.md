# Kindred dating app MVP

The repository now contains two backends: the original local Node.js prototype and a new Appwrite Function with private Cloudflare R2 photo storage. The cloud code is **not deployed** yet. See [the architecture](ARCHITECTURE.md), [cloud setup](cloud/README.md), and [GitHub upload guide](GITHUB_UPLOAD.md).

Kindred is a Flutter app for Android and iPhone. The pilot includes adult sign-up, profiles, discovery, mutual likes, chat, reporting, blocking, photo upload, and account deletion. The local demo account uses clearly labelled sample profiles; cloud builds do not show the demo.

## Run locally

Requirements: Node.js 20+ and Flutter 3.47+.

1. Start the backend from this folder:

   ```bash
   npm start
   ```

2. In another terminal, start the Flutter app:

   ```bash
   cd mobile
   flutter run
   ```

The default API address is `http://10.0.2.2:3000` on the Android emulator and `http://127.0.0.1:3000` on the iOS simulator. On a physical Android phone, start the backend with `HOST=0.0.0.0 npm start`, then enter `http://YOUR_COMPUTER_IP:3000` under **Development server address** on the sign-in screen. The phone and computer must share a trusted local network. For an iPhone on a physical device or any public deployment, use an HTTPS backend URL. You can also set the initial address at build time with `--dart-define=API_BASE_URL=https://YOUR_SERVER`.

The demo sign-in is `demo@example.com` / `DemoPass123!`. Sample profiles are labelled in the app. To test real matching, create two accounts in the same city with compatible preferences on separate devices or simulators. Both accounts must like each other before chat opens.

## Data and moderation

The backend saves data to `data/app.json` and photos to `uploads/`, both excluded from Git. Back up these directories if you need to keep pilot data.

To review reports or ban an account, stop the backend and run:

```bash
node admin.cjs reports
node admin.cjs ban USER_ID
node admin.cjs resolve REPORT_ID
```

Restart the backend afterward.

## Before a public launch

This is a controlled pilot, not a production dating service. Add reliable age assurance, verified contact information, image and message moderation, a staffed report queue, abuse monitoring, HTTPS, backups, proper legal notices, and review the requirements for each launch region. The date-of-birth field is only a basic gate and is not sufficient age assurance on its own. iOS source is included, but iOS builds require macOS and Xcode.
