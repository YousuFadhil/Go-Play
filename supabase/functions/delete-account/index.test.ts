// Behaviour of the deletion function against a fake backend, for BOTH routes: who may reach what, in
// which order, whose picture is removed, and what each failure leaves behind. Run with `node --test`
// (Node 22.18+ strips the types itself); no dependency, and nothing here touches a real project.
//
//   node --test supabase/functions/delete-account/index.test.ts
import assert from "node:assert/strict";
import test from "node:test";
import { handle } from "./index.ts";

const ME = "00000000-0000-4000-8000-000000000003";
const VICTIM = "00000000-0000-4000-8000-0000000000ab";

const ENV = { url: "https://p.test", anonKey: "ANON", serviceKey: "SERVICE" };
const JWT = "user-jwt";

interface Call {
  method: string;
  path: string;
  caller: "user" | "service" | "anon" | "none";
  body: any;
}

function previewDoc(over: { blockers?: string[]; user_id?: string | null } = {}) {
  const blockers = over.blockers ?? [];
  const doc: any = {
    version: 2,
    has_blockers: blockers.length > 0,
    findings: [
      ...blockers.map((code) => ({ code, severity: "BLOCKER", category: "X", count: 1 })),
      { code: "HISTORY_KEPT", severity: "CONSTRAINT", category: "HISTORY", count: 4 },
    ],
  };
  if (over.user_id !== null) doc.user_id = over.user_id ?? ME;
  return doc;
}

interface Options {
  previewStatus?: number;
  preview?: any;
  del?: { status: number; body: any } | "network";
  files?: string[];
  deleteStatus?: number;
  deleteRemoves?: boolean;
  deleteThrows?: boolean;
  listStatus?: number;
}

/// A backend that records every call and says who made it.
function backend(options: Options = {}) {
  const calls: Call[] = [];
  const state = { files: [...(options.files ?? [])], deleted: false };
  const who = (headers: Headers): Call["caller"] => {
    const bearer = (headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (bearer === JWT) return "user";
    if (bearer === ENV.serviceKey) return "service";
    if (bearer === ENV.anonKey) return "anon";
    return "none";
  };
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  const isPreview = (p: string) =>
    p.endsWith("/rpc/admin_preview_account_deletion") || p.endsWith("/rpc/preview_my_account_deletion");
  const isDelete = (p: string) =>
    p.endsWith("/rpc/admin_delete_account") || p.endsWith("/rpc/delete_my_account");

  const fetchFn = (async (input: any, init: any) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    const body = init?.body ? JSON.parse(init.body) : null;
    const call: Call = { method: init?.method ?? "GET", path: url.pathname, caller: who(headers), body };
    calls.push(call);

    if (isPreview(url.pathname)) {
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
    if (isDelete(url.pathname)) {
      if (call.caller !== "user") return json(401, { message: "JWT expired" });
      if (options.del === "network") throw new TypeError("connection reset");
      const del = options.del ?? { status: 200, body: { deleted: true, user_id: ME, mode: "x" } };
      if (del.status < 300) state.deleted = true;
      return json(del.status, del.body);
    }
    throw new Error(`unexpected call ${call.method} ${url.pathname}`);
  }) as typeof fetch;

  return { fetchFn, calls, state };
}

function request(body: unknown, { jwt = JWT, method = "POST" }: { jwt?: string | null; method?: string } = {}) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (jwt !== null) headers["Authorization"] = `Bearer ${jwt}`;
  return new Request("https://p.test/functions/v1/delete-account", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const SELF = {};
const ADMIN = { p_user_id: VICTIM };
const names = (calls: Call[]) =>
  calls.map((c) => `${c.caller}:${c.method} ${c.path.replace("/rest/v1/rpc/", "rpc/").replace("/storage/v1/object/", "storage/")}`);
const pgError = (message: string, details: string | null = null) => ({ status: 400, body: { code: "P0001", details, hint: null, message } });

// ----------------------------------------------------------------------------- authorization
test("no token: refused before anything is called", async () => {
  const b = backend();
  const res = await handle(request(SELF, { jwt: null }), ENV, b.fetchFn);
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error, "NOT_AUTHENTICATED");
  assert.deepEqual(b.calls, []);
});

test("a signed-in user who is not a System Admin cannot name somebody else: refused, no service-role call", async () => {
  const b = backend({ previewStatus: 400, preview: { code: "P0001", message: "NOT_AUTHORIZED", details: null, hint: null }, files: [`${VICTIM}/avatar.jpg`] });
  const res = await handle(request(ADMIN), ENV, b.fetchFn);
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, "NOT_AUTHORIZED");
  assert.deepEqual(names(b.calls), ["user:POST rpc/admin_preview_account_deletion"]);
  assert.deepEqual(b.state.files, [`${VICTIM}/avatar.jpg`], "the victim's picture is untouched");
});

