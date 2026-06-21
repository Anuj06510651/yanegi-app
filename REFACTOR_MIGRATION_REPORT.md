# Refactor Migration Report

Safe split of oversized files into a `features/` structure, with identical runtime
behavior, no Firestore schema changes, and no route changes.

Plan: `~/.claude/plans/graceful-brewing-rain.md`. Strategy: **extract-in-place** —
entry files stay at their paths as thin composition roots / facade.

---

## Verification baselines

| Checkpoint | `flutter analyze` | `flutter test` |
|---|---|---|
| Initial (pre-work) | 14 issues, 0 errors | **23 pass / 42 fail** (pre-existing) |
| After test-harness repair | 14 issues, 0 errors | **52 pass / 13 fail** |
| After Part A (Hive caching) | 14 issues, 0 errors | 52 pass / 13 fail (no regression) |

**Gate for every refactor step:** analyze ≤ 14 issues / 0 errors, and tests show
**no new failures vs 52 pass / 13 fail**.

### Pre-existing test failures (NOT caused by this work; out of scope)
The 13 remaining failures are genuine pre-existing product/test bugs, none in the
refactor targets' safety nets:
- `user_presence_service_test`: `isOnline` writes `null` vs expected `false`.
- `user_service_username_limits_test` (1): `PlatformException: Firestore transactions
  require all reads before writes` — real transaction-ordering bug in `UserService`.
- `firebase_chat_repository_reliability_test` (1): typing-indicator assertion `true`/`false`.
- `event_consistency_stream_test`, `explore_feed_resilience_test`, `auth_flow_service_test`,
  `auth_onboarding_flow_widget_test`, `firestore_rules_chat_security_test`, `widget_test`,
  `discover_people_transitions_test`: assorted timeouts / assertions / full-app-boot setup.

---

## Step 0 — Test-harness repair (test-only; no production change)

**Problem:** Most suites never initialized Firebase, so any code transitively touching
`FirebaseFirestore.instance` (e.g. `EventService` → default `MediaStorageService` →
`RateLimiterService`) threw `[core/no-app]`. This left the safety net for the riskiest
refactor target (`event_service`) 100% red.

**Fix:** Added `TestWidgetsFlutterBinding.ensureInitialized()` +
`setUpAll(setupFirebaseCoreMocks(); Firebase.initializeApp())` (mirroring the existing
`discover_people_transitions_test.dart`) to:
- `test/event_service_production_test.dart` → **+0/-19 → +19/0** ✅
- `test/firebase_chat_repository_reliability_test.dart` → **+0/-10 → +9/-1**
- `test/user_service_username_limits_test.dart` → **+0/-2 → +1/-1**

Net suite: **23/42 → 52/13**. No production code changed.

---

## Part A — Hive caching (Instagram-like startup; completed earlier task)

Behavior-neutral to tests (cache services no-op when Hive isn't initialized in the
harness). Files:
- `lib/services/local_profile_cache.dart` (new), `lib/services/explore_cache_service.dart` (new)
- `lib/main.dart`: Hive init + open boxes before `runApp`.
- `lib/onboarding/auth_bootstrapper.dart`: persist fetched profile to cache.
- `lib/services/explore_recommendation_service.dart`: yield persisted page on cold start
  (5-min TTL), save fresh first page, clear persisted page on sign-out.
- `lib/screens/profile_screen.dart`: pre-fill display fields from cache in `initState`.
- `lib/screens/settings_screen.dart`: clear `LocalProfileCache` on sign-out.

Gate: analyze 14/0err, tests 52/13 (no regression). ✅

---

## Part B — File splits (in progress)

| Step | File | Before (lines) | After (lines) | New files | analyze | tests |
|---|---|---:|---:|---|---|---|
| 1 | `event_service.dart` | 2,329 | **850** | 5 | 14 / 0err | 52/13 ✅ |
| 2 | `profile_social_screen.dart` | 3,022 | **304** | 7 | 14 / 0err | 52/13 ✅ |
| 3 | `chat_thread_screen.dart` | 3,318 | **1,275** | 9 | 14 / 0err | 52/13 ✅ |
| 4 | `map_screen.dart` | 5,704 | **455** | 11 | 14 / 0err | 52/13 ✅ |

### Step 4 detail — `map_screen.dart` (part/part-of split)

