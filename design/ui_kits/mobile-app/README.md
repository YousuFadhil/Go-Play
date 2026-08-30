# Reference build

The authoritative visual reference for the frozen Club direction. Open
`index.html` in a browser.

Screen sources live in `../../screens/`; components in `../../components/`;
tokens in `../../tokens/`. This folder holds only the build entry point.

Read `../../HANDOFF.md` for the implementation specification.

## Screens

| Screen | File (in `../../screens/`) | Flutter source |
|---|---|---|
| Discover | `App.jsx` | `features/discover/` |
| Home | `Home.jsx` | `features/home/home_tab.dart` |
| Communities | `App.jsx` | `features/communities/communities_screen.dart` |
| Community details | `CommunityDetails.jsx` | `features/communities/community_details_screen.dart` |
| Match details | `MatchDetails.jsx` | `features/matches/match_details_screen.dart` |
| Create match | `CreateMatch.jsx` | `features/matches/create_match_screen.dart` |
| Profile | `Profile.jsx` | `features/profile/`, `features/statistics/` |
| Member management | `Members.jsx` | `features/members/member_management_screen.dart` |
| Invitation (share + landing) | `Invite.jsx` | `features/invitations/` |
| Teams / Arrange participants | `Teams.jsx` | `features/teams/`, `features/matches/arrange_roster_screen.dart` |
| Result entry | `Result.jsx` | `features/results/result_entry_screen.dart` |
| Notifications | `App.jsx` | `features/notifications/` |

## Structure

`../../screens/Shell.jsx` holds the pieces that are compositions rather than primitives: `TaskBar` and `TaskBody` (the task-screen shell), `ActionBar` (the pinned commit action), `RowGroup`, `FieldRow`, `OwnerLine`, `HeroFacts`. Everything else comes from `window.GoPlayDesignSystem_984b89`, compiled into `../../_ds_bundle.js`.

## Two shapes of screen

- **Places** — Discover, Home, Communities, Community, Match, Profile, Invitation. Green crest hero, light sheet over it, floating bottom nav.
- **Tasks** — Create match, Members, Teams / Arrange, Result entry, Notifications. Plain white `TaskBar`, no bottom nav, and where there is one commit action it is pinned in an `ActionBar` at the bottom.

## Role gating

`role` on the fixture community and match drives what appears. Admin and Owner see Create match, Invite, Manage, Teams, Result and the arrange handles; a Player sees none of them — the controls are absent, not disabled. Owner-only actions (transfer ownership, delete community, change an admin) appear only when `role === 'Owner'`.

## What is faked

All data is fixtures in `data.js`. No auth, no network, no push, no drag-and-drop physics on the arrange list (tap-to-swap works). Team generation shows a fixed split rather than running the BTGE engine.

## Review harness

The control bar above the phone is **not part of the product**. It is how a
reviewer or a Flutter engineer reaches states that would otherwise need a
backend to produce:

| Control | What it changes |
|---|---|
| **Role** | Owner / Admin / Player — regates every organizer control on Community Details, Match Details and Member Management |
| **State** | Populated / Loading / Empty / Error — swaps a screen's body for the skeleton, empty state or failed-read state. On Create Match it stands in for a failed submit and shows the validation errors |
| **You** | Confirmed / Reserve / Not in — the three registration states of the card on Match Details |
| **Dir** | EN / العربية — mirrors the layout **and** swaps the fixtures for deliberately long Arabic content (`window.GP_DATA_AR`) |
| **Width** | 320 / 412 / 480 — the three widths in the responsive spec |

Chrome strings stay English under العربية. The app already ships `app_ar.arb`;
what this harness proves is that the layout survives Arabic content.