test("an expired or forged token is refused as unauthenticated, on both routes", async () => {
  for (const body of [SELF, ADMIN]) {
    const b = backend();
    const res = await handle(request(body, { jwt: "forged" }), ENV, b.fetchFn);
    assert.equal(res.status, 401);
    assert.equal((await res.json()).error, "NOT_AUTHENTICATED");
    assert.equal(b.calls.length, 1);
    assert.equal(b.calls[0].caller, "none");
  }
});

test("the service role key reaches only storage and the file list, never a preview or a deletion", async () => {
  for (const body of [SELF, ADMIN]) {
    const b = backend({ files: [`${body === ADMIN ? VICTIM : ME}/avatar.jpg`], preview: previewDoc({ user_id: ME }) });
    const res = await handle(request(body), ENV, b.fetchFn);
    assert.equal(res.status, 200);
    for (const c of b.calls) {
      const privileged = c.path.includes("merge_source_stored_files") || c.path.startsWith("/storage/");
      assert.equal(c.caller, privileged ? "service" : "user", `${c.path} ran as ${c.caller}`);
    }
  }
});

// ----------------------------------------------------------------------------- bad requests
for (const [name, body] of [
  ["not an object", []],
  ["a malformed id", { p_user_id: "nope" }],
  ["an id that is not a string", { p_user_id: 7 }],
] as const) {
  test(`bad request (${name}): refused before anything is called`, async () => {
    const b = backend();
    const res = await handle(request(body), ENV, b.fetchFn);
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, "BAD_REQUEST");
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
  const refused = await handle(request(SELF, { jwt: null }), ENV, b.fetchFn);
  assert.equal(refused.headers.get("Access-Control-Allow-Origin"), "*");
  assert.equal((await handle(request(null, { method: "GET" }), ENV, b.fetchFn)).status, 405);
  assert.deepEqual(b.calls, []);
});

// ----------------------------------------------------------------------------- preflight: nothing is deleted
test("a blocker stops everything before the picture is touched, on both routes", async () => {
  for (const [body, who] of [[SELF, ME], [ADMIN, VICTIM]] as const) {
    const b = backend({ preview: previewDoc({ blockers: ["OWNS_COMMUNITIES"] }), files: [`${who}/avatar.jpg`] });
    const res = await handle(request(body), ENV, b.fetchFn);
    const out = await res.json();
    assert.equal(res.status, 409);
    assert.equal(out.error, "DELETE_BLOCKED");
    assert.equal(out.detail, "OWNS_COMMUNITIES");
    assert.equal(b.calls.length, 1);
    assert.deepEqual(b.state.files, [`${who}/avatar.jpg`]);
  }
});

test("a suspended account is stopped by the preflight, before its picture is touched", async () => {
  const b = backend({ preview: previewDoc({ blockers: ["ACCOUNT_SUSPENDED"] }), files: [`${ME}/avatar.jpg`] });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal((await res.json()).detail, "ACCOUNT_SUSPENDED");
  assert.deepEqual(b.state.files, [`${ME}/avatar.jpg`]);
});

