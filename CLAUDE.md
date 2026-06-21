# Yanegi — Startup Architecture

## Cold-Start Flow (optimized)

```
T0  App launched
T1  Hive.initFlutter()
T2  LocalProfileCache + ExploreCacheService + ChatPeerCache open in parallel (Future.wait)
T3  Firebase.initializeApp()
T4  AppThemeService.loadThemePreference()
T5  runApp() → first frame → AuthBootstrapper resolves
T6  Auth token restored (FirebaseAuth.authStateChanges().first)
T7  LocalProfileCache.loadHasCompleted(uid) → cache hit → ROUTE TO MAP (no network)
     └─ background: server doc refresh to keep cache current
T8  MapScreen rendered — FlutterMap tiles begin loading
T9  _initLocation() resolves → camera animates to user position
T10 _loadEventsAfterMapReady() fires → Firestore events stream starts
T11 Markers appear on map
T12 (3 s after T8) Chat unread listener starts
```

## Auth Bootstrap Strategy

`auth_bootstrapper.dart` uses **cache-first routing**:

1. Check `LocalProfileCache.loadHasCompleted(uid)` (Hive, ~0 ms)
2. If `true` → route to MapPage **immediately** (skip Firestore fetch)
3. Background-refresh the server doc and update the cache for next launch
4. If cache miss (first install / cleared) → fetch from Firestore as before

First install is slower (server fetch required). Every subsequent warm start is instant.

## Map Render Strategy

- `_allowMapRender` removed — map renders on **first frame**
- `_isLoadingLocation` no longer gates the map — map shows at fallback center
  (`_nycCenter = Delhi: 28.6139, 77.2090`) while GPS resolves
- When location resolves, `_initLocation()` calls `_animateToLocation()` if map
  is already ready, otherwise `onMapReady` handles the animation
- `LocationAccuracy.medium` with 8 s timeout (was `high` / 12 s)

---

# Authentication Architecture

## Sign-in methods supported

| Method | Provider |
|---|---|
| Email OTP | Custom Firebase Function (`sendOtp` / `verifyOtp`) → `signInWithCustomToken` |
| Google | `google_sign_in` package → Firebase `GoogleAuthProvider` credential |

Password sign-in is disabled (throws `StateError` if called).

## Startup auth flow

```
main() → _clearAuthOnFreshInstall()
       → Firebase.initializeApp()
       → runApp → AuthBootstrapper._resolveStartup()
         ├─ authStateChanges().first → null → WelcomeScreen
         └─ user exists
              ├─ LocalProfileCache.loadHasCompleted(uid) == true
              │    → MapPage (instant, background refresh)
              └─ cache miss → Firestore server fetch → onboarding or MapPage
```

## Fresh-install guard (`main.dart → _clearAuthOnFreshInstall`)

Firebase Auth tokens live in the Android Keystore and can survive uninstall on
certain OEM devices or when Google Backup/Restore is enabled. SharedPreferences
data is wiped on clean uninstall, so we use key `yanegi_installed_v2` as a
reliable "first launch after install" signal.

On first launch: forces `FirebaseAuth.signOut()` + `GoogleSignIn().signOut()`.
On warm start: the key exists, no-op, zero cost.

**Do NOT change the marker key without a migration strategy** — changing it
causes every existing user to be signed out on next app update.

## Logout flow (`settings_screen._signOut`)

```
_signOut()
  1. LocalProfileCache.clear(uid)   — wipe local profile display fields
  2. ChatPeerCache.clear()           — wipe cached peer data
  3. _invalidateServiceCaches()      — dispose Riverpod service providers
  4. _clearGoogleSession()           — GoogleSignIn().signOut() (platform call)
  5. FirebaseAuth.instance.signOut() — invalidate Firebase token
  6. AuthBootstrapperController.rebootstrap() → WelcomeScreen
```

Google sign-out (step 4) **must** happen before Firebase sign-out. Without it
the next "Continue with Google" call silently reuses the previous account.

## Google Sign-In — forced account chooser

`AuthService.signInWithGoogle()` calls `googleSignIn.signOut()` before
`googleSignIn.signIn()`. This forces the OS-level account chooser every time,
matching Instagram / Uber / Airbnb behavior.

The web path uses `{'prompt': 'select_account'}` for the equivalent effect.

## Bug history

| Bug | Root cause | Fix |
|---|---|---|
| Reinstall restores session | Android Keystore survives uninstall | Fresh-install guard in `main.dart` |
| Logout restores session | `_signOut()` never called `_clearGoogleSession()` | Added step 4 to logout flow |
| Google chooser skipped | `signIn()` reused cached Google session | `signOut()` before `signIn()` in `AuthService` |

## Deferred Services

| Service | When started |
|---|---|
| UserPresenceService | First frame (addPostFrameCallback) |
| PushNotificationService | First frame (addPostFrameCallback) |
| Deep link handler | First frame (addPostFrameCallback) |
| Chat unread Firestore listener | 3 s after map renders |
| Events Firestore stream | After `onMapReady` fires |
| Event expiry pruner | `initState` (Timer.periodic 1 min — cheap) |

