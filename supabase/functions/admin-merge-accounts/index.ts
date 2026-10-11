// Merge two accounts for good: the one request the System Admin console makes.
//
// **Why this is an Edge Function and not just the `admin_merge_accounts` RPC.** The merge
// removes the source account from the database and from Auth in ONE transaction, but a
// profile picture lives in Storage, whose `protect_delete` trigger refuses any delete
// from SQL, in a PUBLIC bucket. Only the Storage API (service role) can remove it. So the
// order is fixed, and this function is what enforces it:
//
//   1. prove the caller may merge: the preview RPC is called AS THE CALLER, with their own
//      token, and it checks `is_system_admin()` and `system_admins` for itself. A caller
//      who is not a System Admin never reaches anything below;
//   2. preflight: the preview must have no blocker, and the caller's choices for the
//      matches both accounts took part in must cover them exactly, each side allowed;
//   3. remove the source's picture(s) through the Storage API, using the service role,
//      and ONLY the objects `merge_source_stored_files` lists for the source, each of which
//      must sit under `<source uuid>/`; read the list again to prove it is empty;
//   4. call `admin_merge_accounts`, again as the caller. That is the atomic part: the
//      football record, the audit snapshots, the profile and the Auth user, or nothing.
//
// **What a failure at each step leaves.** Steps 1-2: nothing was touched. Step 3: nothing
// but possibly (part of) the picture. Step 4: the database and Auth are untouched (the
// transaction rolled back) but the picture is already gone, which the response says
// (`avatar_removed`). The one outcome nobody can know is a lost answer from step 4 (the
// merge may have committed): `MERGE_OUTCOME_UNKNOWN`.
//
// The service role is used for the Storage calls and the stored-files list, and for
// nothing else: it never reaches the preview or the merge, which run under the caller.
//
// Environment, all injected by the platform:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

export interface Env {
  url: string;
  anonKey: string;
  serviceKey: string;
}

type Json = Record<string, unknown>;

interface Resolution {
  match_id: string;
  keep: "retained" | "source";
}

interface Input {
  retained: string;
  source: string;
  resolutions: Resolution[];
}

interface RpcResult {
  ok: boolean;
  status: number;
  body: unknown;
}

const BUCKET = "avatars";
const MAX_RESOLUTIONS = 100;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^[A-Z][A-Z0-9_]+$/;

// The console is also served from the web, so the browser asks first. Authorization is by
// bearer token, never by cookie, so any origin may ask.
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
  CANNOT_MERGE_SELF: 403,
  USER_NOT_FOUND: 404,
  BAD_REQUEST: 400,
  SAME_ACCOUNT: 400,
  RESOLUTIONS_INVALID: 400,
  MERGE_BLOCKED: 409,
  RESOLUTION_REQUIRED: 409,
  RESOLUTION_BLOCKED: 409,
  RESOLUTION_UNKNOWN_MATCH: 409,
  SOURCE_FILES_REMAIN: 409,
  PREFLIGHT_FAILED: 502,
  AVATAR_CLEANUP_FAILED: 502,
  MERGE_OUTCOME_UNKNOWN: 502,
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

