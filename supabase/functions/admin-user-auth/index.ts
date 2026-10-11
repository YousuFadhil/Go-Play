// Admin authentication management: three operations on ANOTHER user's sign-in, one request each.
//
//   { "action": "change_email",  "user_id": "<uuid>", "reason": "...", "new_email": "...", "redirect_to": "..." }
//   { "action": "send_recovery", "user_id": "<uuid>", "reason": "...", "redirect_to": "..." }
//   { "action": "set_password",  "user_id": "<uuid>", "reason": "...", "password": "..." }
//
// **Why an Edge Function.** Changing an email or a password, and sending the recovery mail, are Auth
// Admin API calls: they need the service role, which must never reach the app. Migration 0103 supplies
// what the database is responsible for -- WHETHER the act may be attempted (`admin_check_user_auth_action`)
// and THAT it happened (one action-specific audit writer per event). Both run AS THE CALLER, with the
// caller's own token, so `auth.uid()` is the real administrator and the request cannot name another.
// The service role is used for exactly two Auth calls and nothing else:
//
//   PUT  /auth/v1/admin/users/{id}   with { email, email_confirm: true }  or  { password }
//   (and the standard recovery email, POST /auth/v1/recover, which is a PUBLIC endpoint and uses the
//    anon key -- it is the same request the app's own "forgot password" makes)
//
// Nothing else of the Auth Admin API is reachable: the URL carries only a validated uuid and the body is
// built here from two fixed shapes. No field of the request is forwarded.
//
// **The order, for every action.**
//   1. validate the request (no network);
//   2. ask the database AS THE CALLER whether it may be attempted -- System Admin (twice), not oneself,
//      not a System Admin, a live account, and for an email change: no Google identity, a valid, new,
//      unused address;
//   3. ask AGAIN, immediately before the mutation: the second answer is the one used;
//   4. the Auth call;
//   5. the audit event, AS THE CALLER, retried once;
//   6. for an email change, the standard recovery email to the NEW address, and its own audit event.
//
// **Auth, email delivery and the audit are three services, not one transaction, and this function never
// says otherwise.** What each failure leaves:
//
//   1-3  nothing touched
//   4    the Auth call was refused (`INVALID_PASSWORD`, `EMAIL_TAKEN`, `RATE_LIMITED`, ...): nothing
//        changed. If the answer was lost (`AUTH_OUTCOME_UNKNOWN`) the change MAY have been applied; the
//        administrator reads the account and decides.
//   5    the change HAPPENED but its audit event could not be written: the answer is a success with
//        `audit_recorded: false`, never an error, because an error invites a second attempt at something
//        already done.
//   6    the email WAS changed; the recovery mail was not requested: success with `recovery_sent: false`
//        and the reason in `recovery_error`. `send_recovery` is the retry, and it is safe to repeat.
//
// **Sessions.** Setting a password through the Admin API ends every refresh session of the account (the
// Auth service calls its own `Logout` for it). Changing an email does NOT: the Admin API has no
// per-user session revocation and this function invents none. An access token already issued stays
// valid until it expires in either case.
//
// **Confidential data.** The password is read from the request body, sent once to the Auth Admin API and
// dropped. It is never logged, never put in a URL, an audit row or a response. Addresses are never
// logged or answered either. `console.error` below carries fixed words, the action and status codes.
//
// Environment, all injected by the platform:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

export interface Env {
  url: string;
  anonKey: string;
  serviceKey: string;
}

type Json = Record<string, unknown>;

type Action = "change_email" | "send_recovery" | "set_password";

const SQL_ACTION: Record<Action, string> = {
  change_email: "CHANGE_EMAIL",
  send_recovery: "SEND_RECOVERY",
  set_password: "SET_PASSWORD",
};

