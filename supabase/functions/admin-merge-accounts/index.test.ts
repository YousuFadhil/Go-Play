// Behaviour of the merge function against a fake backend: who may reach what, in which
// order, and what each failure leaves behind. Run with `node --test` (Node 22.18+ strips
// the types itself); no dependency, and nothing here touches a real project.
//
//   node --test supabase/functions/admin-merge-accounts/
import assert from "node:assert/strict";
import test from "node:test";
import { handle } from "./index.ts";

const RETAINED = "00000000-0000-4000-8000-000000000002";
const SOURCE = "00000000-0000-4000-8000-000000000003";
const M1 = "e15d4a62-9c37-4e79-ad50-b84e36d458f3";
const M2 = "250a22ba-6589-45c9-afed-e3f6716742ab";

const ENV = { url: "https://p.test", anonKey: "ANON", serviceKey: "SERVICE" };
const JWT = "user-jwt";

interface Call {
  method: string;
  path: string;
  caller: "user" | "service" | "anon" | "none";
  body: any;
}

function match(id: string, keepRetained: boolean, keepSource: boolean) {
  return { match_id: id, can_keep_retained: keepRetained, can_keep_source: keepSource };
}

function previewDoc(over: { blockers?: string[]; items?: any[] } = {}) {
  const items = over.items ?? [];
  const blockers = over.blockers ?? [];
  return {
    version: 2,
    has_blockers: blockers.length > 0,
    findings: [
      ...blockers.map((code) => ({ code, severity: "BLOCKER", category: "X", count: 1 })),
      { code: "EVENT_LOGS_NAME_SOURCE", severity: "CONSTRAINT", category: "HISTORY", count: 2 },
    ],
    shared_matches: { items, total: items.length, unresolvable_total: 0 },
  };
}

interface Options {
  previewStatus?: number;
  preview?: any;
  merge?: { status: number; body: any } | "network";
  files?: string[];
  deleteStatus?: number;       // the Storage API answers this
  deleteRemoves?: boolean;     // ...and whether the objects really go
  deleteThrows?: boolean;
  listStatus?: number;
}

/// A backend that records every call and says who made it.
function backend(options: Options = {}) {
  const calls: Call[] = [];
  const state = { files: [...(options.files ?? [])], merged: false };
  const who = (headers: Headers): Call["caller"] => {
    const bearer = (headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (bearer === JWT) return "user";
    if (bearer === ENV.serviceKey) return "service";
    if (bearer === ENV.anonKey) return "anon";
    return "none";
  };
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

  const fetchFn = (async (input: any, init: any) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    const body = init?.body ? JSON.parse(init.body) : null;
    const call: Call = { method: init?.method ?? "GET", path: url.pathname, caller: who(headers), body };
    calls.push(call);

    if (url.pathname.endsWith("/rpc/admin_preview_account_merge")) {
      if (call.caller !== "user") return json(401, { code: "PGRST301", message: "JWT expired" });
      return json(options.previewStatus ?? 200, options.preview ?? previewDoc());
    }
    if (url.pathname.endsWith("/rpc/merge_source_stored_files")) {
      if (call.caller !== "service") return json(401, { message: "no" });
      if (options.listStatus && options.listStatus >= 400) return json(options.listStatus, { message: "boom" });
      return json(200, state.files);
    }
    if (url.pathname === "/storage/v1/object/avatars" && call.method === "DELETE") {
      if (options.deleteThrows) throw new TypeError("network down");
      if (call.caller !== "service") return json(403, { message: "no" });
      if (options.deleteRemoves !== false) {
        state.files = state.files.filter((n) => !body.prefixes.includes(n));
      }
      return json(options.deleteStatus ?? 200, body.prefixes.map((name: string) => ({ name })));
    }
    if (url.pathname.endsWith("/rpc/admin_merge_accounts")) {
      if (call.caller !== "user") return json(401, { message: "JWT expired" });
      if (options.merge === "network") throw new TypeError("connection reset");
      const merge = options.merge ?? { status: 200, body: { merged: true, retained_user_id: RETAINED, source_user_id: SOURCE } };
      if (merge.status < 300) state.merged = true;
      return json(merge.status, merge.body);
    }
    throw new Error(`unexpected call ${call.method} ${url.pathname}`);
  }) as typeof fetch;

  return { fetchFn, calls, state };
}

