// Behaviour of the admin authentication function against a fake backend: who may reach what, in which
// order, what each Auth call is allowed to carry, what each failure leaves, and that no secret travels
// where it should not. Run with `node --test` (Node 22.18+ strips the types itself); no dependency, and
// nothing here touches a real project, sends a real email or changes a real credential.
//
//   node --test supabase/functions/admin-user-auth/index.test.ts
import assert from "node:assert/strict";
import test from "node:test";
import { handle } from "./index.ts";

const TARGET = "00000000-0000-4000-8000-0000000000ab";
const ENV = { url: "https://p.test", anonKey: "ANON", serviceKey: "SERVICE" };
const JWT = "admin-jwt";
const REDIRECT = "goplay://login-callback/recovery";
const PASSWORD = "S3cret-pass-ūnicode!";
const OLD_EMAIL = "old.address@example.test";
const NEW_EMAIL = "new.address@example.test";

interface Call {
  method: string;
  path: string;
  search: string;
  caller: "user" | "service" | "anon" | "none";
  body: any;
}

type Scripted = { status: number; body?: any; headers?: Record<string, string> } | "network";

interface Options {
  /// Successive answers of admin_check_user_auth_action. The last one repeats.
  check?: Scripted[];
  put?: Scripted;
  recover?: Scripted;
  /// Per audit function, successive answers. The last one repeats.
  audit?: Record<string, Scripted[]>;
}

const pgError = (message: string): Scripted => ({
  status: 400,
  body: { code: "P0001", details: null, hint: null, message },
});

function checkDoc(over: Record<string, unknown> = {}) {
  return {
    version: 1,
    user_id: TARGET,
    action: "CHANGE_EMAIL",
    current_email: OLD_EMAIL,
    has_google: false,
    providers: ["email"],
    new_email: NEW_EMAIL,
    ...over,
  };
}

/// A backend that records every call and says who made it.
function backend(options: Options = {}) {
  const calls: Call[] = [];
  const counters: Record<string, number> = {};
  const who = (headers: Headers): Call["caller"] => {
    const bearer = (headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (bearer === JWT) return "user";
    if (bearer === ENV.serviceKey) return "service";
    if (bearer === ENV.anonKey) return "anon";
    return "none";
  };
  const answer = (s: Scripted): Response => {
    if (s === "network") throw new TypeError("connection reset");
    return new Response(s.body === undefined ? "" : JSON.stringify(s.body), {
      status: s.status,
      headers: { "Content-Type": "application/json", ...(s.headers ?? {}) },
    });
  };
  const next = (key: string, list: Scripted[]): Scripted => {
    const i = counters[key] ?? 0;
    counters[key] = i + 1;
    return list[Math.min(i, list.length - 1)];
  };

  const fetchFn = (async (input: any, init: any) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    const body = init?.body ? JSON.parse(init.body) : null;
    const call: Call = {
      method: init?.method ?? "GET",
      path: url.pathname,
      search: url.search,
      caller: who(headers),
      body,
    };
    calls.push(call);

    if (url.pathname === "/rest/v1/rpc/admin_check_user_auth_action") {
      if (call.caller !== "user") return answer({ status: 401, body: { message: "JWT expired" } });
      return answer(next("check", options.check ?? [{ status: 200, body: checkDoc() }]));
    }
    const auditFn = /^\/rest\/v1\/rpc\/(admin_record_user_[a-z_]+)$/.exec(url.pathname);
    if (auditFn) {
      if (call.caller !== "user") return answer({ status: 401, body: { message: "JWT expired" } });
      const list = options.audit?.[auditFn[1]] ?? [{ status: 200, body: "11111111-1111-4111-8111-111111111111" }];
      return answer(next(auditFn[1], list));
    }
    if (url.pathname === `/auth/v1/admin/users/${TARGET}` && call.method === "PUT") {
      if (call.caller !== "service") return answer({ status: 401, body: { msg: "no" } });
      return answer(options.put ?? { status: 200, body: { id: TARGET } });
    }
    if (url.pathname === "/auth/v1/recover" && call.method === "POST") {
      return answer(options.recover ?? { status: 200, body: {} });
    }
    throw new Error(`unexpected call ${call.method} ${url.pathname}`);
  }) as typeof fetch;

  return { fetchFn, calls };
}

