# Screens

The twelve approved Go Play screens. See `../HANDOFF.md` §C for the full
inventory (sections, components used, primary CTA, role-specific controls,
required states) and §D for the navigation map.

These are React reference implementations, not production code. They exist to
pin down layout, spacing, hierarchy and state behaviour precisely enough to
reproduce in Flutter. Read them alongside the running build in
`../ui_kits/mobile-app/index.html`.

## Files

| File | Contains |
|---|---|
| `App.jsx` | The router, the review harness, and three single-section screens: Discover, Communities, Notifications |
| `Shell.jsx` | `TaskBar`, `TaskBody`, `ActionBar`, `RowGroup`, `FieldRow`, `OwnerLine`, `HeroFacts`, `MatchListSkeleton`, `screenState` — the task-screen shell and the pinned commit action |
| `Home.jsx` | Home |
| `CommunityDetails.jsx` | Community Details, incl. the underlined content tabs and the role-gated action sheet |
| `MatchDetails.jsx` | Match Details, incl. the three registration states and the organizer action pair |
| `CreateMatch.jsx` | Create Match, incl. validation |
| `Members.jsx` | Member Management, incl. the permission-restricted read-only state |
| `Invite.jsx` | Invitation — both `share` and `landing` modes |
| `Teams.jsx` | Teams and Arrange Participants (one screen, segmented switch) |
| `Result.jsx` | Result Entry, incl. the goals-must-equal-score rule |
| `Profile.jsx` | Profile |
| `data.js` | Fixtures. `GP_DATA` is English; `GP_DATA_AR` is the deliberately long Arabic set used for the RTL audit; `T(review)` selects between them |

## Reading them

Every screen takes `{ go, review, setToast }`. `review` is the harness state —
it is a review affordance, not product state, and has no Flutter counterpart.
Drop it and read the branches it selects as the states the screen must support.