## Performance Notes

- `BackdropFilter` sigma reduced from 8 → 4 in search bar (GPU compositing cost)
- Hive boxes opened in parallel at boot (was sequential, ~3× faster)
- `_startEventExpiryPruner()` is a 1-minute timer — negligible startup cost
- `_notifCountStream` (ActivityNotificationService) starts at map init — defer
  if startup regresses further

---

# Profile Architecture (redesign)

The profile is one screen — `SocialProfileScreen` (`lib/screens/profile_social_screen.dart`)
— composed of `part` files (one `_SocialProfileScreenState`). It renders **three
states** off `_isOwnProfile` + `FriendRelationshipState`. It is hosted as tab 3 of
`MapScreen` (`Visibility(maintainState: true)`) and pushed as a route for other users.

> `lib/screens/profile_screen.dart` (`ProfileScreen`) is **dead code** (imported by
> nothing). Do not wire it up; the live screen is `SocialProfileScreen`.

## Part-file layout

| File | Role |
|---|---|
| `profile_social_screen.dart` | State + `build()` skeleton, top-level layout |
| `controllers/profile_data_controller.dart` | Profile-doc sync (`_syncProfileFromSnapshot`), member-since/vibes parse, friend-state stream, `_loadProfileData` |
| `controllers/profile_media_controller.dart` | Avatar/banner pick + upload (unchanged) |
| `controllers/hosted_events_controller.dart` | Hosted-event paging + `_liveHostedEvents` + `_buildHostedEventCard` + date parsing |
| `controllers/profile_view_controller.dart` | Top bar, About (bio), `_glassButton`, blocked/error views |
| `controllers/profile_sections_data.dart` | **NEW** — interest-tags, friends preview, joined events (lazy), shared-events count |
| `controllers/profile_sections_view.dart` | **NEW** — identity, tags, member-since, connection cards, friends strip, Hosting Now, Events tabs, save toggle |
| `controllers/friend_action_controller.dart` (features/friends) | Friend actions, 3-dot menus, logout, report |
| `widgets/profile_media_header.dart` | `StaticProfileMediaHeader` (banner + centered avatar, upload affordances) |

## Layout order (`build()` Column)

TopBar → `StaticProfileMediaHeader` → Identity (name + verified + username) → Bio →
Interest Tags → Member Since → Action Buttons → Connection Context Card →
Friends Strip → Hosting Now → Events Tabs.

**The old stats row (Friends / Joined / Hosted counts) was removed** along with its
three `includeMetadataChanges` count streams, the stats-warmup timer, and the shimmer
placeholders — fewer listeners, no primary-metric clutter.

## Three states

| State | Action area | Context card |
|---|---|---|
| Own (`_isOwnProfile`) | "Edit Profile" (solid) | none |
| Stranger (`notFriend`/`requestSent`/`requestReceived`) | Add Friend / Requested / Accept+Decline | **"Why you should connect"** (mutual friends, active-in-category, active host) |
| Friend (`friend`) | "Friends ▼" + "Message" | **"Connection"** (connected, mutual friends, shared events) |

The context card and friends ordering both read the **same** `_cachedFriendStateStream`
(`friendStateStream`, a `Stream.multi` — safe to listen to from multiple `StreamBuilder`s).

## Three-dot / dropdown menus

| Surface | Items |
|---|---|
| Own 3-dot | Edit Profile · Share Profile · Blocked Users · Settings · Logout |
| Friend "Friends ▼" | Remove Friend · Block User · Report User |
| Stranger 3-dot | Share Profile · Block/Unblock · Report User |

- **Logout** mirrors the Settings `_signOut` flow exactly (LocalProfileCache.clear →
  ChatPeerCache.clear → invalidate `chatRepositoryProvider`/`eventServiceProvider`/
  `exploreRecommendationServiceProvider` via `ProviderScope.containerOf` →
  GoogleSignIn().signOut() → FirebaseAuth.signOut() → `rebootstrap`). Google sign-out
  **before** Firebase sign-out (see Authentication Architecture).
- **Report User** → `SafetyReportingScreen`.

## Interest Tags (derived — no new collection)

`_loadInterestTags()` ranks tags by frequency from the user's event `tags`:
- hosted events (public-only for non-own profiles)
- **own profile also** folds in joined-event tags (a stranger must never be able to
  infer which private events someone joined)
- falls back to the onboarding `vibes` field when there is no event history

Top 5, title-cased. Empty → section hidden.

## Member Since

Parsed from `users/{uid}.createdAt` (or legacy `created_at`) in `_syncProfileFromSnapshot`.
Rendered `"Member since <MMMM yyyy>"`. Missing timestamp → row hidden (old accounts safe).

## Friends Strip / Hosting Now / Events tabs

- **Friends:** `FriendService.getFriendsList` (batched `whereIn`, no N+1). On a friend/
  stranger profile, mutual friends are ordered first and ringed (`AppUserAvatar.showRing`).
  Count label + "View All" → `ConnectionsScreen(initialTab: 'friends')`. Avatar tap →
  that user's `SocialProfileScreen`.
