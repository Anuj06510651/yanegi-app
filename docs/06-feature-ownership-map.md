# Feature Ownership Map

## Purpose

This guide assigns clear ownership so the team avoids merge conflicts, duplicated work, and unclear responsibility.

## Ownership Principles

- Every feature area has one primary owner.
- Shared services require review from all affected owners.
- Interns work inside assigned areas.
- No one edits production-critical code without review.
- Owners are responsible for quality, docs, and regression checks in their area.

## Recommended Ownership

### Auth and Onboarding

Owner: Developer A

Owns:

- Login
- Signup
- Google Sign-In
- Email OTP
- Auth routing
- Onboarding gates
- Profile completion requirements

High-risk files:

- Auth screens
- Auth services
- Firebase Auth integration
- User creation logic

Required review:

- Senior engineer
- Backend owner for token/function changes

### Profile and Settings

Owner: Developer B

Owns:

- Profile screen
- Edit profile
- Settings
- Avatar and bio display
- User visibility controls

Required review:

- Storage/media owner for upload changes
- Security owner for privacy changes

### Events

Owner: Developer C

Owns:

- Event creation
- Event detail
- Event edit
- Event joining
- Host tools
- Event capacity/status

Required review:

- Map/discovery owner for location changes
- Notifications owner for event alerts

### Discovery and Maps

Owner: Developer D

Owns:

- Map screen
- Event discovery feed
- Filters
- Location-based event queries
- Mapbox integration

Required review:

- Backend owner for query/index changes
- Cost owner for broad reads

### Friends and Social Graph

Owner: Developer E

Owns:

- Friend requests
- Connections
- Follow/friend state
- Social graph queries

Required review:

- Notifications owner for friend alerts
- Privacy owner for visibility changes

### Chat

Owner: Developer F

Owns:

- DM chat
- Group chat
- Message sending
- Chat list
- Unread counters

Required review:

- Backend owner for schema changes
- Cost owner for listener changes

### Notifications

Owner: Developer G

Owns:

- Push notifications
- In-app notifications
- Activity feed
- FCM token handling

Required review:

- Backend owner for Cloud Functions
- Product owner for notification timing/frequency

### Storage and Media

Owner: Developer H

Owns:

- Image upload
- Media compression
- Storage paths
- Thumbnail strategy
- Storage rules

Required review:

- Security owner for rules
- Cost owner for bandwidth changes

### QA and Testing

Owner: Developer I

Owns:

- Regression plans
- Manual test checklists
- Test user setup
- Release QA

### DevOps and Releases

Owner: Developer J

Owns:

- CI
- Branch protection
- Firebase deploys
- Release builds
- Rollbacks

## Shared High-Risk Areas

These require senior review:

- Firebase Auth
- Cloud Functions
- Firestore rules
- Storage rules
- Firebase project config
- Production environment variables
- App release config
- User deletion or migration scripts