test("a preview that does not say has_blockers: false is treated as blocked", async () => {
  const doc: any = previewDoc();
  delete doc.has_blockers;
  const b = backend({ preview: doc, files: [`${ME}/avatar.jpg`] });
  assert.equal((await (await handle(request(SELF), ENV, b.fetchFn)).json()).error, "DELETE_BLOCKED");
  assert.equal(b.calls.length, 1);
});

test("an unreadable preview stops it before the picture is touched", async () => {
  const b = backend({ preview: "nope", files: [`${ME}/avatar.jpg`] });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal(res.status, 502);
  assert.equal((await res.json()).error, "PREFLIGHT_FAILED");
  assert.deepEqual(b.state.files, [`${ME}/avatar.jpg`]);
});

test("self route: a preview without the caller's id is not enough to remove a picture", async () => {
  const b = backend({ preview: previewDoc({ user_id: null }), files: [`${ME}/avatar.jpg`] });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "PREFLIGHT_FAILED");
  assert.equal(b.calls.length, 1);
  assert.deepEqual(b.state.files, [`${ME}/avatar.jpg`]);
});

// ----------------------------------------------------------------------------- the deletion, with and without a picture
test("self route: preview, list, delete exactly the caller's objects, list again, then delete the account", async () => {
  const files = [`${ME}/avatar.jpg`, `${ME}/old/avatar.png`];
  const b = backend({ files, preview: previewDoc({ user_id: ME }) });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  const out = await res.json();
  assert.equal(res.status, 200);
  assert.equal(out.deleted, true);
  assert.equal(out.avatar_files_removed, 2);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/preview_my_account_deletion",
    "service:POST rpc/merge_source_stored_files",
    "service:DELETE storage/avatars",
    "service:POST rpc/merge_source_stored_files",
    "user:POST rpc/delete_my_account",
  ]);
  assert.deepEqual(b.calls[1].body, { p_user_id: ME }, "the picture list is for the id the DATABASE returned");
  assert.deepEqual(b.calls.find((c) => c.method === "DELETE")!.body, { prefixes: files });
  assert.deepEqual(b.calls[4].body, {}, "the self route sends no account to delete: the database acts on the caller");
  assert.deepEqual(b.state.files, []);
  assert.equal(b.state.deleted, true);
});

test("admin route: the administrator's target is the account whose picture goes, and the target is what is deleted", async () => {
  const files = [`${VICTIM}/avatar.jpg`];
  const b = backend({ files, preview: previewDoc({ user_id: undefined }) });
  const res = await handle(request({ p_user_id: VICTIM.toUpperCase() }), ENV, b.fetchFn);
  assert.equal(res.status, 200);
  assert.deepEqual(names(b.calls), [
    "user:POST rpc/admin_preview_account_deletion",
    "service:POST rpc/merge_source_stored_files",
    "service:DELETE storage/avatars",
    "service:POST rpc/merge_source_stored_files",
    "user:POST rpc/admin_delete_account",
  ]);
  assert.deepEqual(b.calls[0].body, { p_user_id: VICTIM }, "ids are sent in one form");
  assert.deepEqual(b.calls[1].body, { p_user_id: VICTIM });
  assert.deepEqual(b.calls[4].body, { p_user_id: VICTIM });
});

test("without a picture: nothing is deleted from Storage and the account is deleted", async () => {
  for (const body of [SELF, ADMIN]) {
    const b = backend({ files: [] });
    const res = await handle(request(body), ENV, b.fetchFn);
    assert.equal(res.status, 200);
    assert.equal((await res.json()).avatar_files_removed, 0);
    assert.ok(!b.calls.some((c) => c.method === "DELETE"));
    assert.equal(b.calls.length, 3);
  }
});

// ----------------------------------------------------------------------------- cleanup that fails: no deletion, ever
test("the Storage API refuses: the deletion is not attempted and the answer says so", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`], deleteStatus: 500, deleteRemoves: false });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  const out = await res.json();
  assert.equal(res.status, 502);
  assert.equal(out.error, "AVATAR_CLEANUP_FAILED");
  assert.equal(out.avatar_removed, false);
  assert.ok(!b.calls.some((c) => c.path.endsWith("delete_my_account")));
  assert.equal(b.state.deleted, false);
});

test("the Storage API says ok but the object is still there: not taken on trust, no deletion", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`], deleteStatus: 200, deleteRemoves: false });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.ok(!b.calls.some((c) => c.path.endsWith("delete_my_account")));
});

