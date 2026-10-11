# Cloudflare Pages Functions

Only one route lives here.

| File | Route | Purpose |
|---|---|---|
| `share/match/[id].js` | `GET /share/match/:id` | The link a match invitation shares. Answers a chat app's crawler with a server-rendered Open Graph preview and moves a person on to `/#/match/:id`. |

`wrangler pages deploy app/build/web` (both deploy workflows) runs from the
repository root, so this directory is picked up with no workflow change. The
generated `_routes.json` includes only `/share/match/*`; every other request is
served as a static asset and never reaches a Function.

## Runtime bindings (set in each Pages project, not in this repository)

| Name | Value |
|---|---|
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_ANON_KEY` | the publishable/anon key (the one the web build already embeds) |

Set them on **both** `go-play` and `go-play-staging`, for the environment that
serves the link. Until they exist the Function still answers, with the generic
Go Play preview, and makes no request. Never bind a service-role key: the
Function calls one RPC, `public_match_detail`, as `anon`.

## Thumbnail

`app/web/og/go-play-match-invite.jpg` (1200×630) is copied into the web build and
served at `/og/go-play-match-invite.jpg`; the Function names it by absolute
https URL. It is the share-card look: pitch gradient, accent ball, wordmark.

## Tests and local run

```
node --test tests/cloudflare/share_match.test.mjs     # no dependencies
flutter test test/match_invitation_preview_function_test.dart   # also runs the above
```

To run the Function in Pages' local runtime, from the repository root:

```
npx wrangler pages dev app/build/web \
  --binding SUPABASE_URL=https://<project>.supabase.co \
  --binding SUPABASE_ANON_KEY=<publishable key>
```

(`SUPABASE_URL` may be `http://127.0.0.1:<port>` for a stand-in server; no other
plain-http address is accepted.)

## Behaviour worth knowing

- The page is keyed by the link, so the preview language is the sharer's
  (`?lang=ar|en`); without it the Function uses `Accept-Language`, then Arabic,
  the app's own default.
- Times are shown as Oman reads them (`Asia/Muscat`).
- Chat apps keep the first preview they fetch for a link (WhatsApp for days), so
  a match edited after it was shared keeps its old preview there.