- **Hosting Now:** single featured card = `_liveHostedEvents.first` (public for non-own).
  Hidden entirely when there is no live hosted event — **no empty/placeholder card**.
- **Events tabs:** Hosting (`_hostedEvents`) | Joined (`_joinedEvents`, lazy-loaded on
  first tab open). Joined events for non-own profiles are filtered to public. Card tap →
  `EventDetailScreen`.

## Privacy rules enforced

Never surfaced for other users: phone, email, private events, joined-private-event
inference. Non-own hosted/joined/shared queries all add `visibility == 'public'`.

## Saved Events (private, owner-only)

New feature — **`SavedEventsService`** (`lib/services/saved_events_service.dart`) over a
**private** subcollection `users/{uid}/savedEvents/{eventId}` (pointer = `eventId` +
`savedAt`). Only the owner reads/writes it; saved events are **never** shown on anyone
else's profile.

- Bookmark toggle (`isSavedStream` + `toggleSaved`) on the **event detail** header (beside
  Share) and on the profile **Hosting Now** card.
- **`SavedEventsScreen`** (`lib/screens/saved_events_screen.dart`) lists them (re-fetches
  live `events/{id}` docs so deleted events drop out; swipe-to-remove). Reached from
  **Settings → SOCIAL → Saved Events** (per product decision, not the profile 3-dot).

> ⚠️ **Firestore rules requirement:** the owner must be allowed read/write on
> `users/{uid}/savedEvents/**`. The common `match /users/{uid}/{document=**} { allow
> read, write: if request.auth.uid == uid; }` rule already covers it. There is no
> `firestore.rules` file in-repo (rules live in the Firebase console) — verify there.

## Backward compatibility

No schema migration. Only a **new** private subcollection is added; no existing field/
collection is changed. Every redesigned section degrades to hidden when its data is
absent, so legacy accounts (no `vibes`, no `createdAt`, no events, no friends) render
cleanly. Reused existing fields throughout: `vibes`, `createdAt/created_at`, event `tags`,
`friends/{uid}/list`, `participants`.

---

# Event Creation Architecture

## Flow (4-step wizard in `_CreateEventSheet`)

| Step | Title | Fields |
|---|---|---|
| 1 | About | Avatar picker, Event name (required), Description |
| 2 | Location | Map location picker (required), Privacy toggle, Tags |
| 3 | Details | Capacity (required), Date & time (required), **Meeting Point**, Visibility, Approval, Age range, Banner |
| 4 | Preview | Quality Score + Recommendations + live event preview + cover upload prompt |

## Back Navigation

- Footer shows a **"← Back"** labelled button on steps 2, 3, and 4.
- `_prevPage()` calls `PageController.previousPage()` — the `PageView` holds all pages in memory.
- All form state lives at `_CreateEventSheetState` level (`_formModel`, `TextEditingController`s, `_selectedLocation`, etc.) — nothing is lost when navigating back.
- Validation errors are reset when going back (only shown on "Next"/"Publish Event" tap).

## Event Preview (Step 4)

- Quality Score: 0–100 calculated from title (+20), description (+20), date (+15), location (+15), meeting point (+10), cover image (+20)
- Score labels: 0–39 "Needs more detail", 40–69 "Good start", 70–89 "Looking good", 90–100 "Ready to publish"
- Recommended Improvements: non-blocking list of missing fields — no red/shame states, positive framing
- Cover image upload: shows prompt with "+20 quality points" incentive if no cover; live score update on upload
- Auto fallback banner: gradient based on `_colorFromTags()` with event avatar centered (no cover needed for preview)
- Cover guidance text: "Landscape image, 16:9 format" — never pixel dimensions
- Publish button: "Publish Event" — no decorative emojis anywhere in the step
- Design rule: NO decorative emojis (no ✨ 🚀 🎉 🔥 ⭐) in any heading, button, hint, score, or message — clean typography + icons only

## Event Cover Architecture

### Selection flow
1. User taps the banner picker (step 3 Details or step 4 Preview upload prompt)
2. `image_picker` opens gallery (`maxWidth: 2048, maxHeight: 2048, imageQuality: 95`)
3. `CoverCropScreen` opens fullscreen with `crop_your_image`
4. User pans/pinches image within a fixed 16:9 frame (`fixCropRect: true, interactive: true`)
5. User taps "Use" → `CropController.crop()` → `onCropped(Uint8List)` fires
6. `flutter_image_compress` compresses to JPEG (1280×720 min, quality 88)
7. Saved to `getTemporaryDirectory()` → path returned to sheet state via `Navigator.pop`
8. `_formModel.bannerImagePath` updated → preview card re-renders with cropped image

### Key file
- `lib/screens/cover_crop_screen.dart` — standalone fullscreen widget
- Accepts `imagePath`, returns cropped file path or null (cancel)

### Design rules
- Black background (standard for image editing UIs)
- Top bar: Cancel | Cover | Use (blue button)
- Hint: "Pinch to zoom · Drag to reposition"
- No pixel dimension guidance shown to user — guidance only in picker: "Landscape image, 16:9 format"

