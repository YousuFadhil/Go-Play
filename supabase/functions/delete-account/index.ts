// Permanent account deletion: the one request both entry points make.
//
//   { "p_user_id": "<uuid>" }   a System Admin deletes that user
//   { }                         a signed-in user deletes their own account
//
// **Why this is an Edge Function and not just the RPCs.** The deletion itself is one database
// transaction (`admin_delete_account` / `delete_my_account`, migration 0102), but a profile picture
// lives in Storage, whose `protect_delete` trigger refuses any delete from SQL, in a PUBLIC bucket.
// Only the Storage API (service role) can remove it. This is the same pattern as
// `admin-merge-accounts`, and the order is fixed here:
//
//   1. preflight AS THE CALLER, with their own token: the admin route calls
//      `admin_preview_account_deletion` (the database checks System Admin, twice), the self route
//      calls `preview_my_account_deletion` (the database answers about `auth.uid()`). Anything that
//      blocks -- owning a community, being a System Admin, a suspended account -- stops here, with
//      nothing touched;
//   2. remove the target's picture(s) through the Storage API with the service role: only the
//      objects `merge_source_stored_files` lists, each of which must sit under `<uuid>/`; read the
//      list again to prove it is empty;
//   3. call the deletion RPC, again AS THE CALLER. That is the atomic part: personal data, the Auth
//      user, the football record kept under the deleted player, or nothing.
//
// **What a failure at each step leaves.** 1: nothing touched. 2: nothing but possibly (part of)
// the picture. 3: the database and Auth are untouched (the transaction rolled back) but the picture
// is already gone, which the answer says (`avatar_removed`). A lost answer from step 3 is
// `DELETE_OUTCOME_UNKNOWN`: the deletion may have committed.
//
// The service role is used for the Storage calls and the stored-files list, and for nothing else:
// it never reaches a preview or a deletion, which run under the caller. In self mode the uuid the
// picture is removed for is the one the DATABASE returned for the caller, never one from the request.
//
// Environment, all injected by the platform:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

export interface Env {
  url: string;
  anonKey: string;
  serviceKey: string;
}

type Json = Record<string, unknown>;

interface RpcResult {
  ok: boolean;
  status: number;
  body: unknown;
}

const BUCKET = "avatars";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^[A-Z][A-Z0-9_]+$/;

// The console and the app are also served from the web, so the browser asks first. Authorization is
// by bearer token, never by cookie, so any origin may ask.
const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// The HTTP status each refusal travels under. The token in the body is what the app reads.
const STATUS: Record<string, number> = {
  NOT_AUTHENTICATED: 401,
  NOT_AUTHORIZED: 403,
  CANNOT_DELETE_SELF: 403,
  ACCOUNT_SUSPENDED: 403,
  USER_NOT_FOUND: 404,
  BAD_REQUEST: 400,
  DELETE_BLOCKED: 409,
  SOURCE_FILES_REMAIN: 409,
  PREFLIGHT_FAILED: 502,
  AVATAR_CLEANUP_FAILED: 502,
  DELETE_OUTCOME_UNKNOWN: 502,
};