Kept in `_MapScreenState`: fields, `initState`, `dispose`,
`didChangeAppLifecycleState`, `build`, the theme-color getters, and the `static`
consts (`_exploreChips`, `_nycCenter`). 104 instance methods moved into 5 controller
extensions (`lib/features/map/controllers/{map_location,map_events,map_markers,
map_ui,map_explore}_controller.dart`); 11 standalone widget/enum types moved into 6
widget parts (`lib/features/map/widgets/{create_event_sheet,explore_card_interaction,
explore_skeleton_card,user_location_marker,map_share_tile,explore_feed_models}.dart`).
Public widgets `MapWidget`/`ExploreListWidget`/`TopBarWidget` kept in main.
Static refs qualified with `_MapScreenState.`. Only importer (`auth/screens/map_page.dart`)
unchanged. Gate: analyze 14/0err; suite 52/13. ✅

## Summary

| Metric | Before | After |
|---|---|---|
| 4 entry files, total | **14,373 lines** | **2,884 lines** (‑80%) |
| New feature files | — | **32** under `lib/features/{event,profile,friends,chat,map}/` |
| `flutter analyze` | 14 / 0 errors | 14 / 0 errors (unchanged) |
| `flutter test` | 52 / 13 | 52 / 13 (no regression) |

Behavior, Firestore schema, routes, public class names/constructors, and all
importers are unchanged. Every extraction was a verbatim code move (one class per
library across `part` files); the only edits were `EventService.`/`_MapScreenState.`
static qualification and scoped `invalid_use_of_protected_member` ignores on State
controller parts.

### Step 3 detail — `chat_thread_screen.dart` (part/part-of split)

Kept in `_ChatThreadScreenState`: fields, `initState`, `dispose`, the ~1,000-line
`build`, and the two `static` helpers (`_isChatDocStableEqual`, `_listEquals` —
statics can't move to an extension without breaking call sites). 56 instance methods
moved into 4 controller extensions (`lib/features/chat/controllers/{chat_streams,
chat_delivery,chat_mention,chat_message_actions}_controller.dart`) and 5 widget parts
(`lib/features/chat/widgets/{pinned_banner,group_info_modal,swipe_to_reply_row,
seen_initial_bubble,alumni_share_button}.dart`).

Splitter hardened this step (reused for map): string/comment-aware brace+paren depth
so multi-line signatures and interspersed fields are handled; fields and `static`
methods stay in the class; trailing divider comments stay put. No importer changed.
Gate: analyze 14/0err; suite 52/13. ✅

### Step 2 detail — `profile_social_screen.dart` (part/part-of split)

Confirmed with user: same part/part-of technique, with `// ignore_for_file:
invalid_use_of_protected_member` on controller parts (State extensions call the
protected `setState`; semantically safe within the State's own library).

- Kept in `_SocialProfileScreenState`: fields, `initState`, `dispose`, `build`.
- 5 controller extensions: `lib/features/profile/controllers/{profile_data,
  profile_media,hosted_events,profile_view}_controller.dart` and
  `lib/features/friends/controllers/friend_action_controller.dart`.
- 2 widget parts: `lib/features/profile/widgets/{profile_media_header,
  profile_share_sheet}.dart`.
- Extensions are private (`_XxxController`) on the private State type; static consts
  (`_hostedEventsPageSize`, `_statsWarmupDuration`) qualified with
  `_SocialProfileScreenState.`. Method bodies moved verbatim (annotations travel with
  their method).
- No importer changed (10 importers of `profile_social_screen.dart` untouched);
  `StaticProfileMediaHeader` still exported by the library. No schema/route change.
- Gate: analyze 14/0err; full suite 52/13 unchanged. ✅

### Step 1 detail — `event_service.dart` (part/part-of split)

Technique (confirmed with user): the single `EventService` class kept in
`lib/services/event_service.dart` (ctor, fields, static constants, **all** private
helpers). 23 public methods (1,485 lines) moved verbatim into 5 `part`-file public
`extension`s under `lib/features/event/`:
`event_service_creation.dart`, `_participation.dart`, `_join_approval.dart`,
`_lifecycle.dart`, `_queries.dart`.

- One class across a library + parts → private instance helpers reachable via implicit
  `this`; only static-constant refs needed `EventService.` qualification.
- Method bodies moved byte-for-byte (line-accounting invariant enforced by the split
  script: every original line kept-or-moved exactly once).
- **No importer changed** (all 10 importers still `import .../services/event_service.dart`
  and call the same public methods — extensions are in-scope via the library).
- No schema change, no route change, public API identical.
- Gate: analyze 14/0err (the 12 pre-existing `unnecessary_cast` warnings simply
  relocated into the part files); `event_service_production_test` **+19** unchanged;
  full suite 52/13 unchanged. ✅

_Updated after each step._