## Event Location Selection Architecture

### Flow
```
User taps location picker → MapPickerScreen opens
  Search bar (top overlay)
    ↓ type ≥ 3 chars → debounce 400ms → Nominatim geocoding
    ↓ results dropdown appears
    ↓ user taps result → camera animates to place (smooth 16-step ease-out)
  User can further drag/tap map to fine-tune exact point
  Bottom panel shows: place name + lat/lng coordinates
  User taps "Confirm Location" → returns {lat, lng, name}
```

### Key files
- `lib/screens/map_picker_screen.dart` — rewritten with search overlay

### Search implementation
- **API**: Nominatim OpenStreetMap (`nominatim.openstreetmap.org/search`)
- **No API key required** — free, open usage policy
- **Debounce**: 400ms after each keystroke, triggered at ≥ 3 chars
- **Cache**: `Map<String, List<_PlaceResult>>` in-memory per session
- **User-Agent**: `Yanegi/1.0` (required by Nominatim usage policy)
- **Limit**: 6 results per query
- **Accept-Language**: `en` (English results)
- Supports: landmarks, buildings, colleges, cafes, parks, stadiums, metro stations, addresses

### Location name propagation
- `MapPickerScreen` returns `{lat, lng, name}` (name = first part of Nominatim display_name)
- `create_event_sheet.dart` stores name in `_selectedLocationName` state variable
- Shown in: location picker button label, event preview card, `createEvent(locationName:)` call
- Falls back to `'Location selected'` for map tap (no Nominatim lookup on manual tap)

### Removed restrictions
- 50km radius restriction from original picker was removed — users can create events anywhere

## Meeting Point Field

- **Model**: `EventCreationModel.meetingPoint` (String, default `''`)
- **Creation**: Text field on step 3, between Date/Time and Visibility
- **Service**: `EventService.createEvent()` accepts `meetingPoint`; written to Firestore only when non-empty (omit-if-empty pattern avoids polluting existing docs)
- **Detail screen** (`event_detail_screen.dart`): "MEETING POINT" section hidden entirely when field is null or empty — no fake fallback values
- **Existing events**: Null-safe — `eventData['meetingPoint']` null/empty → section hidden, no crash

## Event Data Schema (Firestore `events` collection)

Key fields relevant to creation:

```
title           String   required
description     String   optional
location        String   locationName
lat / lng       double   precise coords
locationGeoPoint GeoPoint
approximateLocation {lat, lng}
startAt         Timestamp UTC
endAt           Timestamp UTC (startAt + 2 h default)
maxCapacity     int      ≥ 2
visibility      String   'public' | 'private'
isApprovalRequired bool
hideExactLocationUntilApproved bool
eventAvatar     String   asset path or emoji
bannerUrl       String   Storage URL (optional)
tags            List<String>
ageRange        {min, max}
meetingPoint    String   optional — omitted if empty
chatId          String   'grp_<eventId>'
hostId          String
participants    List<String>
participantsCount int
status          String   'active'
isActive        bool
isDeleted       bool
```

## Navigation Architecture (MapScreen)

`MapScreen` is the root shell. It hosts 4 tabs via `_navIndex`:

| Index | Tab | Widget |
|---|---|---|
| 0 | Map | `FlutterMap` + markers |
| 1 | Explore | `ExploreListWidget` |
| 2 | Chat | `ChatHubScreen` |
| 3 | Profile | `SocialProfileScreen` |

All tabs use `Visibility(maintainState: true)` — they are built once and hidden/shown. State is never discarded on tab switch.

Deep-links (`/event/<id>`, `/profile/<id>`) push a `MaterialPageRoute` on top of `_navigatorKey` — handled in `_handleDeepLink`.

---

# Notification Architecture

## Notification Flow

```
Action occurs (e.g. join request, friend request, shoutout)
  → NotificationService.sendNotification() / ActivityNotificationService.createNotification()
  → Written to Firestore `notifications` collection
  → FCM Cloud Function picks up the Firestore write and sends push
  → ActivityScreen reads from Firestore via stream
  → PushNotificationService handles foreground FCM messages
```

## Two Display Contexts

Every stored notification is rendered in two contexts, both must be human-readable:

| Context | Source |
|---|---|
| Activity feed (in-app) | Firestore `notifications` doc — `senderName` prepended by `_line1ActionText()` in `activity_screen.dart` |
| Push notification | FCM title/body — falls back to `data['senderName']` as title, `data['message']` as body |

**Rule**: The `message`/`title` fields stored in Firestore must be complete sentences (not fragments) because they are used verbatim in push notifications where `senderName` is NOT automatically prepended.

## Notification Copy Standards

Every notification must answer: **WHO** did **WHAT** to **WHICH** thing, with a clear **NEXT ACTION**.

No developer jargon, no IDs, no vague system messages.

### Approved copy per type