function request(body: unknown, { jwt = JWT, method = "POST" }: { jwt?: string | null; method?: string } = {}) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (jwt !== null) headers["Authorization"] = `Bearer ${jwt}`;
  return new Request("https://p.test/functions/v1/admin-user-auth", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const CHANGE = { action: "change_email", user_id: TARGET, reason: "Support ticket 12", new_email: "  New.Address@Example.test ", redirect_to: REDIRECT };
const RECOVER = { action: "send_recovery", user_id: TARGET, reason: "Locked out", redirect_to: REDIRECT };
const SETPW = { action: "set_password", user_id: TARGET, reason: "Phone call verified", password: PASSWORD };

const names = (calls: Call[]) =>
  calls.map((c) => `${c.caller}:${c.method} ${c.path.replace("/rest/v1/rpc/", "rpc/").replace("/auth/v1/", "auth/").replace(TARGET, "{id}")}`);

/// Runs [fn] with console.error/log captured, and returns what was written.
async function logged<T>(fn: () => Promise<T>): Promise<{ result: T; logs: string }> {
  const out: string[] = [];
  const e = console.error;
  const l = console.log;
  const w = console.warn;
  console.error = (...a: unknown[]) => void out.push(a.map(String).join(" "));
  console.log = (...a: unknown[]) => void out.push(a.map(String).join(" "));
  console.warn = (...a: unknown[]) => void out.push(a.map(String).join(" "));
  try {
    return { result: await fn(), logs: out.join("\n") };
  } finally {
    console.error = e;
    console.log = l;
    console.warn = w;
  }
}

// ----------------------------------------------------------------------------- the request
test("OPTIONS is answered for the browser, anything but POST is refused, with no call", async () => {
  const b = backend();
  assert.equal((await handle(request(null, { method: "OPTIONS" }), ENV, b.fetchFn)).status, 204);
  assert.equal((await handle(request(null, { method: "GET" }), ENV, b.fetchFn)).status, 405);
  assert.deepEqual(b.calls, []);
});

test("no token: refused before anything is called", async () => {
  const b = backend();
  const res = await handle(request(RECOVER, { jwt: null }), ENV, b.fetchFn);
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error, "NOT_AUTHENTICATED");
  assert.deepEqual(b.calls, []);
});

test("a request that is not valid is refused before anything is called", async () => {
  const bad: [string, unknown, string][] = [
    ["not an object", [1], "BAD_REQUEST"],
    ["no action", { ...RECOVER, action: undefined }, "BAD_REQUEST"],
    ["unknown action", { ...RECOVER, action: "delete_user" }, "BAD_REQUEST"],
    ["the SQL spelling of an action", { ...RECOVER, action: "SEND_RECOVERY" }, "BAD_REQUEST"],
    ["no user", { ...RECOVER, user_id: undefined }, "BAD_REQUEST"],
    ["a user that is not a uuid", { ...RECOVER, user_id: "1; drop table" }, "BAD_REQUEST"],
    ["a user with a path in it", { ...RECOVER, user_id: `${TARGET}/../x` }, "BAD_REQUEST"],
    ["no reason", { ...RECOVER, reason: undefined }, "INVALID_REASON"],
    ["a blank reason", { ...RECOVER, reason: "   " }, "INVALID_REASON"],
    ["a reason that is not text", { ...RECOVER, reason: 5 }, "INVALID_REASON"],
    ["a reason of 501 characters", { ...RECOVER, reason: "x".repeat(501) }, "INVALID_REASON"],
    ["no redirect", { ...RECOVER, redirect_to: undefined }, "BAD_REQUEST"],
    ["a redirect to another site", { ...RECOVER, redirect_to: "https://evil.example/login-callback/recovery#x" }, "BAD_REQUEST"],
    ["a redirect to the wrong path", { ...RECOVER, redirect_to: "goplay://login-callback" }, "BAD_REQUEST"],
    ["a redirect with a query", { ...RECOVER, redirect_to: "https://app.example/login-callback/recovery?x=1" }, "BAD_REQUEST"],
    ["a redirect with credentials", { ...RECOVER, redirect_to: "https://a@app.example/login-callback/recovery" }, "BAD_REQUEST"],
    ["a plain-http redirect to a real host", { ...RECOVER, redirect_to: "http://app.example/login-callback/recovery" }, "BAD_REQUEST"],
    ["a javascript redirect", { ...RECOVER, redirect_to: "javascript:alert(1)" }, "BAD_REQUEST"],
    ["a password sent with a recovery", { ...RECOVER, password: PASSWORD }, "BAD_REQUEST"],
    ["a password sent with an email change", { ...CHANGE, password: PASSWORD }, "BAD_REQUEST"],
    ["an address sent with a password change", { ...SETPW, new_email: NEW_EMAIL }, "BAD_REQUEST"],
    ["an email change without an address", { ...CHANGE, new_email: undefined }, "INVALID_EMAIL"],
    ["an email change with a blank address", { ...CHANGE, new_email: "   " }, "INVALID_EMAIL"],
    ["an address of 300 characters", { ...CHANGE, new_email: "x".repeat(300) + "@example.test" }, "INVALID_EMAIL"],
    ["an address that is not text", { ...CHANGE, new_email: 7 }, "INVALID_EMAIL"],
    ["no password", { ...SETPW, password: undefined }, "INVALID_PASSWORD"],
    ["a password of 7 characters", { ...SETPW, password: "1234567" }, "INVALID_PASSWORD"],
    ["a password that is not text", { ...SETPW, password: 12345678 }, "INVALID_PASSWORD"],
    ["a password longer than 72 bytes", { ...SETPW, password: "a".repeat(73) }, "INVALID_PASSWORD"],
    ["a short-looking password that is over 72 bytes in UTF-8", { ...SETPW, password: "ū".repeat(37) }, "INVALID_PASSWORD"],
  ];
  for (const [label, body, token] of bad) {
    const b = backend();
    const res = await handle(request(body), ENV, b.fetchFn);
    assert.equal((await res.json()).error, token, label);
    assert.deepEqual(b.calls, [], `${label}: nothing was called`);
  }
  const b = backend();
  const res = await handle(
    new Request("https://p.test/f", { method: "POST", headers: { Authorization: `Bearer ${JWT}` }, body: "{not json" }),
    ENV,
    b.fetchFn,
  );
  assert.equal((await res.json()).error, "BAD_REQUEST");
  assert.deepEqual(b.calls, []);
});

