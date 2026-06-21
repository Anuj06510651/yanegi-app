# Copilot Instructions for Yanegi

## Architecture you must keep in mind
- This is a Flutter + Firebase app with most business logic in `lib/services/` and UI/state wiring in `lib/screens/` + Riverpod providers (`lib/providers/explore_feed_provider.dart`).
- App bootstrap is centralized in `lib/main.dart`: Firebase init, global error hooks, theme loading (`AppThemeService`), deep links (`app_links`), presence tracking, and push setup happen before/around `runApp`.
- Firestore is the source of truth for social/event/chat data; Cloud Functions in `functions/index.js` react to Firestore writes (`notifications/{id}`) to send FCM pushes.

## Data model and schema conventions (important)
- `users` and `events` documents often carry both canonical and legacy keys. Example in `lib/services/user_service.dart`: `avatarUrl` + `avatar_url`, `createdAt` + `created_at`.
- Preserve backward-compat fields when updating profile/event writes unless a migration is explicitly part of the task.
- Username identity is split across:
  - `users/{uid}.usernameLower`
  - `usernames/{normalizedUsername}`
  Keep both in sync (see `updateUsername` in `lib/services/user_service.dart`).
- Event/chat consistency is strict: creating an event also creates/updates participant and chat documents (see `lib/services/event_service.dart`). Avoid “single-document only” edits for event membership logic.

## Security and integration boundaries
- Any feature touching Firestore collections must be checked against `firestore.rules` (chat, notifications, event participation rules are strict and test-backed).
- Storage upload paths are constrained by `storage.rules` (`profile_images/{userId}.jpg`, `banner_images/{userId}.jpg`, `event_images/{eventId}.jpg`, etc.).
- Notification type values are normalized across app + backend:
  - App constants: `lib/services/notification_types.dart`
  - Backend mapping: `functions/index.js` (`normalizeType`)
  - Migration helper: `tool/normalize_notification_types.dart`

## Preferred coding patterns in this repo
- Services are dependency-injectable for tests (`FirebaseFirestore?`, `FirebaseAuth?`, override callbacks).
- Use Riverpod providers for feed/state composition; in async notifiers, guard against dispose races (pattern: `_setStateSafely` in `explore_feed_provider.dart`).
- Existing code intentionally allows `print` logs in services (see `analysis_options.yaml` where `avoid_print: false`). Don’t remove debugging hooks unless requested.

## Dev workflows to use
- Install deps: `flutter pub get`
- Run app: `flutter run`
- Static analysis: `flutter analyze`
- Run all tests: `flutter test`
- Run targeted tests while changing critical logic:
  - `flutter test test/event_service_production_test.dart`
  - `flutter test test/user_service_username_limits_test.dart`
  - `flutter test test/firestore_rules_chat_security_test.dart`

## Change-safety checklist for agents
- When changing event participation/chat flows, update both service logic and tests in `test/event_service_production_test.dart`.
- When changing Firestore rules behavior, update/verify rule-string tests in `test/firestore_rules_chat_security_test.dart`.
- Prefer additive migrations over destructive renames because the app still reads legacy keys in multiple paths.
