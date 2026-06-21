# Ranchi Events Seeder

Seeds 20 sample events in Ranchi, Jharkhand into Firestore along with host users, chats, and event participants.

## What it creates

- `users/{ranchi_host_*}` for five fake hosts.
- `events/{ranchi_event_01..20}` with Ranchi locations.
- `chats/grp_ranchi_event_*` linked to each event.
- `event_participants/{eventId}/users/{hostId}` for each host.

## Run locally (dry run)

```bash
cd functions
node seed_ranchi_events.js --dry-run
```

## Run against emulator

```bash
export FIRESTORE_EMULATOR_HOST=localhost:8080
cd functions
node seed_ranchi_events.js
```

## Run against a Firebase project

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
export FIREBASE_PROJECT_ID=your-project-id
cd functions
node seed_ranchi_events.js
```

> Tip: The script respects `FIRESTORE_EMULATOR_HOST` if it is set.