const PROD = "https://go-play-44y.pages.dev";
const STAGING = "https://go-play-staging.pages.dev";
const PATH = "/login-callback/recovery";

test("the redirect allowlist accepts exactly these: both hosts, the app scheme, and a local server on any valid port", async () => {
  for (const redirect of [
    `${PROD}${PATH}`,
    `${STAGING}${PATH}`,
    `goplay://login-callback/recovery`,
    `http://localhost${PATH}`,
    `http://localhost:5000${PATH}`,
    `http://localhost:1${PATH}`,
    `http://localhost:65535${PATH}`,
    `http://127.0.0.1${PATH}`,
    `http://127.0.0.1:8080${PATH}`,
  ]) {
    for (const base of [RECOVER, CHANGE]) {
      const b = backend();
      const res = await handle(request({ ...base, redirect_to: redirect }), ENV, b.fetchFn);
      assert.equal(res.status, 200, `${base.action}: ${redirect}`);
      // the link the provider is asked to send is the one that was validated, byte for byte
      const recover = b.calls.filter((c) => c.path === "/auth/v1/recover");
      assert.equal(recover.length, 1);
      assert.equal(new URLSearchParams(recover[0].search).get("redirect_to"), redirect);
    }
  }
});

test("the redirect allowlist refuses everything else, before anything is called", async () => {
  const refused: [string, string[]][] = [
    ["an HTTPS domain nobody approved", [
      `https://app.example.com${PATH}`,
      `https://evil.example${PATH}`,
      `https://pages.dev${PATH}`,
      `https://go-play.pages.dev${PATH}`,
      `https://go-play-44y.example.com${PATH}`,
    ]],
    ["a lookalike or a subdomain of an approved host", [
      `https://go-play-44y.pages.dev.evil.example${PATH}`,
      `https://evil.go-play-44y.pages.dev${PATH}`,
      `https://www.go-play-44y.pages.dev${PATH}`,
      `https://xgo-play-44y.pages.dev${PATH}`,
      `https://go-play-44y-pages.dev${PATH}`,
      `https://go-play-staging.pages.dev.evil.example${PATH}`,
      `https://sub.go-play-staging.pages.dev${PATH}`,
      `https://go-play-44y.pages.dev.${PATH}`,
    ]],
    ["a username or credentials in the address", [
      `https://evil.example@go-play-44y.pages.dev${PATH}`,
      `https://go-play-44y.pages.dev@evil.example${PATH}`,
      `https://user:pass@go-play-44y.pages.dev${PATH}`,
      `https://user@go-play-staging.pages.dev${PATH}`,
      `http://evil.example@localhost${PATH}`,
      `http://localhost@evil.example${PATH}`,
      `goplay://user@login-callback/recovery`,
    ]],
    ["a port on a production host, even the default one", [
      `${PROD}:443${PATH}`,
      `${PROD}:8443${PATH}`,
      `${PROD}:80${PATH}`,
      `${PROD}:${PATH}`,
      `${STAGING}:443${PATH}`,
      `${STAGING}:8080${PATH}`,
    ]],
    ["a query string or a fragment", [
      `${PROD}${PATH}?x=1`,
      `${PROD}${PATH}?`,
      `${PROD}${PATH}#access_token=x`,
      `${PROD}${PATH}#`,
      `${STAGING}${PATH}?next=https://evil.example`,
      `goplay://login-callback/recovery?x=1`,
      `goplay://login-callback/recovery#x`,
      `http://localhost:5000${PATH}?x=1`,
      `http://127.0.0.1${PATH}#x`,
    ]],
    ["another path", [
      `${PROD}/login-callback`,
      `${PROD}${PATH}/`,
      `${PROD}${PATH}/x`,
      `${PROD}/Login-Callback/Recovery`,
      `${PROD}//login-callback/recovery`,
      `${PROD}/login-callback/../login-callback/recovery`,
      `${PROD}/login-callback/recovery%2f..`,
      `${PROD}/`,
      PROD,
      `goplay://login-callback`,
      `goplay://login-callback/recovery/`,
      `goplay:///login-callback/recovery`,
      `goplay://evil/login-callback/recovery`,
      `http://localhost:5000/login-callback`,
      `http://localhost${PATH}/`,
    ]],
    ["another scheme or another case", [
      `http://go-play-44y.pages.dev${PATH}`,
      `http://go-play-staging.pages.dev${PATH}`,
      `HTTPS://go-play-44y.pages.dev${PATH}`,
      `Https://go-play-44y.pages.dev${PATH}`,
      `https://GO-PLAY-44Y.pages.dev${PATH}`,
      `https://Go-Play-Staging.pages.dev${PATH}`,
      `GoPlay://login-callback/recovery`,
      `goplay://LOGIN-CALLBACK/recovery`,
      `https://localhost${PATH}`,
      `https://127.0.0.1${PATH}`,
      `javascript:alert(1)`,
      `data:text/html,x`,
      `ftp://go-play-44y.pages.dev${PATH}`,
    ]],
    ["a local address that is not one of the two, or a port that is not one", [
      `http://localhost.evil.example${PATH}`,
      `http://127.0.0.1.evil.example${PATH}`,
      `http://LOCALHOST${PATH}`,
      `http://127.1${PATH}`,
      `http://0.0.0.0:5000${PATH}`,
      `http://[::1]:5000${PATH}`,
      `http://192.168.1.10:5000${PATH}`,
      `http://localhost:${PATH}`,
      `http://localhost:0${PATH}`,
      `http://localhost:05000${PATH}`,
      `http://localhost:65536${PATH}`,
      `http://localhost:99999${PATH}`,
      `http://localhost:123456${PATH}`,
      `http://localhost:80a${PATH}`,
      `http://localhost:-1${PATH}`,
    ]],
    ["whitespace or control characters", [
      ` ${PROD}${PATH}`,
      `${PROD}${PATH} `,
      `${PROD}${PATH}\n`,
      `${PROD}${PATH}\r\n`,
      `${PROD}${PATH}\t`,
      `\n${PROD}${PATH}`,
      `${PROD}${PATH}%20`,
      `${PROD}${PATH}\u0000`,
      `goplay://login-callback/recovery\n`,
      `http://localhost:5000${PATH}\n`,
      "",
      "   ",
    ]],
  ];
  let count = 0;
  for (const [reason, urls] of refused) {
    for (const redirect of urls) {
      for (const base of [RECOVER, CHANGE]) {
        const b = backend();
        const res = await handle(request({ ...base, redirect_to: redirect }), ENV, b.fetchFn);
        assert.equal(res.status, 400, `${reason}: ${JSON.stringify(redirect)} (${base.action})`);
        assert.equal((await res.json()).error, "BAD_REQUEST");
        assert.deepEqual(b.calls, [], `${reason}: ${JSON.stringify(redirect)}: nothing was called`);
        count++;
      }
    }
  }
  assert.ok(count > 150, `only ${count} cases ran`);
});