| Type | Push title | Message / body |
|---|---|---|
| `friend_request` | senderName (FCM fallback) | `'sent you a friend request'` |
| `friend_accept` | senderName (FCM fallback) | `'accepted your friend request'` |
| `event_request` | senderName (FCM fallback) | `'wants to join: "$eventTitle"'` |
| `event_accept` | `'$hostName accepted your request to join $eventTitle'` | same |
| `event_reject` | `'$hostName declined your request to join $eventTitle'` | same |
| `chat_message` (DM) | senderName | `'sent you a message: "$preview"'` |
| `chat_message` (group) | senderName | `'sent a message in your group: "$preview"'` |
| `mention` | senderName | `'mentioned you in $chatTitle'` |
| `nearby_event` | senderName | `'A new event "$title" is happening near you.'` |
| `friend_joined_event` | senderName | `'$joinerName joined $eventTitle'` |
| `waitlist_spot_available` | `'A spot opened in $eventTitle'` | `'A spot opened in $eventTitle. Join now before it fills up!'` |
| `shoutout` | senderName | `'gave you a shoutout after $eventTitle'` — NO emoji |
| `post_event_recap` | senderName | `'How was your event? Share your recap'` |

## Activity Screen Rendering Rules

- `_line1ActionText()` in `activity_screen.dart` — always check stored `notification.message` for types where the copy varies (chat, mention, shoutout, waitlist). Hardcode for types where copy is uniform (friend_request, event_request, etc).
- `_line2Text()` — shows the event name as a tappable underlined link (no "Join" prefix). Chat messages without eventId show "Open conversation".
- `_buildSecondLine()` — renders the event name as tappable text only (no "Join" verb). The whole tile is tappable anyway.
- `_shouldDisplayNotification()` — `event_reject` and declined `friend_request` are hidden from activity feed (no shame states).

## UX Rules

- No decorative emojis anywhere (no 🎉 🚀 ✨ 🔥 ⭐)
- No technical IDs or error codes shown to users
- Error messages use `ErrorHandler.showUserMessage()` with `AppErrorType` enums
- Snackbar for join approval flow: `'Join request sent.'` (period, not vague "Requested")
- Snackbar for direct join: `'You joined the event.'`

## Files

| Concern | File |
|---|---|
| Notification write (low-level) | `lib/services/notification_service.dart` |
| Notification write (high-level, with sender lookup) | `lib/services/activity_notification_service.dart` |
| Friend notifications | `lib/services/friend_service.dart` |
| Event join/approval notifications | `lib/features/event/event_service_join_approval.dart` |
| Event reject notification | `lib/services/activity_notification_service.dart:declineEventRequest` |
| Chat message notifications | `lib/chat/data/firebase_chat_repository.dart` |
| Mention notifications | `lib/features/chat/controllers/chat_mention_controller.dart` |
| Nearby event / waitlist notifications | `lib/services/event_service.dart` |
| Shoutout notifications | `lib/screens/event_recap_screen.dart` |
| Activity feed rendering | `lib/screens/activity_screen.dart` |
| Foreground push display | `lib/services/push_notification_service.dart` |
| Notification types constants | `lib/services/notification_types.dart` |

---

# Image & Notification Avatar Architecture

## Notification Avatar Matrix

Every notification type has a defined leading image. Rule: **the entity that is acting provides the image.**

| Notification Type | Image Shown | Rationale |
|---|---|---|
| `friend_request` | Sender profile photo | A person is acting |
| `friend_accept` | Sender profile photo | A person is acting |
| `event_request` | Requester profile photo | A person is acting (NOT the event) |
| `event_accept` | Event cover image | The event is acting |
| `event_reject` | Event cover image | The event is acting |
| `event_created` (nearby) | Event cover image | The event is the subject |
| `waitlist_spot_available` | Event cover image | The event is acting |
| `post_event_recap` | Event cover image | The event is the subject |
| `chat_message` (DM) | Sender profile photo | A person is acting |
| `chat_message` (group, chatId starts with `grp_`) | Event cover image | The group event is the context |
| `mention` | Sender profile photo | A person is acting |
| `friend_joined_event` | Sender profile photo | A person is acting |
| `shoutout` | Sender profile photo | A person is acting |

**Implemented in:** `activity_screen.dart:_buildNotificationLeadingMedia` and `_buildEventThumbnail`

## Event Thumbnail Fallback

When an event has no cover image, show a branded gradient background with `Icons.event_rounded` (NOT a generic placeholder icon).

## Profile Photo Fallback

When a user has no profile photo, show `Icons.person_rounded` on a branded gradient background via `AppUserAvatar` (NOT an empty grey circle or broken image).

## Image Consistency Rules

| Entity | Image Source | Widget |
|---|---|---|
| User (everywhere) | `avatarUrl` / `photoUrl` from Firestore user doc | `AppUserAvatar` |
| Event cover (full) | `bannerUrl` / `bannerImagePath` from events doc | `AppBannerImage` |
| Event cover (thumbnail) | Same URL, constrained via `memCacheWidth` | `_buildEventThumbnail` or direct `CachedNetworkImage` |
| Group chat avatar | Event `bannerUrl`, falls back to `eventAvatar` emoji/asset | `EventCategoryAvatar` |
| DM chat avatar | User `avatarUrl` | `AppUserAvatar` |

