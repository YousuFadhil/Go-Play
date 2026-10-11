# `admin-user-auth`

The one request the System Admin console makes to change another account's sign-in. It exists
because changing an email or a password is an Auth Admin API call, which needs the service role,
and the service role never reaches the app. Migration `0103` is the database's half: **whether** the
act may be attempted, and **that** it happened.

Three operations, one request each:

| `action` | What it does | Body fields |
|---|---|---|
| `change_email` | Sets the account's email at once (no confirmation by the player), then sends the standard recovery email to the **new** address | `user_id`, `reason`, `new_email`, `redirect_to` |
| `send_recovery` | Sends the standard recovery email to the **current** address. Changes nothing | `user_id`, `reason`, `redirect_to` |
| `set_password` | Sets the password directly | `user_id`, `reason`, `password` |

A field that does not belong to the action is refused (`BAD_REQUEST`), so a password cannot travel
with a recovery request. The actor is **never** a field: it is the caller's own token.

## What it does, in this order

1. Validates the request. No network yet.
2. Asks `admin_check_user_auth_action` **as the caller**, with their own token. The database checks
   System Admin (the helper and the table), that the target is not the caller, not a System Admin,
   a live account, and for an email change: no Google identity, a valid, different, unused address.
3. Asks it **again**, immediately before the mutation. The second answer is the one used, including
   the address the database normalised.
4. The one Auth Admin API call (`PUT /auth/v1/admin/users/{id}` with `{email, email_confirm: true}`
   or `{password}`), or the standard recovery email (`POST /auth/v1/recover`, the public endpoint, the
   same request the app's "forgot password" makes, without a PKCE challenge so the link redeems in
   any browser).
5. The audit event, **as the caller**, retried once (`admin_record_user_*`).
6. For an email change: the recovery email to the new address, and its own audit event.

The service role is used for the one Admin API call and nowhere else. Nothing else of the Auth Admin
API is reachable: the URL carries a validated uuid and the body is one of two fixed shapes.

## It is three services, not one transaction

Auth, the email provider and the audit trail can each succeed or fail alone, and the function says
which:

| Failed at | Left behind | Answer |
|---|---|---|
| 1 to 3 | nothing touched | the database's token (`NOT_AUTHORIZED`, `CANNOT_MODIFY_SELF`, `CANNOT_MODIFY_SYSTEM_ADMIN`, `USER_NOT_FOUND`, `GOOGLE_LINKED`, `EMAIL_TAKEN`, `EMAIL_UNCHANGED`, `INVALID_EMAIL`, `NO_EMAIL`), `INVALID_REASON`, `INVALID_PASSWORD`, `BAD_REQUEST`, `PREFLIGHT_FAILED` |
| 4, refused | nothing changed | `INVALID_PASSWORD`, `EMAIL_TAKEN`, `RATE_LIMITED` (`retry_after`), `AUTH_UPDATE_REFUSED` |
| 4, answer lost (5xx, timeout) | **unknown**: it may have been applied | `AUTH_OUTCOME_UNKNOWN` (no event is written, no mail sent) |
| 4, `send_recovery` refused | nothing | `RATE_LIMITED`, `RECOVERY_SEND_FAILED` |
| 5 | the change **happened**; its event was not written | **200** with `audit_recorded: false`, never an error |
| 6 | the email **is changed**; the mail was not requested | **200** with `recovery_sent: false` and `recovery_error`. `send_recovery` is the retry and is safe to repeat |

A second `change_email` for the same address is refused by the database (`EMAIL_UNCHANGED`) before
Auth is called, so a retry after a lost answer cannot change anything twice.

## Sessions

* **`set_password`**: the Auth service ends every refresh session of the account when a password is
  set through the Admin API (it calls its own `Logout` for it). This is read from the open-source Auth
  service, not shown against this project: confirm it on the first controlled use.
* **`change_email`**: the Admin API has **no per-user session revocation** and this function invents
  none. The account's existing sessions stay valid. When the person finishes the recovery email that
  follows, the Auth service ends the account's other sessions.
* Either way, an **access token already issued stays valid until it expires**.

## Confidential data

The password is read from the request body, sent once to the Auth Admin API and dropped. It is not
logged, not in a URL, not in an audit row, not in a response. Addresses are not logged or returned
either. The only things written to the log are fixed words, the action and a refusal token.

## Audit

`USER_EMAIL_CHANGED`, `USER_RECOVERY_SENT`, `USER_PASSWORD_SET`, each by its own function. No event
carries an address, a password or a token; the only snapshot is the target's **name** as the label,
which migration `0102` clears when the account is deleted. The reason is kept as written.

## Deploy

Apply migration `0103` first (the function calls what it adds), then:

```bash
supabase functions deploy admin-user-auth
```

No secrets to set: `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform. The platform's JWT check can stay on; the function does not rely on it, because the
caller's token is forwarded and the database decides.

The recovery link must be allowed by the project's Auth Redirect URLs: the same `/login-callback/recovery`
forms the app's own "forgot password" already uses. Nothing in Auth settings is changed by this.

The function accepts `redirect_to` only from an explicit allowlist, compared exactly: the production and
staging web hosts (`https://go-play-44y.pages.dev`, `https://go-play-staging.pages.dev`),
`goplay://login-callback/recovery`, and `http://localhost` or `http://127.0.0.1` with an optional port,
each followed by `/login-callback/recovery` and nothing more (no query, fragment, username or other
port). Anything else is `BAD_REQUEST` before any call is made. **A new web host needs a change to
`index.ts`**, on purpose.

## Tests

No dependencies, no project:

```bash
node --test supabase/functions/admin-user-auth/index.test.ts
```

They run the handler against a fake backend and check who is allowed to reach what, in which order,
what each Auth call may carry, what each failure leaves, and that the password and the addresses are in
no log and no response. The Auth Admin and recovery endpoints follow the Auth service's source; they
have not been exercised against a live project, so the first controlled use should be a designated
test account, with an inbox that can be read.