test("the Storage call never completes: no deletion", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`], deleteThrows: true });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.ok(!b.calls.some((c) => c.path.endsWith("delete_my_account")));
});

test("the list cannot be read: nothing is deleted from Storage and the account is not deleted", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`], listStatus: 500 });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.deepEqual(names(b.calls), ["user:POST rpc/preview_my_account_deletion", "service:POST rpc/merge_source_stored_files"]);
  assert.deepEqual(b.state.files, [`${ME}/avatar.jpg`]);
});

test("an object outside the account's folder is never deleted, whatever the database lists", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`, `${VICTIM}/avatar.jpg`] });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal((await res.json()).error, "AVATAR_CLEANUP_FAILED");
  assert.ok(!b.calls.some((c) => c.method === "DELETE"), "no delete was issued at all");
  assert.deepEqual(b.state.files, [`${ME}/avatar.jpg`, `${VICTIM}/avatar.jpg`]);
  assert.ok(!b.calls.some((c) => c.path.endsWith("delete_my_account")));
});

// ----------------------------------------------------------------------------- the deletion fails after the picture is gone
test("the database refuses after the picture is gone: the answer says so, with its own reason", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`], del: pgError("DELETE_BLOCKED", "OWNS_COMMUNITIES") });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  const out = await res.json();
  assert.equal(res.status, 409);
  assert.equal(out.error, "DELETE_BLOCKED");
  assert.equal(out.detail, "OWNS_COMMUNITIES");
  assert.equal(out.avatar_removed, true);
  assert.equal(b.state.deleted, false);
  assert.deepEqual(b.state.files, [], "the picture stays removed");
});

test("a refusal when there was no picture says the picture is intact", async () => {
  const b = backend({ files: [], del: pgError("ACCOUNT_SUSPENDED") });
  const out = await (await handle(request(SELF), ENV, b.fetchFn)).json();
  assert.equal(out.error, "ACCOUNT_SUSPENDED");
  assert.equal(out.avatar_removed, false);
});

test("an internal check of the engine failing is reported as itself", async () => {
  const b = backend({ files: [], del: pgError("DELETE_EVIDENCE_CHANGED", "goal_rows") });
  const res = await handle(request(ADMIN), ENV, b.fetchFn);
  assert.equal(res.status, 500);
  assert.equal((await res.json()).error, "DELETE_EVIDENCE_CHANGED");
});

test("the deletion call never answers: the outcome is unknown, never 'nothing happened'", async () => {
  const b = backend({ files: [`${ME}/avatar.jpg`], del: "network" });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  const out = await res.json();
  assert.equal(res.status, 502);
  assert.equal(out.error, "DELETE_OUTCOME_UNKNOWN");
  assert.equal(out.avatar_removed, true);
});

test("a gateway error with no business reason could hide a commit: unknown outcome", async () => {
  const b = backend({ files: [], del: { status: 504, body: "gateway timeout" } });
  assert.equal((await (await handle(request(SELF), ENV, b.fetchFn)).json()).error, "DELETE_OUTCOME_UNKNOWN");
});

test("a request the database rejected without a reason is a plain failure", async () => {
  const b = backend({ files: [], del: { status: 400, body: { message: "invalid input syntax for type uuid" } } });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal(res.status, 500);
  assert.equal((await res.json()).error, "REQUEST_FAILED");
});

test("a picture left by a direct call is the database's to refuse (SOURCE_FILES_REMAIN) and is reported", async () => {
  const b = backend({ files: [], del: pgError("SOURCE_FILES_REMAIN") });
  const res = await handle(request(SELF), ENV, b.fetchFn);
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error, "SOURCE_FILES_REMAIN");
});