interface RpcResult {
  ok: boolean;
  status: number;
  body: unknown;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^[A-Z][A-Z0-9_]+$/;

// The only places a recovery link may send the person: the app's own callback with `/recovery`
// (`AuthService.recoveryRedirect`) on the two hosts it is served from, the native scheme, and a local
// development server. The Auth service enforces its own allow-list on top of this.
//
// **Exact strings, not patterns, for everything that is not a local server.** A pattern that accepts
// "any HTTPS host" lets an administrator's request send a recovery link anywhere; a string comparison
// cannot be argued with. So a subdomain lookalike, an embedded username, a port the host does not use,
// a query or a fragment, another case, a trailing slash or a trailing space all simply are not in the
// list. A new web host is a code change here, deliberately.
const RECOVERY_REDIRECTS: ReadonlySet<string> = new Set([
  "https://go-play-44y.pages.dev/login-callback/recovery",
  "https://go-play-staging.pages.dev/login-callback/recovery",
  "goplay://login-callback/recovery",
]);

// A local development server may use any port, over plain http, on exactly these two names.
const LOCAL_REDIRECT =
  /^http:\/\/(?:localhost|127\.0\.0\.1)(?::([1-9][0-9]{0,4}))?\/login-callback\/recovery$/;

function isAllowedRedirect(value: string): boolean {
  if (RECOVERY_REDIRECTS.has(value)) return true;
  const local = LOCAL_REDIRECT.exec(value);
  if (local === null) return false;
  return local[1] === undefined || Number(local[1]) <= 65535;
}

const REASON_MAX = 500;
// The product's rule (`AuthService.minimumPasswordLength`) and the hash function's own ceiling.
const PASSWORD_MIN = 8;
const PASSWORD_MAX_BYTES = 72;
const EMAIL_MAX = 254;

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
  CANNOT_MODIFY_SELF: 403,
  CANNOT_MODIFY_SYSTEM_ADMIN: 403,
  USER_NOT_FOUND: 404,
  BAD_REQUEST: 400,
  INVALID_REASON: 400,
  INVALID_EMAIL: 400,
  INVALID_PASSWORD: 400,
  INVALID_ACTION: 400,
  GOOGLE_LINKED: 409,
  EMAIL_TAKEN: 409,
  EMAIL_UNCHANGED: 409,
  NO_EMAIL: 409,
  RATE_LIMITED: 429,
  PREFLIGHT_FAILED: 502,
  AUTH_UPDATE_REFUSED: 502,
  AUTH_OUTCOME_UNKNOWN: 502,
  RECOVERY_SEND_FAILED: 502,
};