function request(body: unknown, { jwt = JWT, method = "POST" }: { jwt?: string | null; method?: string } = {}) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (jwt !== null) headers["Authorization"] = `Bearer ${jwt}`;
  return new Request("https://p.test/functions/v1/admin-merge-accounts", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const PAIR = { p_retained_user_id: RETAINED, p_source_user_id: SOURCE, p_resolutions: [] as any[] };
const names = (calls: Call[]) => calls.map((c) => `${c.caller}:${c.method} ${c.path.replace("/rest/v1/rpc/", "rpc/").replace("/storage/v1/object/", "storage/")}`);

const pgError = (message: string, details: string | null = null) => ({ status: 400, body: { code: "P0001", details, hint: null, message } });

// ----------------------------------------------------------------------------- authorization
test("no token: refused before anything is called", async () => {
  const b = backend();
  const res = await handle(request(PAIR, { jwt: null }), ENV, b.fetchFn);
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error, "NOT_AUTHENTICATED");
  assert.deepEqual(b.calls, []);
});

test("a signed-in user who is not a System Admin is refused, and no service-role call is made", async () => {
  const b = backend({ previewStatus: 400, preview: { code: "P0001", message: "NOT_AUTHORIZED", details: null, hint: null }, files: [`${SOURCE}/avatar.jpg`] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, "NOT_AUTHORIZED");
  assert.deepEqual(names(b.calls), ["user:POST rpc/admin_preview_account_merge"]);
  assert.deepEqual(b.state.files, [`${SOURCE}/avatar.jpg`], "the picture is untouched");
});

test("an expired or forged token is refused as unauthenticated", async () => {
  const b = backend();
  const res = await handle(request(PAIR, { jwt: "forged" }), ENV, b.fetchFn);
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error, "NOT_AUTHENTICATED");
  assert.deepEqual(names(b.calls), ["none:POST rpc/admin_preview_account_merge"]);
});

test("the service role key reaches only storage and the file list, never the preview or the merge", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  for (const c of b.calls) {
    const privileged = c.path.includes("merge_source_stored_files") || c.path.startsWith("/storage/");
    assert.equal(c.caller, privileged ? "service" : "user", `${c.path} ran as ${c.caller}`);
  }
});

// ----------------------------------------------------------------------------- bad requests
for (const [name, body, token] of [
  ["not an object", [], "BAD_REQUEST"],
  ["a malformed id", { ...PAIR, p_source_user_id: "nope" }, "BAD_REQUEST"],
  ["the same account twice", { ...PAIR, p_source_user_id: RETAINED }, "SAME_ACCOUNT"],
  ["resolutions that are not a list", { ...PAIR, p_resolutions: "x" }, "RESOLUTIONS_INVALID"],
  ["a resolution that keeps neither side", { ...PAIR, p_resolutions: [{ match_id: M1, keep: "both" }] }, "RESOLUTIONS_INVALID"],
  ["the same match twice", { ...PAIR, p_resolutions: [{ match_id: M1, keep: "source" }, { match_id: M1, keep: "retained" }] }, "RESOLUTIONS_INVALID"],
] as const) {
  test(`bad request (${name}): refused before anything is called`, async () => {
    const b = backend();
    const res = await handle(request(body), ENV, b.fetchFn);
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, token);
    assert.deepEqual(b.calls, []);
  });
}

test("an unreadable body is a bad request", async () => {
  const b = backend();
  const bad = new Request("https://p.test/f", { method: "POST", headers: { Authorization: `Bearer ${JWT}` }, body: "{not json" });
  const res = await handle(bad, ENV, b.fetchFn);
  assert.equal(res.status, 400);
  assert.deepEqual(b.calls, []);
});

test("the browser's preflight is answered, and every answer carries the CORS headers", async () => {
  const b = backend();
  const options = await handle(request(null, { method: "OPTIONS", jwt: null }), ENV, b.fetchFn);
  assert.equal(options.status, 204);
  assert.ok(options.headers.get("Access-Control-Allow-Headers")!.includes("authorization"));
  const refused = await handle(request(PAIR, { jwt: null }), ENV, b.fetchFn);
  assert.equal(refused.headers.get("Access-Control-Allow-Origin"), "*");
  const wrongMethod = await handle(request(null, { method: "GET" }), ENV, b.fetchFn);
  assert.equal(wrongMethod.status, 405);
  assert.deepEqual(b.calls, []);
});