**Rule:** Never branch on avatar type in calling code. Let the shared widgets (`AppUserAvatar`, `AppGroupAvatar`, `EventCategoryAvatar`, `AppBannerImage`) handle all fallback logic.

## Image Cache Strategy

`cached_network_image ^3.4.0` provides both disk cache (default 7 days) and memory cache. To prevent large images from being decoded at full resolution for small display slots, `memCacheWidth`/`memCacheHeight` constraints are set at every call site.

### Cache Size by Use Case

| Use Case | Display Size | `memCacheWidth` | `memCacheHeight` |
|---|---|---|---|
| `AppUserAvatar` | `radius × 2` logical px | `(radius × 3).ceil()` | same |
| `AppGroupAvatar` | `radius × 2` logical px | `(radius × 3).ceil()` | same |
| `EventCategoryAvatar` | `radius × 2` logical px | `(radius × 3).ceil()` | same |
| Notification event thumbnail | 46 × 46 logical px | 92 | 92 |
| Chat hub tiny avatar overlay | 14 × 14 logical px | 42 | 42 |
| Share card bubble avatar | 40 × 40 logical px | 120 | 120 |
| Share card bubble banner | 100px height strip | 500 | 200 |
| Profile hosted event card | 132px height | 600 | 264 |
| Connections screen event card | 140px height | 600 | 280 |
| Explore feed event image | ~full card width | 600 | — |
| `AppBannerImage` (full width) | ~screen width | 800 | — |
| Event detail banner (full width) | full screen width | 800 | — |
| Full-screen image viewer | Full screen | no constraint | — |

### Cache Lifecycle

- **First load:** Network fetch → stored on disk (7 days) + in memory
- **Second load (same session):** Memory hit — instant, zero network
- **Third load (new session):** Disk hit — fast, zero network
- **Memory pressure:** Flutter's `ImageCache` evicts LRU entries; `memCacheWidth` constraints keep each entry small so more images fit in memory

### Performance Rules

- Never use raw `Image.network()` — always use `CachedNetworkImage` or `AppUserAvatar`/`AppBannerImage`
- Never use `CachedNetworkImage` for avatars without `memCacheWidth`/`memCacheHeight` — full-res decodes waste memory for small slots
- The `CachedNetworkImageProvider` (used for `DecorationImage`) does not support `memCacheWidth` — avoid it for avatar slots; use `AppUserAvatar` instead
- Full-screen viewers (`AppImageViewer`, avatar expand dialog) intentionally have no memory cache constraint — users open these to see full detail

## Shared Image Widgets

| Widget | File | Purpose |
|---|---|---|
| `AppUserAvatar` | `lib/widgets/app_avatars.dart` | All person avatars. Handles empty URL, error, fallback person icon. |
| `AppGroupAvatar` | `lib/widgets/app_avatars.dart` | Group/generic image avatars. |
| `EventCategoryAvatar` | `lib/widgets/app_avatars.dart` | Event chat rows. Priority: banner URL → asset avatar → emoji → generic fallback. |
| `AppBannerImage` | `lib/widgets/app_banner_image.dart` | Full-width event/profile banners. |

## Estimated Firebase Storage Savings

Memory cache constraints reduce the number of full-resolution images decoded per session:

- Avatars rendered at 44px were previously decoded at full resolution (often 400–800px source). With `memCacheWidth: 66`, the same source image is decoded once at 66px and reused from memory — **~95% memory reduction per avatar slot**.
- Event banners capped at 800px prevent decoding 2000px+ source images for standard mobile screens.
- The blur placeholder overlay (explore feed) is now capped at 120px since it is displayed blurred — previously decoded at full source resolution for no visual benefit.

## Validation Checklist

- [x] Notification images follow the avatar matrix (event_request shows requester photo, not event banner)
- [x] DM notifications show sender profile photo
- [x] Group chat notifications show event cover image
- [x] All event-acting notifications show event cover
- [x] `AppUserAvatar` shows `Icons.person_rounded` fallback (no broken placeholder)
- [x] Event thumbnails show branded gradient + event icon when no cover (no generic `Icons.image`)
- [x] `memCacheWidth`/`memCacheHeight` set at every `CachedNetworkImage` call site except full-screen viewers
- [x] `flutter analyze` passes with zero errors

---

# Event Sharing Architecture

## Entry Point

`_shareEvent()` in `event_detail_screen.dart` opens `showEventShareSheet()`.
Passes `isHost` (Firestore `hostId == currentUserId`) and `isParticipant`
(`userState == UserEventState.joined && !isHost`).

## Share Sheet (`lib/screens/event_share_sheet.dart`)

`EventShareSheet` is a `DraggableScrollableSheet` with four actions:

| Action | Mechanism | Platforms |
|---|---|---|
| Send in Chat | `showShareToChatSheet` → DM card | Yanegi internal (optional, shown when `onShareInChat` provided) |
| Share Card | PNG capture → `Share.shareXFiles` | WhatsApp, Instagram, Telegram, Discord, any image-accepting platform |
| Share Link | text + deep link → `Share.share` | X, LinkedIn, Facebook, SMS, email |
| Copy Link | `Clipboard.setData` | paste anywhere |

