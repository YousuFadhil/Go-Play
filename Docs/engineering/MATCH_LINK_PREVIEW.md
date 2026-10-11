# Match invitation link preview — Option A

Match invitations from creation and match details send readable invitation text
and exactly one URL:
`https://<PUBLIC_WEB_BASE>/share/match/<uuid>?lang=ar|en&v=2`.
The page returns server-rendered Open Graph metadata: the publicly readable
match title, its date/time in Asia/Muscat and location, plus one reusable
localized Go Play thumbnail. No PNG file is attached to the share sheet.
JavaScript opens the existing `/#/match/<uuid>` route; an ordinary HTML link
provides the same destination without JavaScript. Existing authentication and
registration continue through that route. Existing hash links still work.
Lineup, results and statistics card sharing are unchanged.

## Deployment prerequisite

The existing Wrangler workflows run from the repository root and deploy
`app/build/web`; Wrangler discovers the root `functions/` directory. Flutter
copies `app/web/_routes.json` and `app/web/share/go-play-thumbnail.png` into that
build. Only `/share/match/*` invokes a Function. No new deployment project,
workflow, database migration, dependency or service-role key is needed.

The Function requires these **runtime** variables in Cloudflare Pages, distinct
from the GitHub secrets used for Flutter's build-time Dart defines:

| Runtime variable | Value |
| --- | --- |
| `SUPABASE_URL` | The same HTTPS Supabase project root URL as the relevant app build, without `/rest/v1/`. |
| `SUPABASE_ANON_KEY` | The same public anon key as the app, or its publishable key. Never a service-role or secret key. |

Before an authorized deployment: in Cloudflare **Workers & Pages → the existing
Go Play project → Settings → Variables and Secrets**, add these variables for
the environment that will receive that deployment. A deployment with a branch
matching the project's configured production branch uses its Production
variables; Preview deployments use Preview variables. The separate staging
project, if used, needs its own values. GitHub Environment secrets do not become
Pages Function runtime bindings automatically. Redeploy after changing bindings.
No live bindings or deployment were changed during implementation.

Reference: [Cloudflare Pages Functions deployment](https://developers.cloudflare.com/pages/functions/get-started/) and [runtime bindings](https://developers.cloudflare.com/pages/functions/bindings/).

Missing/invalid configuration returns generic metadata with HTTP 503, rather
than silently claiming a successful dynamic preview. Check this before release.

## Public-data boundary

Only the existing `public_match_detail(p_match_id)` RPC is called, with the public
key and no visitor credentials. UUID validation precedes the call. The response
publishes only title, location and date/time; no roster, organizer, join code,
MVP or profile fields. Privileged keys are rejected. HTML is escaped, reads have
a five-second timeout, and responses use `Cache-Control: no-store` to avoid an
application/CDN cache retaining data after public visibility changes.
Unavailable matches get generic metadata and HTTP 404; malformed identifiers
get HTTP 400. The app handles availability again when a reader opens the link.
WhatsApp may keep its own cached preview; the application cannot control that.

## Validation and acceptance

- Server tests: `node --test tests/pages/match-preview.test.mjs` (Node 22+).
- Function bundling, without publishing: `wrangler pages functions build functions --outdir /tmp/goplay-pages-functions`.
- Flutter: format changed Dart files, `flutter analyze`, and the invitation,
  public-link, create-match, match-details and analytics tests.
- After configuring runtime variables and authorizing a deployment, fetch a
  real publicly visible match URL without running JavaScript: it must return
  HTTP 200, match-specific metadata, an absolute HTTPS image URL and a fallback
  link to that same match. The image must return HTTP 200 and `image/png`.
- On a phone, share from each invitation entry point to WhatsApp. Verify that
  one clickable link has its thumbnail, and tapping it opens the correct match
  with the existing registration/login behavior. Test Arabic and English.

Automated tests verify the payload and HTML, not WhatsApp's final rendering.
The Product Owner must authorize any merge or production deployment separately.

## Original Option A implementation verification — 2026-10-11

Baseline: `develop` at `d1601bf75bcc3ea4f2957b4af08050986ddb5e3f`.

- Flutter 3.44.7: 117/117 tests passed across invitation sharing, public links,
  match creation, match details, analytics instrumentation and image payloads.
- `flutter analyze --no-pub`: exactly the same 12 findings as a separate
  checkout of the baseline; no new errors, warnings or lint findings. The
  baseline's findings keep the analyzer's exit code at 1.
- Changed Dart files: formatter check passed; `git diff --check` passed.
- Pages response tests: 12/12 passed.
- Wrangler 4.71.0: Function bundle compiled successfully.
- Release web build passed with dummy public build configuration; not deployed.
  The emitted thumbnail and `_routes.json` match the source files byte-for-byte.
  The build emitted a CupertinoIcons font warning; this change adds no font or
  Cupertino icon and does not alter the existing dependency graph.
- Live Supabase read-only precheck: the RPC signature matches the repository,
  and `anon` has EXECUTE permission. No user rows or database settings changed.

Local `wrangler pages dev` could not start because this container disallows
network-interface enumeration (`uv_interface_addresses`). Handler tests and
bundling passed; an actual hosted request and WhatsApp delivery remain to be
checked after runtime configuration and an authorized deployment.

## Invitation clarity — UX v2

Following real-device acceptance of the URL preview, the Product Owner requested
a clearer invitation and approved its visual concept. The message now gives a
localized invitation heading, date, twelve-hour time range, location (when set),
and explicit instruction to open the link for details and registration. It uses
the existing date/time formatters so the invitation agrees with the app screens.
Both entry points retain one share operation, one URL and no file attachment.

Upcoming match metadata also invites readers to join. Completed matches retain
neutral metadata and the legacy neutral image. Missing matches/configuration do
not acquire a registration claim. Existing hash links and app routes remain
unchanged; no database, dependency, auth or registration behavior changes.

The two reusable images are `go-play-invite-v2-ar.png` (1730×909) and
`go-play-invite-v2-en.png` (1731×909). They contain brand identity and a join
instruction, with no per-match information. The old thumbnail is preserved for
neutral responses and existing references. Generated images were visually
checked for readable Arabic/English text. Metadata declares each actual size.
The `v=2` query and new image filenames distinguish this presentation from older
cached previews; WhatsApp still controls its own rendering and caching.

Validation of this revision: 14/14 Pages handler tests passed, including
localized assets/dimensions, versioned canonical links and completed-match
behavior; `git diff --check` passed. Flutter sharing/link tests were updated but
could not be executed because no Flutter SDK is available in this session.
Before marking ready: regenerate localizations, format changed Dart files, run
the four affected Flutter test files and analyzer against the current baseline.
This revision is for review, with no production publication authorized yet.
