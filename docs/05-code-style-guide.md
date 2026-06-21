# Code Style Guide

## Purpose

This guide keeps Yanegi code consistent, readable, and safe for a growing team.

## Flutter Structure Rules

- Keep screens focused on UI and user interaction.
- Put business logic in services, repositories, or providers.
- Avoid duplicating UI flows.
- Reuse existing theme constants.
- Do not hardcode production secrets.
- Handle loading, success, empty, and error states.

## Naming Rules

Files:

```text
snake_case.dart
```

Classes:

```text
PascalCase
```

Variables and methods:

```text
camelCase
```

Private fields:

```text
_privateField
```

## UI Rules

- Use the existing Yanegi theme.
- Avoid random one-off colors.
- Keep spacing consistent.
- Avoid duplicate buttons for the same action.
- Do not show broken or dead CTAs.
- Make error messages friendly.
- Keep auth and onboarding flows simple.

## Firebase Rules For Code

- Never read a large collection without `limit`.
- Paginate feeds, chats, notifications, events, and friends.
- Use realtime listeners only when realtime behavior is needed.
- Prefer one-time reads for static data.
- Normalize emails to lowercase.
- Normalize usernames to lowercase.
- Do not trust client-only validation.
- Do not expose sensitive backend actions directly to the client.

## Auth Rules

- Same normalized email must map to same Firebase Auth UID.
- User documents should be keyed by UID.
- Avoid creating duplicate user docs.
- Google Sign-In must not be broken by email auth changes.
- Auth changes require extra review.

## Error Handling

User-facing messages should be:

- Clear
- Short
- Actionable
- Non-technical

Technical logs should:

- Avoid secrets
- Avoid full tokens
- Avoid private user data
- Include enough context for debugging

## Testing Expectations

Required tests or manual verification for:

- Auth changes
- Firestore service changes
- Cloud Function changes
- Chat changes
- Event creation/joining changes
- Security rules changes

## Things To Avoid

- Large files with unrelated logic
- Duplicated auth flows
- Direct production URLs in code
- Hardcoded API keys
- Broad Firestore reads
- Client-side-only security
- Silent catch blocks
- Unbounded arrays in Firestore documents