test("a redirect that is not text, or is missing, is refused too", async () => {
  for (const redirect of [undefined, null, 5, true, [`${PROD}${PATH}`], { url: `${PROD}${PATH}` }]) {
    for (const base of [RECOVER, CHANGE]) {
      const b = backend();
      const res = await handle(request({ ...base, redirect_to: redirect }), ENV, b.fetchFn);
      assert.equal(res.status, 400, JSON.stringify(redirect));
      assert.deepEqual(b.calls, []);
    }
  }
});

test("setting a password does not take a redirect at all: the allowlist does not touch it", async () => {
  const b = backend();
  const res = await handle(request({ ...SETPW, redirect_to: "https://evil.example/x" }), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  assert.equal(b.calls.filter((c) => c.path === "/auth/v1/recover").length, 0, "no mail, so no link");
  assert.ok(!JSON.stringify(b.calls.map((c) => c.body)).includes("evil.example"), "and the address is forwarded nowhere");
});

// ----------------------------------------------------------------------------- authorization
test("the check is asked AS THE CALLER, twice, before any Auth call, and the service role is never used for it", async () => {
  const b = backend();
  await handle(request(RECOVER), ENV, b.fetchFn);
  assert.deepEqual(names(b.calls).slice(0, 3), [
    "user:POST rpc/admin_check_user_auth_action",
    "user:POST rpc/admin_check_user_auth_action",
    "anon:POST auth/recover",
  ]);
  for (const c of b.calls.filter((c) => c.path.startsWith("/rest/v1/rpc/"))) {
    assert.equal(c.caller, "user", `${c.path} is called with the caller's token`);
  }
  assert.deepEqual(b.calls[0].body, { p_user_id: TARGET, p_action: "SEND_RECOVERY" });
});

test("the request cannot name the actor: no field of it reaches the database or Auth except the validated ones", async () => {
  const b = backend();
  await handle(
    request({ ...SETPW, actor_user_id: "00000000-0000-4000-8000-0000000000ff", actor: "x", p_actor: "y", role: "service_role", ban_duration: "100y", app_metadata: { a: 1 }, email: "evil@example.test" }),
    ENV,
    b.fetchFn,
  );
  const sent = JSON.stringify(b.calls.map((c) => c.body));
  for (const word of ["actor", "service_role", "ban_duration", "app_metadata", "evil@example.test", "p_actor"]) {
    assert.ok(!sent.includes(word), `${word} was forwarded`);
  }
  const put = b.calls.find((c) => c.method === "PUT")!;
  assert.deepEqual(put.body, { password: PASSWORD }, "the Auth body is exactly the one fixed shape");
});

test("every refusal of the database is passed through with its own status, and no Auth call is made", async () => {
  const cases: [string, number][] = [
    ["NOT_AUTHORIZED", 403],
    ["CANNOT_MODIFY_SELF", 403],
    ["CANNOT_MODIFY_SYSTEM_ADMIN", 403],
    ["USER_NOT_FOUND", 404],
    ["GOOGLE_LINKED", 409],
    ["EMAIL_TAKEN", 409],
    ["EMAIL_UNCHANGED", 409],
    ["INVALID_EMAIL", 400],
    ["NO_EMAIL", 409],
  ];
  for (const [token, status] of cases) {
    const b = backend({ check: [pgError(token)] });
    const res = await handle(request(CHANGE), ENV, b.fetchFn);
    assert.equal(res.status, status, token);
    assert.equal((await res.json()).error, token);
    assert.deepEqual(names(b.calls), ["user:POST rpc/admin_check_user_auth_action"], `${token}: asked once, then stopped`);
  }
});

test("an expired or missing session at the database is NOT_AUTHENTICATED", async () => {
  const b = backend({ check: [{ status: 401, body: { code: "PGRST301", message: "JWT expired" } }] });
  const res = await handle(request(SETPW), ENV, b.fetchFn);
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error, "NOT_AUTHENTICATED");
  assert.equal(b.calls.filter((c) => c.path.startsWith("/auth/")).length, 0);
});

