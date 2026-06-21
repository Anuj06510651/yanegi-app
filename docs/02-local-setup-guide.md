# Local Setup Guide

## Purpose

This guide explains how a developer should set up Yanegi locally without touching production systems.

## Required Tools

- Flutter SDK
- Dart SDK
- Xcode for iOS development
- Android Studio for Android development
- Firebase CLI
- Node.js for Cloud Functions
- Git
- A code editor such as VS Code or Android Studio

## Setup Steps

1. Clone the repository.
2. Open the project folder in the IDE.
3. Run dependency installation:

```bash
flutter pub get
```

4. Install Cloud Functions dependencies:

```bash
cd functions
npm install
```

5. Confirm Firebase configuration points to dev or staging, not production.
6. Run the app on a simulator, emulator, or real device.

```bash
flutter run
```

## Environment Rules

- Do not use production Firebase locally unless explicitly approved by the founder or senior engineer.
- Do not commit API keys, service account files, `.env` files, or Firebase private credentials.
- Use staging or dev Firebase projects for local development.
- Use test users only.

## Common Commands

Analyze code:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Run iOS:

```bash
flutter run -d ios
```

Run Android:

```bash
flutter run -d android
```

Run Firebase emulators if configured:

```bash
firebase emulators:start
```

## Firebase Setup Checklist

Before running locally, confirm:

- Firebase Auth is enabled in dev/staging.
- Firestore exists in dev/staging.
- Storage bucket exists in dev/staging.
- Cloud Functions are deployed or emulated.
- Firebase options file is not accidentally pointing to production.

## Troubleshooting

### Flutter dependencies fail

Run:

```bash
flutter clean
flutter pub get
```

### iOS build fails

Check:

- Xcode installed
- CocoaPods installed
- iOS deployment target
- Signing configuration

### Android build fails

Check:

- Android SDK installed
- Gradle sync completed
- Emulator running
- Package name matches Firebase app

### Firebase permission denied

Possible causes:

- Wrong Firebase project
- Missing test user auth
- Firestore rules blocking access
- Local config points to production with restricted access

## Setup Is Complete When

- App launches successfully.
- Developer can sign in using staging/dev auth.
- Profile screen loads.
- Event discovery loads staging/dev data.
- No production user data is visible.

