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

- Team generator
- Rating engine
- Statistics and leaderboards
- Match results
- Push notifications (in-app notifications are in scope and built)

Deferred ideas are recorded in `11-Future-Backlog.md`.

## Success criteria

- 10 real users
- 3 active communities
- 10 real matches
- Users keep using the app for at least two weeks