test("the database failing, or answering something that is not an answer, stops everything", async () => {
  for (const check of [
    ["network"],
    [{ status: 500, body: { message: "boom" } }],
    [{ status: 200, body: "nope" }],
    [{ status: 200, body: checkDoc({ user_id: "00000000-0000-4000-8000-0000000000cd" }) }],
    [{ status: 200, body: checkDoc({ new_email: null }) }],
  ] as Scripted[][]) {
    const b = backend({ check });
    const res = await handle(request(CHANGE), ENV, b.fetchFn);
    assert.equal((await res.json()).error, "PREFLIGHT_FAILED", JSON.stringify(check));
    assert.equal(b.calls.filter((c) => c.path.startsWith("/auth/")).length, 0);
  }
  const b = backend({ check: [{ status: 200, body: checkDoc({ current_email: "" }) }] });
  assert.equal((await (await handle(request(RECOVER), ENV, b.fetchFn)).json()).error, "PREFLIGHT_FAILED");
});

test("authorization is asked again immediately before the mutation: if it was withdrawn in between, nothing is changed", async () => {
  for (const [req, token] of [
    [CHANGE, "NOT_AUTHORIZED"],
    [SETPW, "CANNOT_MODIFY_SYSTEM_ADMIN"],
    [RECOVER, "USER_NOT_FOUND"],
  ] as [any, string][]) {
    const b = backend({ check: [{ status: 200, body: checkDoc() }, pgError(token)] });
    const res = await handle(request(req), ENV, b.fetchFn);
    assert.equal((await res.json()).error, token);
    assert.deepEqual(names(b.calls), ["user:POST rpc/admin_check_user_auth_action", "user:POST rpc/admin_check_user_auth_action"]);
  }
});

test("what the Auth call uses is the SECOND answer of the database, not the first", async () => {
  const change = backend({
    check: [
      { status: 200, body: checkDoc({ new_email: "stale.first.answer@example.test" }) },
      { status: 200, body: checkDoc({ new_email: NEW_EMAIL }) },
    ],
  });
  await handle(request(CHANGE), ENV, change.fetchFn);
  assert.deepEqual(change.calls.find((c) => c.method === "PUT")!.body, { email: NEW_EMAIL, email_confirm: true });

  const recover = backend({
    check: [
      { status: 200, body: checkDoc({ current_email: "stale.first.answer@example.test" }) },
      { status: 200, body: checkDoc({ current_email: OLD_EMAIL }) },
    ],
  });
  await handle(request(RECOVER), ENV, recover.fetchFn);
  assert.deepEqual(recover.calls.find((c) => c.path === "/auth/v1/recover")!.body, { email: OLD_EMAIL });
});

