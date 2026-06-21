# Yanegi

Yanegi is a Flutter app powered by Firebase.

## Implemented in this update

- Google Sign-In flow using `firebase_auth` + `google_sign_in`
- Firebase Storage image upload system for:
	- `profile_images/{userId}.jpg`
	- `banner_images/{userId}.jpg`
	- `event_images/{eventId}.jpg`
- Firestore URL persistence for profile, banner, and event images
- Crop-before-upload UX for profile, banner, and event banner selection

## Firebase setup checklist

### 1) Enable Google Auth provider

In Firebase Console:

1. Open **Authentication → Sign-in method**
2. Enable **Google** provider

### 2) Configure Android SHA-1 / SHA-256 (required for Google Sign-In)

1. Open **Project settings → Your apps → Android app**
2. Add SHA-1 and SHA-256 certificates
3. Download updated `google-services.json` if Firebase requests it
4. Rebuild app

Without SHA setup, Google Sign-In may fail with `ApiException: 10`.

### 2.1) Verify Android package name mapping

Ensure the package in `android/app/build.gradle.kts`:

- `applicationId = "com.example.yanegi"`

matches the package configured in Firebase Android app and `android/app/google-services.json`.

If package or SHA changes, download a fresh `google-services.json` from Firebase and replace the existing file.

### 2.2) Enable Phone authentication

In Firebase Console:

1. Open **Authentication → Sign-in method**
2. Enable **Phone** provider
3. (Recommended) add test numbers for development

If Phone provider is disabled, OTP login will fail with `operation-not-allowed`.

### 3) Firebase Storage rules

This repo includes:

- `storage.rules`
- `firebase.json`

Rules are currently configured for:

- public reads
- authenticated writes for `profile_images`, `banner_images`, and `event_images`

Deploy rules with Firebase CLI when ready.

## Development run

```bash
flutter pub get
flutter run
```