Sheet also shows a live **MESSAGE PREVIEW** block with the generated copy.

## Share Card (`lib/widgets/event_share_card.dart`)

Fixed 360 × ~460 logical px widget, captured at 2× → ~720 × ~920 px PNG.

Layout:
1. Cover image (200px) — event `bannerUrl`, or category gradient fallback with event avatar centered
2. YANEGI wordmark badge (top-right over image)
3. Bottom fade overlay
4. Event title (bold, max 2 lines)
5. Date/time row — `Icons.calendar_today_rounded`
6. Location row — `Icons.location_on_rounded`
7. Participant count — `Icons.people_alt_rounded`
8. `yanegi.app` footer

## Share Service (`lib/utils/event_share_service.dart`)

### Text generation

| Scenario | Template |
|---|---|
| Host | `I'm hosting [Title] on [Day, Mon D].\n\n[Tagline]\n\nJoin through Yanegi:\n\n[link]` |
| Participant | `I'm joining [Title] on [Day, Mon D].\n\n[Tagline]\n\nLooks interesting:\n\n[link]` |
| No role | `[Title] on [Day, Mon D].\n\n[Tagline]\n\nCheck it out on Yanegi:\n\n[link]` |

Tagline is omitted when empty (no matching tag category).

### Category taglines

| Tags | Tagline |
|---|---|
| music, concert, dj | "A night of great music." |
| sports, fitness, running, outdoor | "Come stay active." |
| startup, networking, business | "Grow your network." |
| tech | "Connect with the tech community." |
| food, dinner, brunch, drinks | "Good food, good company." |
| art, culture, exhibition | "An evening of culture and creativity." |
| gaming, game, esports | "Compete, connect, and level up." |
| study, workshop, lecture, education | "Learn something new." |
| party, social | "Should be a great time." |
| indoor | "A great indoor experience." |
| (no match) | (omitted) |

### Category gradients (cover fallback)

Each category maps to a two-stop dark gradient. Default: `[#1C1C28, #0A0A0F]`.

### Deep link format

`https://yanegi-684f9.web.app/event/{Uri.encodeComponent(eventId)}`

### Card capture

`RepaintBoundary` → `RenderRepaintBoundary.toImage(pixelRatio: 2.0)` →
`ImageByteFormat.png` → `File(tmpDir/yanegi_share_{eventId}.png)` →
`Share.shareXFiles([XFile], text: deepLink)`.

## Design Rules

- No decorative emojis anywhere — card uses `Icons.*` only
- No marketing copy — card shows only factual event data
- Category gradient renders correctly with no cover image
- `onShareInChat` callback is optional — not present hides the "Send in Chat" tile

## Files

| Concern | File |
|---|---|
| Share data model + service | `lib/utils/event_share_service.dart` |
| Share card widget | `lib/widgets/event_share_card.dart` |
| Share bottom sheet | `lib/screens/event_share_sheet.dart` |
| Entry point (share button) | `lib/screens/event_detail_screen.dart:_shareEvent` |

---

# Social Sharing Preview Architecture (Open Graph SSR)

## Root Cause (Fixed)

`firebase.json` previously rewrote `/event/**` to `link.html` — a **static file**.
Social crawlers (WhatsApp, Telegram, Discord, Facebook, X, LinkedIn) do **not** execute
JavaScript. They only read `<head>` meta tags from the raw HTML response.
`link.html` had hardcoded static OG tags:

```html
<meta property="og:site_name" content="Yanegi" />
<meta name="og:description" content="Join events, meet people, live local." />  <!-- wrong attribute: name= not property= -->
<!-- NO og:title -->
<!-- NO og:image -->
```

Every event URL showed the same generic Yanegi card on every platform.

## Fix Architecture

### Cloud Function: `eventPreview` (`functions/index.js`)

Handles every `/event/{eventId}` request. Returns a complete HTML page whose `<head>`
contains per-event OG meta tags — readable without JavaScript.

```
Request: GET /event/abc123
  → eventPreview Cloud Function
  → Firestore: events/abc123  +  users/{hostId}
  → Returns HTML with:
       og:title       = "Startup Meetup"
       og:description = "Wed, 18 Jun · 5:00 PM · Ranchi University · 14 going · Hosted by Rahul"
       og:image       = bannerUrl (or omitted if no cover)
       twitter:card   = summary_large_image
  → Body: pre-rendered event card (visible to humans + crawlers that read body)
  → Script: deep-link redirect to app (Android intent / iOS custom scheme)
```

### `firebase.json` rewrite change

```json
// Before (static file — crawlers can't read dynamic data):
{ "source": "/event/**", "destination": "/link.html" }

// After (Cloud Function — server-side rendered OG tags):
{ "source": "/event/**", "function": "eventPreview" }
```

## Preview Fields Per Platform

