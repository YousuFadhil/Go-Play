# Product Requirements Document (PRD)

> Official product reference for the MVP, updated for the Community-first
> architecture (`v0.4.0-mvp`).

## Goal

An MVP for running amateur football communities and their matches.

## Target users

- Players
- Community owners and admins

## MVP scope

- Register and log in (email + password)
- Create and join communities
- Invite players to the community with a link or join code, and manage members and their roles
- Create matches
- Match registration with a reserve list and automatic promotion
- In-app notifications
- Balanced team generation (BTGE)
- Record match results: score, goal scorers and the MVP
- A system-managed player rating, applied and reversed with each result
- **Statistics and leaderboards**, at two levels:
  - **Global** — the player's career, shown on the Player Profile
  - **Community** — per-community statistics, the Community Dashboard, and
    nine leaderboards over three periods (overall, weekly, monthly)

Statistics and leaderboards are specified in
`engineering/Statistics_Leaderboards_MVP_Specification.md` (v2.0), which is the
authoritative source for that feature. Decisions `SL-1` … `SL-5` are recorded
in `10-Design-Decisions.md`.

## Roles

Exactly three, held per community and cumulative — owner covers admin, admin
covers player.

| | Player | Admin | Owner |
|---|---|---|---|
| View the community, join and withdraw from matches | yes | yes | yes |
| Leave the community | yes | yes | only after transferring ownership |
| Create, edit and delete matches; manage a roster | no | yes | yes |
| Share the community invitation | no | yes | yes |
| Remove a member | no | players only | admins and players |
| Change roles, edit settings, transfer ownership, delete the community | no | no | yes |

## Out of scope

- Push notifications (in-app notifications are in scope and built)
- Charts and any graphical presentation of statistics
- Analytics — trends, form curves, projections
- AI recommendations, player comparison, and **Most Improved** boards
- Global rankings across communities (a career record is not a leaderboard)
- Displaying a Community Rating on the Player Profile

The team generator, the rating engine and match results were previously listed
here. All three are now in scope and built — see `Docs/README.md` for the
current state and `engineering/Results_Rating_Engineering_Decisions.md` for the
results and rating phase.

The statistics and leaderboards exclusions above are the approved list in §12
of the Statistics & Leaderboards MVP Specification v2.0. Deferred ideas are
recorded in `11-Future-Backlog.md`.

## Success criteria

- 10 real users
- 3 active communities
- 10 real matches
- Users keep using the app for at least two weeks
