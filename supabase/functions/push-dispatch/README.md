# `push-dispatch`

Delivers a notification as a Firebase push. Invoked by the `after insert`
trigger on `public.notifications` (migration `0036`), never by the client.

The notice is written and visible in the Notification Center whether or not this
function runs. Everything here is delivery.

## Secrets

```bash
supabase secrets set PUSH_DISPATCH_SECRET="<a long random string>"
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform.

`FCM_SERVICE_ACCOUNT` is the JSON downloaded from **Firebase Console → Project
settings → Service accounts → Generate new private key**. It must contain
`project_id`, `client_email` and `private_key`.

## Deploy

The trigger calls this with a shared secret rather than a user JWT, so the
platform's own JWT check has to be off:

```bash
supabase functions deploy push-dispatch --no-verify-jwt
```

## Point the database at it

Until this row is filled in the trigger returns immediately and nothing is ever
pushed. That is the intended state before Firebase is set up.

```sql
update public.push_config
set function_url    = 'https://<project-ref>.supabase.co/functions/v1/push-dispatch',
    dispatch_secret = '<the same string as PUSH_DISPATCH_SECRET>'
where id = true;
```

`pg_net` must be enabled on the project (**Database → Extensions → pg_net**).
The migration attempts to enable it and carries on if it cannot.

## Outcome evidence

Each invocation that gets past the secret and body checks records **one**
terminal outcome through `record_push_dispatch_outcome_v1` (migration `0090`,
service role only) into `public.push_dispatch_outcomes`:

| Outcome          | Meaning                                              |
|------------------|------------------------------------------------------|
| `not_found`      | the notice no longer exists                          |
| `suppressed`     | the policy says not to push this notice              |
| `no_devices`     | the recipient has no registered device               |
| `unrenderable`   | the registry has no title/body for the type          |
| `dispatched`     | sent to every device: `sent` + `stale` + `failed`    |
| `internal_error` | the invocation failed and answered HTTP 500          |

Only the notification id, the registry priority (`high`/`medium`/`low`, or
null when unknown) and device counts are stored — never a push token, the
notice text, the recipient or a Firebase response. There is no foreign key to
`notifications`; the Notification Center stays the source of truth.

Recording is best-effort: it is bounded by a short timeout, logged by status
only when it fails, never retried, and never changes the push, the stale-token
cleanup or the response. Requests refused by the secret or body checks are not
recorded — they carry no notification id worth trusting.

OI-05 **FCM Acceptance Rate** = `sent / (sent + stale + failed)` over
`dispatched` rows. `sent` means Firebase accepted the message, not that a
device displayed it.

## Turning push off

```sql
update public.push_config set function_url = null where id = true;
```

Notices keep being written. Nothing else changes.
