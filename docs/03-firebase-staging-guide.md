# Firebase Staging Guide

## Purpose

Yanegi is live, so production Firebase must be protected. This guide defines how Firebase environments should be separated and used.

## Recommended Firebase Projects

```text
yanegi-dev
yanegi-staging
yanegi-prod
```

## Environment Purpose

### Dev

Used for:

- Intern development
- Experimental features
- Fake data
- Local testing

Access:

- Interns can receive limited access.
- No real user data.
- No production secrets.

### Staging

Used for:

- Release testing
- QA
- Pre-production validation
- Cloud Function testing
- Firestore rules testing

Access:

- Senior engineers
- Selected interns with limited roles
- Test data only

### Production

Used for:

- Real users
- Real events
- Real chats
- Real notifications
- Real storage

Access:

- Founder
- Senior trusted engineers only
- No interns by default

## Services To Separate

Each environment should have separate:

- Firebase Auth
- Firestore
- Firebase Storage
- Cloud Functions
- Firebase Messaging
- Firebase Remote Config, if used
- API keys
- Resend keys
- Mapbox keys, where possible

## Production Data Rules

- Never export production user data to intern machines.
- Never copy production Firestore into dev without anonymization.
- Never test destructive scripts on production.
- Never give service account keys to interns.
- Never commit production config files.

## Deployment Rules

Cloud Functions:

```text
dev -> staging -> production
```

Firestore rules:

```text
dev validation -> staging validation -> production deploy
```

Storage rules:

```text
dev validation -> staging validation -> production deploy
```

Flutter app:

```text
local -> staging build -> production release
```

## Staging Validation Checklist

Before production deployment:

- Google Sign-In works.
- Email OTP works.
- Profile completion works.
- Event creation works.
- Event discovery works.
- Event joining works.
- Chat works.
- Notifications work.
- Storage upload works.
- Firestore rules do not block valid users.
- Firestore rules block unauthorized users.

## Founder-Only Items

- Production Firebase owner access
- Billing
- Service account keys
- App Store credentials
- Play Store credentials
- Production Resend key
- Production Mapbox key
- Production signing keys