// ----------------------------------------------------------------------------- change email
test("change email: the order, the exact Auth body, the address the DATABASE normalised, then the recovery mail to the NEW address", async () => {
  const b = backend();
  const res = await handle(request(CHANGE), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/admin_check_user_auth_action",
    "user:POST rpc/admin_check_user_auth_action",
    "service:PUT auth/admin/users/{id}",
    "user:POST rpc/admin_record_user_email_changed",
    "anon:POST auth/recover",
    "user:POST rpc/admin_record_user_recovery_sent",
  ]);
  // what the database was asked: the address as typed (trimmed), the action in the database's spelling
  assert.deepEqual(b.calls[0].body, { p_user_id: TARGET, p_action: "CHANGE_EMAIL", p_new_email: "New.Address@Example.test" });
  // what Auth was told: the database's normalised address, confirmed, and nothing else
  const put = b.calls[2];
  assert.deepEqual(put.body, { email: NEW_EMAIL, email_confirm: true });
  // the recovery mail goes to the NEW address, with the app's own redirect, through the standard endpoint
  const recover = b.calls[4];
  assert.deepEqual(recover.body, { email: NEW_EMAIL });
  assert.equal(new URLSearchParams(recover.search).get("redirect_to"), REDIRECT);
  // the events
  assert.deepEqual(b.calls[3].body, { p_user_id: TARGET, p_reason: "Support ticket 12" });
  assert.deepEqual(b.calls[5].body, { p_user_id: TARGET, p_reason: "Support ticket 12", p_after_email_change: true });
  assert.deepEqual(await res.json(), { ok: true, action: "change_email", email_changed: true, recovery_sent: true, audit_recorded: true });
});

test("change email: the response and the logs carry no address", async () => {
  const b = backend();
  const { result, logs } = await logged(() => handle(request(CHANGE), ENV, b.fetchFn));
  const text = JSON.stringify(await result.json());
  for (const address of [OLD_EMAIL, NEW_EMAIL, "new.address", "old.address"]) {
    assert.ok(!text.toLowerCase().includes(address), `response holds ${address}`);
    assert.ok(!logs.toLowerCase().includes(address), `logs hold ${address}`);
  }
});

test("change email: the email is changed but the recovery mail is not sent -- reported as a partial success, not an error", async () => {
  for (const [recover, error] of [
    [{ status: 429, body: { error_code: "over_email_send_rate_limit" }, headers: { "retry-after": "42" } }, "RATE_LIMITED"],
    [{ status: 500, body: { msg: "smtp" } }, "RECOVERY_SEND_FAILED"],
    [{ status: 422, body: { error_code: "validation_failed" } }, "RECOVERY_SEND_FAILED"],
    ["network", "RECOVERY_SEND_FAILED"],
  ] as [Scripted, string][]) {
    const b = backend({ recover });
    const { result: res } = await logged(() => handle(request(CHANGE), ENV, b.fetchFn));
    assert.equal(res.status, 200, error);
    const body = await res.json();
    assert.equal(body.email_changed, true);
    assert.equal(body.recovery_sent, false);
    assert.equal(body.recovery_error, error);
    assert.equal(body.audit_recorded, true, "the email event was recorded");
    assert.equal(b.calls.filter((c) => c.path.endsWith("admin_record_user_recovery_sent")).length, 0, "and no recovery event, because none was sent");
    assert.equal(b.calls.filter((c) => c.method === "PUT").length, 1, "the email change is not retried or reverted");
  }
  const b = backend({ recover: { status: 429, body: {}, headers: { "retry-after": "42" } } });
  const body = await (await logged(() => handle(request(CHANGE), ENV, b.fetchFn))).result.json();
  assert.equal(body.retry_after, 42);
});

test("change email: Auth refusing the change leaves nothing: no event, no recovery mail", async () => {
  const cases: [Scripted, string, number][] = [
    [{ status: 422, body: { error_code: "email_exists" } }, "EMAIL_TAKEN", 409],
    [{ status: 422, body: { error_code: "validation_failed" } }, "INVALID_EMAIL", 400],
    [{ status: 404, body: { error_code: "user_not_found" } }, "USER_NOT_FOUND", 404],
    [{ status: 429, body: { error_code: "over_request_rate_limit" }, headers: { "retry-after": "9" } }, "RATE_LIMITED", 429],
    [{ status: 403, body: { error_code: "not_admin" } }, "AUTH_UPDATE_REFUSED", 502],
    [{ status: 401, body: { msg: "invalid JWT" } }, "AUTH_UPDATE_REFUSED", 502],
  ];
  for (const [put, token, status] of cases) {
    const b = backend({ put });
    const { result: res } = await logged(() => handle(request(CHANGE), ENV, b.fetchFn));
    assert.equal(res.status, status, token);
    assert.equal((await res.json()).error, token);
    assert.deepEqual(names(b.calls).slice(-1), ["service:PUT auth/admin/users/{id}"], `${token}: nothing after the Auth call`);
  }
});

test("change email: an Auth answer that was lost is UNKNOWN -- the change may have happened, so nothing is recorded and no mail is sent", async () => {
  for (const put of ["network", { status: 500, body: { msg: "x" } }, { status: 502, body: "bad gateway" }, { status: 504 }] as Scripted[]) {
    const b = backend({ put });
    const { result: res, logs } = await logged(() => handle(request(CHANGE), ENV, b.fetchFn));
    assert.equal(res.status, 502);
    assert.equal((await res.json()).error, "AUTH_OUTCOME_UNKNOWN");
    assert.deepEqual(names(b.calls).slice(-1), ["service:PUT auth/admin/users/{id}"]);
    assert.ok(!logs.includes(NEW_EMAIL));
  }
});

