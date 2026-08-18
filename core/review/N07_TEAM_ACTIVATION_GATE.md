# N07 — Team feed activation gate

**Status: NOT IMPLEMENTED, and this document is not a plan to implement it.**

`/team/:teamId` is declared at `mobile/lib/core/router/app_router.dart:349`, builds
`TeamFeedPage`, and nothing in `lib/` navigates to it. It is deferred as a product decision:
wiring it ships a Celebrity-tier feature no user has exercised, and deleting it removes intended
work during an audit. `N07 = KEEP`.

This file exists because the *deferral* is safe and the *activation* is not. It is the checklist a
future author must satisfy before binding a real repository, and it is referenced by the tripwire
in `mobile/test/adversarial/n07_team_activation_test.dart`, which fails the moment
`teamFeedRepositoryProvider` is overridden without a Firestore rule to match.

## Why a gate rather than a fix

Three measured facts, at HEAD:

1. **The route is auth-gated.** `/team/:teamId` is absent from `_publicPaths`
   (`app_router.dart:51`), so `resolveRedirect` sends an unauthenticated visitor to `/login`.
   A deep link does not bypass sign-in.
2. **There is nothing on a server to leak.** `firestore.rules` contains no `match` for any team or
   community collection; `main.dart` binds no `TeamFeedRepository`; the default is
   `MockTeamFeedRepository`, so `teamFeedIsDemoProvider` is true and the page shows a demo banner.
   Today the unreachable page reads an in-memory map that vanishes on restart.
3. **The tier lock is client-side and partial.** `_PostCard(locked: !isPremium)` substitutes a
   "sustainer only" string for `post.body` — but the author name, avatar, timestamp, pin state and
   **title** are rendered above that branch, and the whole post document reaches the device either
   way. Reaction counts are hidden; the title is not.

Fact 3 is harmless while fact 2 holds. The two are only one line of `main.dart` apart.

## The gate

Every item is required. None of them is "Teams is implemented"; they are the conditions under
which implementing it would not ship a paywall made of a string.

### Server-side authorisation

- [ ] **Server-side membership authorisation.** A Firestore rule (or a callable that mediates every
      read) that returns a post only to a uid that is a member of that team. Membership must be
      readable by the rule without a client-supplied claim.
- [ ] **Server-side tier authorisation.** The Celebrity tier must be checked where the data is
      served, not where it is drawn. The subscription tier already lives server-side; the rule must
      consult it rather than trusting `effectiveTierProvider`.
- [ ] **A rule in `firestore.rules`,** not only in a Cloud Function. The client reads Firestore
      directly today; a callable-only design must also close the direct path.
- [ ] **Locked metadata is not delivered.** If a non-member or non-subscriber must not read a post,
      the *document* must not reach them — author, title and timestamp included. Deciding instead
      that titles are public is a legitimate answer, but it must be a decision, written here.

### Negative tests, against the emulator

- [ ] **Cross-user:** user A, not a member of team T, is refused every document under T.
- [ ] **Cross-tier:** user B, a member of T on the free tier, is refused what the tier gates.
- [ ] **Deep link:** `/team/:teamId` reached directly, signed out and signed in as a non-member,
      lands nowhere useful and fetches nothing.
- [ ] **Unauthenticated:** no rule path grants an unauthenticated read.

These are emulator rules tests, not widget tests. A widget test proves the UI declined to draw
something; only a rules test proves the server declined to send it.

### Housekeeping

- [ ] `teamFeedIsDemoProvider` goes false by construction when the real repository is bound — it
      already does, being `repo is MockTeamFeedRepository`. Confirm the demo banner disappears.
- [ ] The tripwire test is updated in the same commit, so it guards the new state rather than
      being deleted to make the build green.
- [ ] A navigation entry point exists, or the route is removed. An activated feature nobody can
      reach is the current defect with more code behind it.

## What this gate does NOT decide

Whether SPTR should have a team feed at all. That is the product decision N07 defers, and nothing
here anticipates it. If the answer is no, the correct action is to delete the route, the page, the
repository and this file together — which is a cleanup gate, not an audit remediation.
