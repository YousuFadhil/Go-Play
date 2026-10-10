# `admin-merge-accounts`

The one request the System Admin console makes to merge two accounts for good. It exists
because a profile picture lives in Storage, which no SQL can delete (`storage.protect_delete`),
in a public bucket. Everything else is the `admin_merge_accounts` RPC (migration `0101`), which
removes the source from `public.users` and `auth.users` in one transaction.

## What it does, in this order

1. Calls `admin_preview_account_merge` **as the caller**, with their own token. The database
   checks that they are a System Admin (twice), so a caller who is not never gets further.
2. Preflight: the preview has no blocker, and the caller's choice for every match both
   accounts took part in is present and allowed. Nothing has been touched yet.
3. Removes the source's picture(s) through the Storage API with the service role: exactly the
   objects `merge_source_stored_files` lists, each of which must start with `<source uuid>/`,
   then reads the list again to prove it is empty.
4. Calls `admin_merge_accounts`, again as the caller. All or nothing.

The service role is used for step 3 and nowhere else.

## What a failure leaves

| Failed at | Left behind | Answer (`error`) |
|---|---|---|
| 1 or 2 | nothing touched | `NOT_AUTHENTICATED`, `NOT_AUTHORIZED`, `MERGE_BLOCKED`, `RESOLUTION_*`, `PREFLIGHT_FAILED` |
| 3 | nothing merged; the picture may be gone | `AVATAR_CLEANUP_FAILED` (`avatar_removed`: whether any was) |
| 4, refused | both accounts and all football record unchanged; **the picture is already removed** | the database's own token, with `avatar_removed: true` |
| 4, answer lost | unknown: the merge may have committed | `MERGE_OUTCOME_UNKNOWN` |

A source without a picture has nothing to lose in any row.

## Deploy

Apply migration `0101` first (the function calls what it adds), then:

```bash
supabase functions deploy admin-merge-accounts
```

No secrets to set: `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the platform. The platform's JWT check can stay on; the function does not rely on it,
because the caller's token is forwarded and the database decides.

## Tests

No dependencies, no project:

```bash
node --test supabase/functions/admin-merge-accounts/index.test.ts
```

They run the handler against a fake backend and check who is allowed to reach what, in which
order, and what each failure leaves. The Storage request shape (`DELETE /storage/v1/object/avatars`
with `{"prefixes": [...]}`) follows the Storage client; it has not been exercised against a live
project, so the first controlled merge should use a test account with a picture.
