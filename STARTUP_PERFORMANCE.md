# Startup & Load-Time Performance Guide

Reference this before adding any new screen, provider, or startup-path code.
The app was tuned to open like WhatsApp/Telegram (instant, no visible
loading state on a warm launch); it's easy to silently regress that by
adding "just one more" network call or provider to the startup path.

## The one rule

**Nothing on the path from app icon tap to first interactive frame may
block on a network call.** Local disk/secure-storage reads are fine (they're
fast and unavoidable); a server round-trip is not. If a screen needs data
from the backend, it must follow the pattern in [`local_cache.dart`](lib/services/local_cache.dart):
show cached data (or nothing) immediately, fetch fresh data in the
background, update the UI silently when it arrives.

## What was actually slow, and what fixed it

### 1. `AuthProvider.bootstrap()` blocked on `/me`
**File:** `lib/state/auth_provider.dart`

Before: every cold start called `GET /me` to re-validate the stored token
*before* deciding whether to show anything. The first frame waited on a
full network round-trip.

Fix: a stored token is now trusted immediately (`isAuthenticated = true`
the moment `readToken()` resolves). `/me` still runs, but only in the
background to refresh `username`/`userId` for display — it no longer gates
what's shown. Side effect fixed for free: being offline at launch used to
force a logout (since a failed `/me` call was indistinguishable from an
invalid token); it no longer does. A truly invalid/expired token is still
caught correctly, the same way it always is mid-session — via
`ApiClient.onUnauthorized` firing on the first real 401 response.

**Rule going forward:** never add a "validate X on launch" network call
that the first screen waits on. Validate in the background; react to a 401
the same way the rest of the app already does.

### 2. `PersonaGate` blocked on its own network call, every single launch
**File:** `lib/screens/persona_gate.dart`

Before: `GET /persona` ran on every app open with its own spinner, even
though "has this user finished onboarding" essentially never changes once
true.

Fix: the completed flag is cached on-device
(`LocalCache.instance.getPersonaCompleted()` / `setPersonaCompleted()`, same
Hive box everything else uses). A returning user renders `HomeShell`
immediately from the cached flag; the network check still runs in the
background and corrects the cache if it's ever wrong.

**Rule going forward:** anything that's "check once, rarely changes again"
(feature flags, onboarding/setup completion, account-level settings that
don't change often) belongs in `LocalCache`, read synchronously at
`initState`, refreshed in the background — not re-fetched from the network
on every screen open.

### 3. Spinners shown even for a fast/cache-hit gate
**Files:** `lib/main.dart`, `lib/screens/persona_gate.dart`

Before: both gates above showed a `CircularProgressIndicator` while
resolving. Even once #1 and #2 made that resolution fast, a spinner flash
still *reads* as "the app is loading" — WhatsApp/Telegram never show one on
a warm start.

Fix: both loading states now render a blank `Scaffold` in the app's own
background color (`AppColors.bgApp`, matching the native launch splash)
instead of a spinner. Visually, the native splash appears to continue
straight into the real UI with nothing in between.

**Rule going forward:** if you ever add a loading gate that's expected to
resolve in well under a second, don't show a spinner for it — match the
splash background instead. Reserve real spinners/skeletons for things that
visibly take a while (see `ChatListSkeleton`/`MessageListSkeleton` for the
pattern used on genuinely slower, first-ever/no-cache loads).

### 4. `HomeShell` built all 5 tabs at once on mount
**File:** `lib/screens/home_shell.dart`

Before: the bottom-nav body was a plain `IndexedStack` with all 5 tab
screens (`ChatsScreen`, `TasksScreen`, `ProfilesScreen`, `FriendsScreen`,
`SettingsScreen`) as children. `IndexedStack` builds *every* child
regardless of which index is showing — so all 5 screens' `initState()` (and
whatever network/cache calls each one fires) ran simultaneously the instant
`HomeShell` mounted, all competing for the main thread right as the app is
trying to paint its first real frame.

Fix: tabs now build lazily. A `_visited` set tracks which tabs have ever
been opened; only those are actually built inside the `IndexedStack` (others
render an empty `SizedBox.shrink()` placeholder at their index). Only the
Chats tab (index 0) is in `_visited` initially. Once a tab is visited it
stays built (so switching back to it doesn't lose scroll position/state,
same as before) — this only changes *when* each tab's first build happens,
not the state-preservation behavior.

**Rule going forward:** never add a 6th tab (or any new "always-mounted"
top-level screen) that fetches data eagerly in `initState` without checking
whether it actually needs to run on app launch. If a new tab is added,
it'll automatically be lazy too as long as it goes through the same
`_visited`/`_builders` pattern — don't bypass it with a plain list of
screens again.

### 5. Debug build vs. release build
Not a code bug, but worth remembering: `flutter run` (no flags) produces a
**debug** build — Dart runs through a JIT/interpreter with a full VM
service attached for hot reload, which is inherently slower to cold-start
than a release build. WhatsApp on your phone is a release build. Always
compare against `flutter run --release` (or an installed release APK), not
a debug session, when judging whether startup is "fast enough."

## Backend caching (why screens *after* startup also feel instant)

Not startup-path, but the same "never block the UI on a network call"
principle extends into the app: chat/conversation screens show cached data
from `LocalCache` first and refresh from the network silently after (see
`chats_screen.dart`, `chat_thread_screen.dart`, `global_chat_screen.dart`,
`conversation_service.dart`). The backend (`speech2text/app.py`) mirrors
this server-side with Redis cache-aside reads in front of Postgres, so even
the *background* refresh those screens do is fast. See that repo's `app.py`
for the Redis caching/pub-sub layer if a new screen needs a new
cached-on-both-ends endpoint.

## Checklist before adding a new feature

- [ ] Does anything I'm adding run in `main()`, `AuthProvider.bootstrap()`,
      `PersonaGate`, or `HomeShell.initState()`? If yes: does it make a
      network call? If yes: move it to run in the background, not on the
      path to first frame.
- [ ] Does my new screen/provider fetch data in `initState()`? If it's a
      new bottom-nav tab, confirm it's wired through `HomeShell`'s
      `_builders`/`_visited` lazy pattern, not eagerly built.
- [ ] Am I about to add a `CircularProgressIndicator` for something that
      should resolve almost instantly (a cached/local check)? Use a blank
      splash-colored `Scaffold` instead, and cache the result in
      `LocalCache` so it doesn't need to run at all on the next launch.
- [ ] If I'm testing "does this feel slow," am I testing a release build,
      not a debug session?
