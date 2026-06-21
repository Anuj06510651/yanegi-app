# Release Checklist

## Purpose

This checklist prevents broken production releases.

## Pre-Release Code Checks

Before release:

- Run analyzer.
- Run tests.
- Confirm no secrets are committed.
- Confirm no debug-only code is enabled.
- Confirm branch is up to date.
- Confirm PR was reviewed.

Recommended commands:

```bash
flutter analyze
flutter test
```

## Feature QA Checklist

Validate:

- App launch
- Google Sign-In
- Email OTP
- Profile creation
- Profile edit
- Event creation
- Event discovery
- Event joining
- Friend requests
- DM chat
- Group chat
- Notifications
- Image upload
- Map loading
- Logout

## Firebase Checklist

Before production deploy:

- Firestore rules reviewed.
- Storage rules reviewed.
- Cloud Functions tested in staging.
- Required Firestore indexes exist.
- Firebase config points to correct project.
- Production secrets are not in source code.

## Device Checklist

Test on:

- Android real device or emulator
- iOS real device or simulator
- Web, if supported

## Release Approval

Required approvals:

- Feature owner
- QA owner
- Senior engineer
- Founder for production release

## Rollback Plan

Before release, identify:

- Previous stable app build
- Previous Cloud Functions version or commit
- Previous Firestore rules file
- Previous Storage rules file
- Person responsible for rollback

## Production Deploy Rules

Do not deploy production if:

- Auth is failing in staging.
- Firestore rules are untested.
- Cloud Functions errors are unresolved.
- Analyzer/tests fail.
- Release owner is unavailable.
- No rollback path exists.

## Post-Release Monitoring

Monitor for at least 24 hours:

- Crash rate
- Auth failures
- Firestore permission errors
- Cloud Function errors
- Push notification failures
- Firestore read spikes
- Storage bandwidth spikes
- User reports

## Release Notes

Every release should include:

- Version/build number
- Main changes
- Bug fixes
- Known risks
- Rollback owner