/// The request, or the token that refuses it.
function parse(raw: unknown): Input | string {
  if (!isObject(raw)) return "BAD_REQUEST";
  const retained = raw["p_retained_user_id"];
  const source = raw["p_source_user_id"];
  if (typeof retained !== "string" || typeof source !== "string") {
    return "BAD_REQUEST";
  }
  if (!UUID.test(retained) || !UUID.test(source)) return "BAD_REQUEST";
  if (retained.toLowerCase() === source.toLowerCase()) return "SAME_ACCOUNT";

  const given = raw["p_resolutions"] ?? [];
  if (!Array.isArray(given) || given.length > MAX_RESOLUTIONS) {
    return "RESOLUTIONS_INVALID";
  }
  const seen = new Set<string>();
  const resolutions: Resolution[] = [];
  for (const entry of given) {
    if (!isObject(entry)) return "RESOLUTIONS_INVALID";
    const id = entry["match_id"];
    const keep = entry["keep"];
    if (typeof id !== "string" || !UUID.test(id)) return "RESOLUTIONS_INVALID";
    if (keep !== "retained" && keep !== "source") return "RESOLUTIONS_INVALID";
    const key = id.toLowerCase();
    if (seen.has(key)) return "RESOLUTIONS_INVALID";
    seen.add(key);
    resolutions.push({ match_id: key, keep });
  }
  return {
    retained: retained.toLowerCase(),
    source: source.toLowerCase(),
    resolutions,
  };
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

/// Removes the source's stored pictures and proves they are gone.
///
/// `removed` is how many are known to be gone, whether or not the whole job succeeded, so
/// a failure can say whether the picture was lost.
async function removeStoredFiles(
  fetchFn: typeof fetch,
  env: Env,
  source: string,
): Promise<{ ok: boolean; removed: number }> {
  const list = async (): Promise<string[]> => {
    const result = await rpc(
      fetchFn,
      env,
      "merge_source_stored_files",
      { p_user_id: source },
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

  // Whatever the database answered, only the source's own folder is ever deleted.
  const folder = `${source}/`;
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
  const input = parse(raw);
  if (typeof input === "string") return refuse(input);

  const asCaller = (name: string, args: Json) =>
    rpc(fetchFn, env, name, args, jwt, env.anonKey);
  const pair = {
    p_retained_user_id: input.retained,
    p_source_user_id: input.source,
  };

  // ---- 1 and 2. who may merge, and whether anything stands in the way ---------------
  let preview: RpcResult;
  try {
    preview = await asCaller("admin_preview_account_merge", pair);
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
    return refuse("MERGE_BLOCKED", { detail: blockers.join(",") });
  }

  const shared = doc["shared_matches"];
  const items = isObject(shared) ? shared["items"] : null;
  const total = isObject(shared) ? shared["total"] : null;
  if (!Array.isArray(items) || total !== items.length) {
    return refuse("PREFLIGHT_FAILED");
  }
  const matches = new Map<string, Json>();
  for (const item of items) {
    if (!isObject(item) || typeof item["match_id"] !== "string") {
      return refuse("PREFLIGHT_FAILED");
    }
    matches.set(item["match_id"].toLowerCase(), item);
  }
  const chosen = new Map<string, "retained" | "source">(
    input.resolutions.map((r): [string, "retained" | "source"] => [r.match_id, r.keep]),
  );
  const missing = [...matches.keys()].filter((id) => !chosen.has(id));
  if (missing.length > 0) {
    return refuse("RESOLUTION_REQUIRED", { detail: missing.slice(0, 25).join(",") });
  }
  const unknown = [...chosen.keys()].filter((id) => !matches.has(id));
  if (unknown.length > 0) {
    return refuse("RESOLUTION_UNKNOWN_MATCH", { detail: unknown.slice(0, 25).join(",") });
  }
  for (const [id, keep] of chosen) {
    const allowed = matches.get(id)![keep === "retained" ? "can_keep_retained" : "can_keep_source"];
    if (allowed !== true) return refuse("RESOLUTION_BLOCKED", { detail: id });
  }

  // ---- 3. the picture, through the Storage API, only now ----------------------------
  const cleanup = await removeStoredFiles(fetchFn, env, input.source);
  if (!cleanup.ok) {
    console.error("avatar cleanup failed");
    return refuse("AVATAR_CLEANUP_FAILED", { avatar_removed: cleanup.removed > 0 });
  }
  const avatarRemoved = cleanup.removed > 0;

  // ---- 4. the merge: one transaction, as the caller ---------------------------------
  let merge: RpcResult;
  try {
    merge = await asCaller("admin_merge_accounts", {
      ...pair,
      p_resolutions: input.resolutions,
    });
  } catch {
    // The request may have reached the database and committed.
    console.error("merge outcome unknown");
    return refuse("MERGE_OUTCOME_UNKNOWN", { avatar_removed: avatarRemoved });
  }
  if (!merge.ok) {
    const { token, detail } = tokenOf(merge);
    // A gateway error with no business token could hide a commit; a 4xx without one did not.
    const outcome = token ?? (merge.status >= 500 ? "MERGE_OUTCOME_UNKNOWN" : "REQUEST_FAILED");
    console.error(`merge refused: ${outcome}`);
    return refuse(outcome, {
      ...(detail ? { detail } : {}),
      avatar_removed: avatarRemoved,
    });
  }
  return reply(200, {
    ...(isObject(merge.body) ? merge.body : {}),
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