| Field | Source | Example |
|---|---|---|
| `og:title` | `events.title` | "Startup Meetup" |
| `og:description` | date · location · count · host | "Wed, 18 Jun · 5:00 PM · Ranchi University · 14 going · Hosted by Rahul" |
| `og:image` | `events.bannerUrl` | Firebase Storage URL |
| `og:url` | deep link | `https://yanegi-684f9.web.app/event/{id}` |
| `twitter:card` | hardcoded | `summary_large_image` |

If `bannerUrl` is empty: `og:image` tag is **omitted** (better than a broken placeholder).
If host fetch fails: description still includes date, location, and count.
If event is deleted or not found: function redirects to `/link.html`.

## Fallback Behavior

| Scenario | Behavior |
|---|---|
| Function deployed + event exists | Full per-event OG tags |
| Function deployed + event not found | Redirect → `/link.html` |
| Function deployed + Firestore error | Serve default "Event on Yanegi" OG tags (no crash) |
| Function not yet deployed | Old static link.html served (improved with correct `property=` attributes) |

## Deployment Command

```bash
firebase deploy --only functions:eventPreview,hosting
```

Run this from the project root after any change to `functions/index.js` or `firebase.json`.

## OG Image Note

Events with a `bannerUrl` automatically get a rich image preview.
For events without a cover image, `og:image` is omitted — platforms show title +
description without an image, which is still far better than the old generic card.

To add a universal Yanegi fallback image: upload a 1200×630 PNG to
`public/og-default.png` and change the `ogImage` default in `eventPreview` to
`${BASE_URL}/og-default.png`.

## Files Modified

| File | Change |
|---|---|
| `functions/index.js` | Added `eventPreview` Cloud Function (SSR OG tags) |
| `firebase.json` | Changed `/event/**` rewrite from `destination: link.html` to `function: eventPreview` |
| `public/link.html` | Fixed `name="og:..."` → `property="og:..."` bug; added `og:title`; used as fallback for `/profile/**` only |

---

# Environment Separation (Dev / Prod)

Two fully isolated Firebase projects. Selection is **compile-time**, defaults to prod.

| | Production | Development |
|---|---|---|
| Firebase project | `yanegi-684f9` | `yanegi-dev` |
| Sender / project number | `266662976182` | `437216733779` |
| Android applicationId | `com.yanegi.app` | `com.yanegi.app.dev` (suffix) |
| google-services.json | `android/app/google-services.json` (root, untouched) | `android/app/src/dev/google-services.json` |
| FirebaseOptions | `lib/firebase_options.dart` (`DefaultFirebaseOptions`) | `lib/firebase_options_dev.dart` (`DevFirebaseOptions`) |
| Hosting base URL | `https://yanegi-684f9.web.app` | `https://yanegi-dev.web.app` |
| Gradle flavor | `prod` | `dev` |

## How selection works
- `lib/config/app_environment.dart` reads `const String.fromEnvironment('APP_ENV', defaultValue: 'prod')`.
  Exposes `firebaseOptions`, `webBaseUrl`, `isDev`/`isProd`. **Default = prod** → a build that forgets the
  define stays safe on production.
- Android **flavor** picks the `google-services.json` (Gradle Google-Services plugin resolves
  `src/<flavor>/` first, falls back to module root for prod — so the prod file never moves).
- The Dart `APP_ENV` define and the Gradle `--flavor` must agree; the build commands below keep them in sync.

## Build / run commands
```
# Production (live app)
flutter run   --flavor prod                                    # debug
flutter build appbundle --flavor prod --dart-define=APP_ENV=prod   # release → Play Store

# Development (isolated)
flutter run   --flavor dev  --dart-define=APP_ENV=dev
flutter build apk --flavor dev --dart-define=APP_ENV=dev
```
> Once flavors exist, a bare `flutter run` (no `--flavor`) no longer works — always pass `--flavor prod|dev`.
> Google Sign-In: Android uses the OAuth client inside the flavor's google-services.json automatically
> (`GOOGLE_WEB_CLIENT_ID` dart-define is web-only). Dev debug SHA-1 is already registered in yanegi-dev.

## Rules / functions per project (Task 6)
`.firebaserc` aliases: `prod` → yanegi-684f9, `dev` → yanegi-dev (default stays prod).
```
firebase deploy --only firestore:rules,storage:rules -P dev    # push same rules to dev
firebase deploy --only firestore:rules,storage:rules -P prod   # prod (unchanged workflow)
```
Same `firestore.rules` / `storage.rules` source → no drift between environments.

## Rollback
All changes are in-repo code/config; no production data or backend was modified. Revert the env files
(`lib/config/app_environment.dart`, `lib/firebase_options_dev.dart`, the gradle flavor block,
`android/app/src/dev/`, `.firebaserc`) and restore `options: DefaultFirebaseOptions.currentPlatform` in
`main.dart` to return to single-env. Prod build values were never touched.

## Local build note
This machine has **JDK 25**, which the project's Kotlin Gradle plugin cannot parse
(`IllegalArgumentException: 25.0.2`). Build via Android Studio's bundled JBR or set
`JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home` (Java 21) for CLI Gradle.
