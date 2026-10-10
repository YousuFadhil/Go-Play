# `delete-account`

The one request both deletion entry points make: a System Admin deleting a user
(`{ "p_user_id": "<uuid>" }`) and a signed-in user deleting their own account (`{}`). It exists
because a profile picture lives in Storage, which no SQL can delete (`storage.protect_delete`),
in a public bucket. Everything else is the `admin_delete_account` / `delete_my_account` RPC
(migration `0102`), which removes the personal data, the profile's identity and the Auth user in
one transaction and keeps the football record under the anonymous "Deleted Player" stand-in.

## What it does, in this order

1. Calls the preview **as the caller**, with their own token: `admin_preview_account_deletion` on
   the admin route (the database checks System Admin, twice), `preview_my_account_deletion` on the
   self route (the database answers about `auth.uid()`). A caller who may not never gets further.
2. Preflight: the preview has no blocker (owning a community, being a System Admin, a suspended
   account, which cannot delete itself). Nothing has been touched yet.
3. Removes the target's picture(s) through the Storage API with the service role: exactly the
   objects `merge_source_stored_files` lists, each of which must start with `<uuid>/`, then reads
   the list again to prove it is empty. On the self route the uuid is the one the **database**
   returned for the caller, never one from the request.
4. Calls the deletion RPC, again as the caller. All or nothing.

The service role is used for step 3 and nowhere else.

## What a failure leaves

| Failed at | Left behind | Answer (`error`) |
|---|---|---|
| 1 or 2 | nothing touched | `NOT_AUTHENTICATED`, `NOT_AUTHORIZED`, `USER_NOT_FOUND`, `CANNOT_DELETE_SELF`, `DELETE_BLOCKED` (`detail`: the blockers, e.g. `OWNS_COMMUNITIES`, `TARGET_IS_SYSTEM_ADMIN`, `ACCOUNT_SUSPENDED`), `PREFLIGHT_FAILED` |
| 3 | nothing deleted; the picture may be gone | `AVATAR_CLEANUP_FAILED` (`avatar_removed`: whether any was) |
| 4, refused | account, Auth user and football record unchanged; **the picture is already removed** | the database's own token (a state that changed since the preview, e.g. `DELETE_BLOCKED`, `ACCOUNT_SUSPENDED`), with `avatar_removed: true` |
| 4, answer lost | unknown: the deletion may have committed | `DELETE_OUTCOME_UNKNOWN` |

An account without a picture has nothing to lose in any row.

## Deploy

Apply migration `0102` first (the function calls what it adds), then:

```bash
supabase functions deploy delete-account
```

No secrets to set: `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the platform. The platform's JWT check can stay on; the function does not rely on it,
because the caller's token is forwarded and the database decides.

## Tests

No dependencies, no project:

```bash
node --test supabase/functions/delete-account/index.test.ts
```

They run the handler against a fake backend and check who is allowed to reach what, in which
order, and what each failure leaves. The Storage request shape (`DELETE /storage/v1/object/avatars`
with `{"prefixes": [...]}`) follows the Storage client; it has not been exercised against a live
project, so the first controlled deletion should use a test account with a picture.