function reply(status: number, body: Json): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function refuse(token: string, extra: Json = {}): Response {
  return reply(STATUS[token] ?? 500, { error: token, ...extra });
}

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function rpc(
  fetchFn: typeof fetch,
  env: Env,
  name: string,
  args: Json,
  bearer: string,
  apikey: string,
): Promise<RpcResult> {
  const response = await fetchFn(`${env.url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey,
      Authorization: `Bearer ${bearer}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { ok: response.ok, status: response.status, body };
}

/// What a failed RPC said: the business token the database raised, if it raised one.
function tokenOf(result: RpcResult): { token: string | null; detail: string | null } {
  if (result.status === 401) return { token: "NOT_AUTHENTICATED", detail: null };
  const body = result.body;
  if (!isObject(body)) return { token: null, detail: null };
  const message = body["message"];
  const details = body["details"];
  return {
    token: typeof message === "string" && TOKEN.test(message) ? message : null,
    detail: typeof details === "string" ? details : null,
  };
}

/// Removes the target's stored pictures and proves they are gone.
///
/// `removed` is how many are known to be gone, whether or not the whole job succeeded, so a failure
/// can say whether the picture was lost.
async function removeStoredFiles(
  fetchFn: typeof fetch,
  env: Env,
  target: string,
): Promise<{ ok: boolean; removed: number }> {
  const list = async (): Promise<string[]> => {
    const result = await rpc(
      fetchFn,
      env,
      "merge_source_stored_files",
      { p_user_id: target },
      env.serviceKey,
      env.serviceKey,
    );
    const body = result.body;
    if (!result.ok || !Array.isArray(body) || !body.every((n) => typeof n === "string")) {
      throw new Error("stored files could not be listed");
    }
    return body as string[];
  };

  let before: string[];
  try {
    before = await list();
  } catch {
    return { ok: false, removed: 0 };
  }
  if (before.length === 0) return { ok: true, removed: 0 };

  // Whatever the database answered, only the target's own folder is ever deleted.
  const folder = `${target}/`;
  if (!before.every((name) => name.startsWith(folder))) {
    return { ok: false, removed: 0 };
  }

  let deleted = false;
  try {
    const response = await fetchFn(`${env.url}/storage/v1/object/${BUCKET}`, {
      method: "DELETE",
      headers: {
        apikey: env.serviceKey,
        Authorization: `Bearer ${env.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ prefixes: before }),
    });
    await response.text();
    deleted = response.ok;
  } catch {
    deleted = false;
  }

  // The answer of the delete call is not taken on trust: the list is read again.
  let after: string[] | null = null;
  try {
    after = await list();
  } catch {
    after = null;
  }
  return {
    ok: deleted && after !== null && after.length === 0,
    removed: after === null ? 0 : Math.max(0, before.length - after.length),
  };
}

export async function handle(
  request: Request,
  env: Env,
  fetchFn: typeof fetch = fetch,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (request.method !== "POST") {
    return reply(405, { error: "METHOD_NOT_ALLOWED" });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const jwt = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (jwt === "") return refuse("NOT_AUTHENTICATED");

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return refuse("BAD_REQUEST");
  }
  if (!isObject(raw)) return refuse("BAD_REQUEST");

  // A target means the administrator's route; none means the caller's own account.
  const given = raw["p_user_id"];
  let target: string | null = null;
  if (given !== undefined && given !== null) {
    if (typeof given !== "string" || !UUID.test(given)) return refuse("BAD_REQUEST");
    target = given.toLowerCase();
  }
  const admin = target !== null;

  const asCaller = (name: string, args: Json) =>
    rpc(fetchFn, env, name, args, jwt, env.anonKey);

  // ---- 1. who may delete, and whether anything stands in the way -------------------------
  let preview: RpcResult;
  try {
    preview = admin
      ? await asCaller("admin_preview_account_deletion", { p_user_id: target })
      : await asCaller("preview_my_account_deletion", {});
  } catch {
    return refuse("PREFLIGHT_FAILED");
  }
  if (!preview.ok) {
    const { token, detail } = tokenOf(preview);
    return refuse(token ?? "PREFLIGHT_FAILED", detail ? { detail } : {});
  }
  const doc = preview.body;
  if (!isObject(doc)) return refuse("PREFLIGHT_FAILED");

  const findings = Array.isArray(doc["findings"]) ? doc["findings"] : [];
  const blockers = findings
    .filter((f) => isObject(f) && f["severity"] === "BLOCKER")
    .map((f) => String((f as Json)["code"]));
  // Anything but an explicit `false` is treated as blocked.
  if (doc["has_blockers"] !== false || blockers.length > 0) {
    return refuse("DELETE_BLOCKED", { detail: blockers.join(",") });
  }

  // Whose picture: the administrator's target, or -- in self mode -- the uuid the database itself
  // returned for the caller. Never a uuid taken from the request in self mode.
  if (!admin) {
    const own = doc["user_id"];
    if (typeof own !== "string" || !UUID.test(own)) return refuse("PREFLIGHT_FAILED");
    target = own.toLowerCase();
  }

  // ---- 2. the picture, through the Storage API, only now ---------------------------------
  const cleanup = await removeStoredFiles(fetchFn, env, target!);
  if (!cleanup.ok) {
    console.error("avatar cleanup failed");
    return refuse("AVATAR_CLEANUP_FAILED", { avatar_removed: cleanup.removed > 0 });
  }
  const avatarRemoved = cleanup.removed > 0;

  // ---- 3. the deletion: one transaction, as the caller -----------------------------------
  let result: RpcResult;
  try {
    result = admin
      ? await asCaller("admin_delete_account", { p_user_id: target })
      : await asCaller("delete_my_account", {});
  } catch {
    // The request may have reached the database and committed.
    console.error("deletion outcome unknown");
    return refuse("DELETE_OUTCOME_UNKNOWN", { avatar_removed: avatarRemoved });
  }
  if (!result.ok) {
    const { token, detail } = tokenOf(result);
    // A gateway error with no business token could hide a commit; a 4xx without one did not.
    const outcome = token ?? (result.status >= 500 ? "DELETE_OUTCOME_UNKNOWN" : "REQUEST_FAILED");
    console.error(`deletion refused: ${outcome}`);
    return refuse(outcome, {
      ...(detail ? { detail } : {}),
      avatar_removed: avatarRemoved,
    });
  }
  return reply(200, {
    ...(isObject(result.body) ? result.body : {}),
    avatar_files_removed: cleanup.removed,
  });
}

interface DenoRuntime {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): unknown;
}

// Under Deno this serves; imported by a test under Node it does nothing.
const deno = (globalThis as unknown as { Deno?: DenoRuntime }).Deno;
if (deno) {
  deno.serve((request) =>
    handle(request, {
      url: deno.env.get("SUPABASE_URL")!,
      anonKey: deno.env.get("SUPABASE_ANON_KEY")!,
      serviceKey: deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    })
  );
}