test("change email: the audit event failing is a success that says so, and the mail is still sent; the event is retried once", async () => {
  const b = backend({ audit: { admin_record_user_email_changed: [{ status: 500, body: "boom" }, { status: 500, body: "boom" }] } });
  const { result: res } = await logged(() => handle(request(CHANGE), ENV, b.fetchFn));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual([body.email_changed, body.recovery_sent, body.audit_recorded], [true, true, false]);
  assert.equal(b.calls.filter((c) => c.path.endsWith("admin_record_user_email_changed")).length, 2, "tried twice");

  const c = backend({ audit: { admin_record_user_email_changed: ["network", { status: 200, body: "id" }] } });
  const ok = await (await logged(() => handle(request(CHANGE), ENV, c.fetchFn))).result.json();
  assert.equal(ok.audit_recorded, true, "a transient failure on the first try is covered by the retry");

  const d = backend({ audit: { admin_record_user_email_changed: [pgError("NOT_AUTHORIZED")] } });
  const refused = await (await logged(() => handle(request(CHANGE), ENV, d.fetchFn))).result.json();
  assert.equal(refused.audit_recorded, false);
  assert.equal(d.calls.filter((c) => c.path.endsWith("admin_record_user_email_changed")).length, 1, "a refusal with a token is not retried");
});

test("change email: a second try after the first succeeded is refused by the database, with no Auth call", async () => {
  const b = backend({ check: [pgError("EMAIL_UNCHANGED")] });
  const res = await handle(request(CHANGE), ENV, b.fetchFn);
  assert.equal(res.status, 409);
  assert.equal(b.calls.filter((c) => c.path.startsWith("/auth/")).length, 0);
});

// ----------------------------------------------------------------------------- send recovery
test("send recovery: the standard mail to the CURRENT address, one event, and no credential is touched", async () => {
  const b = backend({ check: [{ status: 200, body: checkDoc({ action: "SEND_RECOVERY", new_email: null }) }] });
  const res = await handle(request(RECOVER), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/admin_check_user_auth_action",
    "user:POST rpc/admin_check_user_auth_action",
    "anon:POST auth/recover",
    "user:POST rpc/admin_record_user_recovery_sent",
  ]);
  assert.equal(b.calls.filter((c) => c.method === "PUT").length, 0, "no Admin API call at all");
  assert.equal(b.calls.filter((c) => c.caller === "service").length, 0, "the service role is not used");
  assert.deepEqual(b.calls[2].body, { email: OLD_EMAIL });
  assert.deepEqual(b.calls[3].body, { p_user_id: TARGET, p_reason: "Locked out", p_after_email_change: false });
  assert.deepEqual(await res.json(), { ok: true, action: "send_recovery", recovery_sent: true, audit_recorded: true });
});

test("send recovery: the provider's limits and failures are reported and nothing is recorded", async () => {
  const limited = backend({ recover: { status: 429, body: { error_code: "over_email_send_rate_limit" }, headers: { "retry-after": "55" } } });
  const res = await handle(request(RECOVER), ENV, limited.fetchFn);
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), { error: "RATE_LIMITED", retry_after: 55 });
  assert.equal(limited.calls.filter((c) => c.path.includes("admin_record_user")).length, 0);

  const noHeader = backend({ recover: { status: 429, body: {} } });
  assert.deepEqual(await (await handle(request(RECOVER), ENV, noHeader.fetchFn)).json(), { error: "RATE_LIMITED" });

  for (const recover of [{ status: 500, body: { msg: "smtp" } }, "network", { status: 422, body: { error_code: "validation_failed" } }] as Scripted[]) {
    const b = backend({ recover });
    const { result: r } = await logged(() => handle(request(RECOVER), ENV, b.fetchFn));
    assert.equal(r.status, 502);
    assert.equal((await r.json()).error, "RECOVERY_SEND_FAILED");
    assert.equal(b.calls.filter((c) => c.path.includes("admin_record_user")).length, 0, "no event for a mail that was not requested");
  }
});

test("send recovery: a failed audit write is a success that says so; a retry is a fresh, safe request", async () => {
  const b = backend({ audit: { admin_record_user_recovery_sent: [{ status: 500, body: "x" }] } });
  const { result: res } = await logged(() => handle(request(RECOVER), ENV, b.fetchFn));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, action: "send_recovery", recovery_sent: true, audit_recorded: false });

  // the retry after a partial email change is the same request, and does not depend on any earlier one
  const again = backend();
  assert.equal((await handle(request(RECOVER), ENV, again.fetchFn)).status, 200);
  assert.equal(again.calls.filter((c) => c.method === "PUT").length, 0);
});