// ----------------------------------------------------------------------------- preflight: nothing is deleted
test("a blocker stops everything before the picture is touched", async () => {
  const b = backend({ preview: previewDoc({ blockers: ["TEAM_AWARD_COLLISION", "SOURCE_IS_SYSTEM_ADMIN"] }), files: [`${SOURCE}/avatar.jpg`] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "MERGE_BLOCKED");
  assert.equal(body.detail, "TEAM_AWARD_COLLISION,SOURCE_IS_SYSTEM_ADMIN");
  assert.deepEqual(names(b.calls), ["user:POST rpc/admin_preview_account_merge"]);
  assert.deepEqual(b.state.files, [`${SOURCE}/avatar.jpg`]);
});

test("a preview that does not say has_blockers: false is treated as blocked", async () => {
  const doc: any = previewDoc();
  delete doc.has_blockers;
  const b = backend({ preview: doc, files: [`${SOURCE}/avatar.jpg`] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "MERGE_BLOCKED");
  assert.equal(b.calls.length, 1);
});

test("a preview the function cannot read stops it before the picture is touched", async () => {
  const b = backend({ preview: { has_blockers: false, findings: [] }, files: [`${SOURCE}/avatar.jpg`] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 502);
  assert.equal((await res.json()).error, "PREFLIGHT_FAILED");
  assert.deepEqual(b.state.files, [`${SOURCE}/avatar.jpg`]);
});

test("a missing choice, an unknown match and a closed side are refused before the picture is touched", async () => {
  const items = [match(M1, true, true), match(M2, false, true)];
  const files = [`${SOURCE}/avatar.jpg`];
  const cases: [any[], string][] = [
    [[{ match_id: M1, keep: "retained" }], "RESOLUTION_REQUIRED"],
    [[{ match_id: M1, keep: "retained" }, { match_id: M2, keep: "source" }, { match_id: "00000000-0000-4000-8000-0000000000ff", keep: "source" }], "RESOLUTION_UNKNOWN_MATCH"],
    [[{ match_id: M1, keep: "retained" }, { match_id: M2, keep: "retained" }], "RESOLUTION_BLOCKED"],
  ];
  for (const [resolutions, token] of cases) {
    const b = backend({ preview: previewDoc({ items }), files });
    const res = await handle(request({ ...PAIR, p_resolutions: resolutions }), ENV, b.fetchFn);
    assert.equal(res.status, 409, token);
    assert.equal((await res.json()).error, token);
    assert.deepEqual(names(b.calls), ["user:POST rpc/admin_preview_account_merge"], token);
    assert.deepEqual(b.state.files, files, token);
  }
});

// ----------------------------------------------------------------------------- the merge, with and without a picture
test("with a picture: preview, list, delete exactly the source's objects, list again, then merge", async () => {
  const files = [`${SOURCE}/avatar.jpg`, `${SOURCE}/old/avatar.png`];
  const b = backend({ preview: previewDoc({ items: [match(M1, true, true)] }), files: [...files, `${RETAINED}/avatar.jpg`] });
  // the lookalike belongs to another account and is not in the list the database gives for the source
  b.state.files = [...files];
  const res = await handle(request({ ...PAIR, p_resolutions: [{ match_id: M1, keep: "source" }] }), ENV, b.fetchFn);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.merged, true);
  assert.equal(body.avatar_files_removed, 2);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/admin_preview_account_merge",
    "service:POST rpc/merge_source_stored_files",
    "service:DELETE storage/avatars",
    "service:POST rpc/merge_source_stored_files",
    "user:POST rpc/admin_merge_accounts",
  ]);
  const del = b.calls.find((c) => c.method === "DELETE")!;
  assert.deepEqual(del.body, { prefixes: files }, "exactly the listed objects and nothing else");
  assert.deepEqual(b.calls[4].body, { ...PAIR, p_resolutions: [{ match_id: M1, keep: "source" }] }, "the merge receives exactly the choices made");
  assert.deepEqual(b.state.files, []);
  assert.equal(b.state.merged, true);
});

test("without a picture: nothing is deleted and the merge still runs", async () => {
  const b = backend({ files: [] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).avatar_files_removed, 0);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/admin_preview_account_merge",
    "service:POST rpc/merge_source_stored_files",
    "user:POST rpc/admin_merge_accounts",
  ]);
});

test("ids are case-insensitive but are sent to the database in one form", async () => {
  const b = backend();
  const res = await handle(request({ ...PAIR, p_source_user_id: SOURCE.toUpperCase() }), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  assert.equal(b.calls[0].body.p_source_user_id, SOURCE);
});

// ----------------------------------------------------------------------------- cleanup that fails: no merge, ever
test("the Storage API refuses: the merge is not attempted and the answer says nothing was merged", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`], deleteStatus: 500, deleteRemoves: false });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  const body = await res.json();
  assert.equal(res.status, 502);
  assert.equal(body.error, "AVATAR_CLEANUP_FAILED");
  assert.equal(body.avatar_removed, false);
  assert.ok(!b.calls.some((c) => c.path.endsWith("admin_merge_accounts")), "the merge was never called");
  assert.equal(b.state.merged, false);
});

test("the Storage API says ok but the object is still there: not taken on trust, no merge", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`], deleteStatus: 200, deleteRemoves: false });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.ok(!b.calls.some((c) => c.path.endsWith("admin_merge_accounts")));
});