function reply(status: number, body: Json, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", ...extraHeaders },
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
): Promise<RpcResult> {
  const response = await fetchFn(`${env.url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: env.anonKey,
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
function tokenOf(result: RpcResult): string | null {
  if (result.status === 401) return "NOT_AUTHENTICATED";
  const body = result.body;
  if (!isObject(body)) return null;
  const message = body["message"];
  return typeof message === "string" && TOKEN.test(message) ? message : null;
}

type AuthCall =
  | { kind: "ok" }
  | { kind: "refused"; token: string; retryAfter?: number }
  | { kind: "unknown" };

/// How the Auth service answered, as one of three things. A 4xx is a definite refusal (nothing
/// changed); a 2xx is done; anything else -- a 5xx, a gateway error, a dropped connection -- leaves it
/// unknown, because the change may have been committed before the answer was lost.
async function readAuthAnswer(
  response: Response,
  onRefusal: (status: number, code: string) => string,
): Promise<AuthCall> {
  if (response.ok) {
    await response.text();
    return { kind: "ok" };
  }
  const status = response.status;
  let code = "";
  try {
    const parsed = JSON.parse(await response.text());
    if (isObject(parsed)) {
      const c = parsed["error_code"] ?? parsed["code"];
      if (typeof c === "string") code = c;
    }
  } catch {
    // the body is not needed beyond its code
  }
  if (status === 429) {
    const header = Number(response.headers.get("retry-after"));
    return {
      kind: "refused",
      token: "RATE_LIMITED",
      ...(Number.isFinite(header) && header > 0 ? { retryAfter: Math.ceil(header) } : {}),
    };
  }
  if (status >= 400 && status < 500) {
    return { kind: "refused", token: onRefusal(status, code) };
  }
  return { kind: "unknown" };
}

/// PUT /auth/v1/admin/users/{id}: the one Admin API call this function can make. The body is one of two
/// fixed shapes, chosen by the caller of this function, never forwarded from the request.
async function adminUpdate(
  fetchFn: typeof fetch,
  env: Env,
  id: string,
  payload: { email: string; email_confirm: true } | { password: string },
  onRefusal: (status: number, code: string) => string,
): Promise<AuthCall> {
  try {
    const response = await fetchFn(`${env.url}/auth/v1/admin/users/${id}`, {
      method: "PUT",
      headers: {
        apikey: env.serviceKey,
        Authorization: `Bearer ${env.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    return await readAuthAnswer(response, onRefusal);
  } catch {
    return { kind: "unknown" };
  }
}

/// The standard recovery email, through the same public endpoint the app's "forgot password" uses. No
/// code challenge is sent, so the link is the implicit form that redeems in any browser (see
/// `SupabaseAuthAdapter.requestPasswordReset`): there is no verifier on this side to match.
async function sendRecovery(
  fetchFn: typeof fetch,
  env: Env,
  email: string,
  redirectTo: string,
): Promise<AuthCall> {
  try {
    const response = await fetchFn(
      `${env.url}/auth/v1/recover?redirect_to=${encodeURIComponent(redirectTo)}`,
      {
        method: "POST",
        headers: {
          apikey: env.anonKey,
          Authorization: `Bearer ${env.anonKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email }),
      },
    );
    return await readAuthAnswer(response, () => "RECOVERY_SEND_FAILED");
  } catch {
    return { kind: "unknown" };
  }
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

  // ---- 1. the request, validated before anything is called -----------------------------------
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return refuse("BAD_REQUEST");
  }
  if (!isObject(raw)) return refuse("BAD_REQUEST");

  const action = raw["action"];
  if (action !== "change_email" && action !== "send_recovery" && action !== "set_password") {
    return refuse("BAD_REQUEST");
  }
  const target = raw["user_id"];
  if (typeof target !== "string" || !UUID.test(target)) return refuse("BAD_REQUEST");
  const userId = target.toLowerCase();

  // A field that does not belong to the action is refused, so a secret cannot travel where nothing
  // uses it.
  if (action !== "set_password" && "password" in raw) return refuse("BAD_REQUEST");
  if (action !== "change_email" && "new_email" in raw) return refuse("BAD_REQUEST");

  const rawReason = raw["reason"];
  const reason = typeof rawReason === "string" ? rawReason.trim() : "";
  if (reason === "" || reason.length > REASON_MAX) return refuse("INVALID_REASON");

  let redirectTo = "";
  if (action !== "set_password") {
    const given = raw["redirect_to"];
    if (typeof given !== "string" || !isAllowedRedirect(given)) {
      return refuse("BAD_REQUEST");
    }
    redirectTo = given;
  }

  let newEmail = "";
  if (action === "change_email") {
    const given = raw["new_email"];
    newEmail = typeof given === "string" ? given.trim() : "";
    if (newEmail === "" || newEmail.length > EMAIL_MAX) return refuse("INVALID_EMAIL");
  }

  let password = "";
  if (action === "set_password") {
    const given = raw["password"];
    if (
      typeof given !== "string" ||
      given.length < PASSWORD_MIN ||
      new TextEncoder().encode(given).length > PASSWORD_MAX_BYTES
    ) {
      return refuse("INVALID_PASSWORD");
    }
    password = given;
  }

  const asCaller = (name: string, args: Json) => rpc(fetchFn, env, name, args, jwt);

  // ---- 2 and 3. may it be attempted -- asked twice, the second answer used -------------------
  const checkArgs: Json = {
    p_user_id: userId,
    p_action: SQL_ACTION[action],
    ...(action === "change_email" ? { p_new_email: newEmail } : {}),
  };
  const ask = async (): Promise<{ doc: Json } | { response: Response }> => {
    let result: RpcResult;
    try {
      result = await asCaller("admin_check_user_auth_action", checkArgs);
    } catch {
      return { response: refuse("PREFLIGHT_FAILED") };
    }
    if (!result.ok) return { response: refuse(tokenOf(result) ?? "PREFLIGHT_FAILED") };
    const doc = result.body;
    if (!isObject(doc) || doc["user_id"] !== userId) {
      return { response: refuse("PREFLIGHT_FAILED") };
    }
    return { doc };
  };

  const first = await ask();
  if ("response" in first) return first.response;
  const second = await ask();
  if ("response" in second) return second.response;
  const doc = second.doc;

  // What the Auth calls use comes from the database's answer, not from the request: the address it
  // normalised, the address the account has now.
  const normalised = doc["new_email"];
  const current = doc["current_email"];
  if (action === "change_email" && (typeof normalised !== "string" || normalised === "")) {
    return refuse("PREFLIGHT_FAILED");
  }
  if (action === "send_recovery" && (typeof current !== "string" || current === "")) {
    return refuse("PREFLIGHT_FAILED");
  }

  // The audit event, AS THE CALLER, retried once when the call itself failed. A refusal that carries
  // a business token is not retried: asking again will not change the answer.
  const audit = async (name: string, args: Json): Promise<boolean> => {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const result = await asCaller(name, args);
        if (result.ok) return true;
        if (tokenOf(result) !== null) break;
      } catch {
        // try once more
      }
    }
    console.error(`audit not recorded: ${action}`);
    return false;
  };

  // ---- 4 and 5. the action ---------------------------------------------------------------
  if (action === "send_recovery") {
    const sent = await sendRecovery(fetchFn, env, current as string, redirectTo);
    if (sent.kind === "refused") {
      return refuse(sent.token, sent.retryAfter ? { retry_after: sent.retryAfter } : {});
    }
    if (sent.kind === "unknown") return refuse("RECOVERY_SEND_FAILED");
    const recorded = await audit("admin_record_user_recovery_sent", {
      p_user_id: userId,
      p_reason: reason,
      p_after_email_change: false,
    });
    return reply(200, {
      ok: true,
      action,
      recovery_sent: true,
      audit_recorded: recorded,
    });
  }

  if (action === "set_password") {
    const updated = await adminUpdate(fetchFn, env, userId, { password }, (_status, code) => {
      if (code === "weak_password" || code === "same_password") return "INVALID_PASSWORD";
      if (code === "user_not_found") return "USER_NOT_FOUND";
      return "AUTH_UPDATE_REFUSED";
    });
    if (updated.kind === "refused") {
      console.error(`password update refused: ${updated.token}`);
      return refuse(updated.token, updated.retryAfter ? { retry_after: updated.retryAfter } : {});
    }
    if (updated.kind === "unknown") {
      console.error("password update outcome unknown");
      return refuse("AUTH_OUTCOME_UNKNOWN");
    }
    const recorded = await audit("admin_record_user_password_set", {
      p_user_id: userId,
      p_reason: reason,
    });
    return reply(200, { ok: true, action, password_set: true, audit_recorded: recorded });
  }

  // change_email
  const email = normalised as string;
  const updated = await adminUpdate(
    fetchFn,
    env,
    userId,
    { email, email_confirm: true },
    (_status, code) => {
      if (code === "email_exists" || code === "user_already_exists") return "EMAIL_TAKEN";
      if (code === "validation_failed") return "INVALID_EMAIL";
      if (code === "user_not_found") return "USER_NOT_FOUND";
      return "AUTH_UPDATE_REFUSED";
    },
  );
  if (updated.kind === "refused") {
    console.error(`email update refused: ${updated.token}`);
    return refuse(updated.token, updated.retryAfter ? { retry_after: updated.retryAfter } : {});
  }
  if (updated.kind === "unknown") {
    console.error("email update outcome unknown");
    return refuse("AUTH_OUTCOME_UNKNOWN");
  }

  // The email IS changed from here on. Everything below reports; nothing below undoes it.
  let recorded = await audit("admin_record_user_email_changed", {
    p_user_id: userId,
    p_reason: reason,
  });

  const recovery = await sendRecovery(fetchFn, env, email, redirectTo);
  let recoverySent = false;
  let recoveryError: string | undefined;
  let retryAfter: number | undefined;
  if (recovery.kind === "ok") {
    recoverySent = true;
    const ok = await audit("admin_record_user_recovery_sent", {
      p_user_id: userId,
      p_reason: reason,
      p_after_email_change: true,
    });
    recorded = recorded && ok;
  } else if (recovery.kind === "refused") {
    recoveryError = recovery.token;
    retryAfter = recovery.retryAfter;
    console.error(`recovery after email change refused: ${recovery.token}`);
  } else {
    recoveryError = "RECOVERY_SEND_FAILED";
    console.error("recovery after email change: outcome unknown");
  }

  return reply(200, {
    ok: true,
    action,
    email_changed: true,
    recovery_sent: recoverySent,
    ...(recoveryError ? { recovery_error: recoveryError } : {}),
    ...(retryAfter ? { retry_after: retryAfter } : {}),
    audit_recorded: recorded,
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