// ----------------------------------------------------------------------------- set password
test("set password: the exact Auth body, one event, and the password goes nowhere else", async () => {
  const b = backend({ check: [{ status: 200, body: checkDoc({ action: "SET_PASSWORD", new_email: null }) }] });
  const { result: res, logs } = await logged(() => handle(request(SETPW), ENV, b.fetchFn));
  assert.equal(res.status, 200);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/admin_check_user_auth_action",
    "user:POST rpc/admin_check_user_auth_action",
    "service:PUT auth/admin/users/{id}",
    "user:POST rpc/admin_record_user_password_set",
  ]);
  assert.deepEqual(b.calls[2].body, { password: PASSWORD });
  assert.deepEqual(b.calls[3].body, { p_user_id: TARGET, p_reason: "Phone call verified" });
  const responseText = await res.text();
  assert.deepEqual(JSON.parse(responseText), { ok: true, action: "set_password", password_set: true, audit_recorded: true });

  // the password appears in exactly one request body: the Auth Admin PUT
  const holders = b.calls.filter((c) => JSON.stringify(c.body).includes(PASSWORD));
  assert.deepEqual(holders.map((c) => `${c.method} ${c.path}`), [`PUT /auth/v1/admin/users/${TARGET}`]);
  for (const c of b.calls) {
    assert.ok(!c.search.includes("S3cret") && !c.path.includes("S3cret"), "never in a URL");
  }
  assert.ok(!logs.includes("S3cret"), "never in a log");
  assert.ok(!responseText.includes("S3cret"), "never in the response");
});

test("set password: wherever it fails, the password is in no log and no response", async () => {
  const outcomes: Scripted[] = [
    { status: 422, body: { error_code: "weak_password", msg: `Password ${PASSWORD} is weak` } },
    { status: 422, body: { error_code: "same_password" } },
    { status: 429, body: {}, headers: { "retry-after": "30" } },
    { status: 500, body: { msg: PASSWORD } },
    { status: 403, body: { msg: PASSWORD } },
    "network",
  ];
  for (const put of outcomes) {
    const b = backend({ put });
    const { result: res, logs } = await logged(() => handle(request(SETPW), ENV, b.fetchFn));
    const text = await res.text();
    assert.ok(!text.includes("S3cret") && !logs.includes("S3cret"), JSON.stringify(put));
    assert.equal(b.calls.filter((c) => c.path.includes("admin_record_user")).length, 0, "no event for a password that was not set");
  }
});

test("set password: what Auth says maps to a clear refusal, and an unknown answer is not reported as a failure to change", async () => {
  const cases: [Scripted, string, number][] = [
    [{ status: 422, body: { error_code: "weak_password" } }, "INVALID_PASSWORD", 400],
    [{ status: 422, body: { error_code: "same_password" } }, "INVALID_PASSWORD", 400],
    [{ status: 404, body: { error_code: "user_not_found" } }, "USER_NOT_FOUND", 404],
    [{ status: 429, body: {} }, "RATE_LIMITED", 429],
    [{ status: 400, body: { msg: "x" } }, "AUTH_UPDATE_REFUSED", 502],
    [{ status: 500, body: { msg: "x" } }, "AUTH_OUTCOME_UNKNOWN", 502],
    [{ status: 503 }, "AUTH_OUTCOME_UNKNOWN", 502],
    ["network", "AUTH_OUTCOME_UNKNOWN", 502],
  ];
  for (const [put, token, status] of cases) {
    const b = backend({ put });
    const { result: res } = await logged(() => handle(request(SETPW), ENV, b.fetchFn));
    assert.equal(res.status, status, token);
    assert.equal((await res.json()).error, token);
  }
});

test("set password: a failed audit write is a success that says so -- the password IS set", async () => {
  const b = backend({ audit: { admin_record_user_password_set: [{ status: 500, body: "x" }] } });
  const { result: res } = await logged(() => handle(request(SETPW), ENV, b.fetchFn));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, action: "set_password", password_set: true, audit_recorded: false });
});

test("set password: the minimum is the product's (8 characters) and the maximum is the hash's (72 bytes)", async () => {
  for (const ok of ["12345678", "a".repeat(72), "ū".repeat(36)]) {
    const b = backend();
    assert.equal((await handle(request({ ...SETPW, password: ok }), ENV, b.fetchFn)).status, 200, ok.length + " chars");
  }
});

// ----------------------------------------------------------------------------- the service role
test("the service role reaches nothing but the Admin API call; the caller's token never reaches Auth", async () => {
  for (const req of [CHANGE, RECOVER, SETPW]) {
    const b = backend();
    await handle(request(req), ENV, b.fetchFn);
    for (const c of b.calls) {
      if (c.caller === "service") assert.equal(c.path, `/auth/v1/admin/users/${TARGET}`, "service role only on the Admin API");
      if (c.path.startsWith("/auth/")) assert.notEqual(c.caller, "user", "the caller's token is never sent to Auth");
      if (c.path.startsWith("/rest/")) assert.notEqual(c.caller, "service", "the service role never reaches the database");
    }
  }
});