test("the Storage call never completes: no merge", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`], deleteThrows: true });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.ok(!b.calls.some((c) => c.path.endsWith("admin_merge_accounts")));
});

test("part of the pictures go and then the call fails: the answer says a picture was lost, and no merge", async () => {
  const files = [`${SOURCE}/a.jpg`, `${SOURCE}/b.jpg`];
  const b = backend({ files, deleteStatus: 500, deleteRemoves: false });
  // a delete that removes one object and then errors
  const original = b.fetchFn;
  const fetchFn = (async (input: any, init: any) => {
    const res = await original(input, init);
    if (init?.method === "DELETE") b.state.files = [`${SOURCE}/b.jpg`];
    return res;
  }) as typeof fetch;
  const res = await handle(request(PAIR), ENV, fetchFn);
  const body = await res.json();
  assert.equal(body.error, "AVATAR_CLEANUP_FAILED");
  assert.equal(body.avatar_removed, true);
  assert.ok(!b.calls.some((c) => c.path.endsWith("admin_merge_accounts")));
});

test("the list cannot be read: nothing is deleted and nothing is merged", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`], listStatus: 500 });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.deepEqual(names(b.calls), ["user:POST rpc/admin_preview_account_merge", "service:POST rpc/merge_source_stored_files"]);
  assert.deepEqual(b.state.files, [`${SOURCE}/avatar.jpg`]);
});

test("an object outside the source's folder is never deleted, whatever the database lists", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`, `${RETAINED}/avatar.jpg`] });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.ok(!b.calls.some((c) => c.method === "DELETE"), "no delete was issued at all");
  assert.deepEqual(b.state.files, [`${SOURCE}/avatar.jpg`, `${RETAINED}/avatar.jpg`]);
  assert.ok(!b.calls.some((c) => c.path.endsWith("admin_merge_accounts")));
});

// ----------------------------------------------------------------------------- the merge fails after the picture is gone
test("the database refuses after the picture is gone: the answer says so, with the database's own reason", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`], merge: pgError("MERGE_BLOCKED", "SOURCE_IS_SYSTEM_ADMIN") });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "MERGE_BLOCKED");
  assert.equal(body.detail, "SOURCE_IS_SYSTEM_ADMIN");
  assert.equal(body.avatar_removed, true);
  assert.equal(b.state.merged, false);
  assert.deepEqual(b.state.files, [], "the picture stays removed");
});

test("a refusal when there was no picture says the picture is intact", async () => {
  const b = backend({ files: [], merge: pgError("RESOLUTION_REQUIRED", M1) });
  const body = await (await handle(request(PAIR), ENV, b.fetchFn)).json();
  assert.equal(body.error, "RESOLUTION_REQUIRED");
  assert.equal(body.avatar_removed, false);
});

test("an internal check of the merge failing is reported as itself", async () => {
  const b = backend({ files: [], merge: pgError("MERGE_INVARIANT_BROKEN", "results") });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 500);
  assert.equal((await res.json()).error, "MERGE_INVARIANT_BROKEN");
});

test("the merge call never answers: the outcome is unknown, never 'nothing happened'", async () => {
  const b = backend({ files: [`${SOURCE}/avatar.jpg`], merge: "network" });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  const body = await res.json();
  assert.equal(res.status, 502);
  assert.equal(body.error, "MERGE_OUTCOME_UNKNOWN");
  assert.equal(body.avatar_removed, true);
});

test("a gateway error with no business reason could hide a commit: unknown outcome", async () => {
  const b = backend({ files: [], merge: { status: 504, body: "gateway timeout" } });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "MERGE_OUTCOME_UNKNOWN");
});

test("a request the database rejected without a reason is a plain failure", async () => {
  const b = backend({ files: [], merge: { status: 400, body: { message: "invalid input syntax for type uuid" } } });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 500);
  assert.equal((await res.json()).error, "REQUEST_FAILED");
});

test("a stale picture left by a direct call is the database's to refuse (SOURCE_FILES_REMAIN) and is reported", async () => {
  const b = backend({ files: [], merge: pgError("SOURCE_FILES_REMAIN") });
  const res = await handle(request(PAIR), ENV, b.fetchFn);
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error, "SOURCE_FILES_REMAIN");
});
