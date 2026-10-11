// Tests for functions/share/match/[id].js - run with:  node --test tests/cloudflare/
// No dependencies: Node's built-in runner, and a fake fetch in place of Supabase.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const functionFile = path.join(root, 'functions', 'share', 'match', '[id].js');
const fn = await import(pathToFileURL(functionFile).href);

const ID = '11111111-2222-4333-8444-555555555555';
const BASE = 'https://go-play-44y.pages.dev';
const ENV = { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'sb_publishable_test' };

/** A public_match_detail row, with fields the page must never use. */
const row = (over = {}) => ({
  match_id: ID,
  community_id: 'c1',
  community_name: 'Al Amerat FC',
  community_logo_url: 'https://cdn.example/logo.png',
  title: 'Friday Football',
  location: 'Sohar Pitch',
  start_at: '2026-10-16T16:00:00+00:00', // 20:00 in Muscat
  end_at: '2026-10-16T18:00:00+00:00',
  public_state: 'UPCOMING',
  starting_players: 10,
  open_slots: 4,
  has_result: null,
  team_a_score: 3,
  team_b_score: 1,
  mvp_display_name: 'Secret Player Name',
  mvp_avatar_path: 'avatars/secret.png',
  ...over,
});

function fakeFetch(body, { status = 200, calls = [] } = {}) {
  const impl = async (url, init) => {
    calls.push({ url, init });
    return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  };
  impl.calls = calls;
  return impl;
}

const request = (p, init) => new Request(`${BASE}${p}`, init);
const run = async (p, { env = ENV, id = ID, fetchImpl, init } = {}) => {
  const res = await fn.handle(request(p, init), env, id, fetchImpl);
  return { res, status: res.status, html: await res.text(), headers: res.headers };
};
const tag = (html, name) => {
  const m = html.match(new RegExp(`<meta (?:property|name)="${name}" content="([^"]*)"`));
  return m ? m[1] : null;
};

// --- OG response -------------------------------------------------------------

test('a public match is rendered with every Open Graph tag, from the public RPC only', async () => {
  const f = fakeFetch([row()]);
  const { status, html, headers } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: f });
  assert.equal(status, 200);
  assert.match(headers.get('content-type'), /^text\/html; charset=utf-8$/);
  assert.equal(headers.get('vary'), 'Accept-Language');
  assert.equal(headers.get('x-content-type-options'), 'nosniff');
  assert.equal(tag(html, 'og:type'), 'website');
  assert.equal(tag(html, 'og:title'), 'Friday Football');
  assert.equal(tag(html, 'og:url'), `${BASE}/share/match/${ID}?lang=en`);
  assert.equal(tag(html, 'og:image'), `${BASE}/og/go-play-match-invite.jpg`);
  assert.equal(tag(html, 'og:image:secure_url'), tag(html, 'og:image'));
  assert.equal(tag(html, 'og:image:width'), '1200');
  assert.equal(tag(html, 'og:image:height'), '630');
  assert.equal(tag(html, 'og:site_name'), 'Go Play');
  const description = tag(html, 'og:description');
  assert.match(description, /Oct/);
  assert.match(description, /8:00/); // 16:00 UTC read as Oman's 20:00
  assert.match(description, /Sohar Pitch/);
  assert.match(description, /Al Amerat FC/);
  assert.equal(tag(html, 'description'), description);
  assert.equal(tag(html, 'twitter:card'), 'summary_large_image');
  assert.match(html, /<title>Friday Football<\/title>/);
});

test('the image URL is absolute and https whatever scheme the request carried', async () => {
  const res = await fn.handle(new Request(`http://go-play-staging.pages.dev/share/match/${ID}`), {}, ID);
  const html = await res.text();
  assert.equal(tag(html, 'og:image'), 'https://go-play-staging.pages.dev/og/go-play-match-invite.jpg');
  assert.equal(tag(html, 'og:url'), `https://go-play-staging.pages.dev/share/match/${ID}`);
});

test('exactly one RPC call, to public_match_detail, with the publishable key and nothing else', async () => {
  const f = fakeFetch([row()]);
  await run(`/share/match/${ID}`, { fetchImpl: f });
  assert.equal(f.calls.length, 1);
  const { url, init } = f.calls[0];
  assert.equal(url, 'https://example.supabase.co/rest/v1/rpc/public_match_detail');
  assert.equal(init.method, 'POST');
  assert.deepEqual(JSON.parse(init.body), { p_match_id: ID });
  assert.equal(init.headers.apikey, 'sb_publishable_test');
  assert.equal(init.headers.Authorization, undefined, 'a non-JWT publishable key is never sent as a bearer token');
  assert.ok(init.signal, 'the call is bounded by a timeout signal');
});

test('a legacy JWT anon key is also sent as the bearer token', async () => {
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig';
  const f = fakeFetch([row()]);
  await run(`/share/match/${ID}`, { env: { ...ENV, SUPABASE_ANON_KEY: jwt }, fetchImpl: f });
  assert.equal(f.calls[0].init.headers.apikey, jwt);
  assert.equal(f.calls[0].init.headers.Authorization, `Bearer ${jwt}`);
});

test('nothing beyond title, venue, time and community name reaches the page', async () => {
  const { html } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([row()]) });
  for (const secret of ['Secret Player Name', 'avatars/secret.png', 'cdn.example/logo.png', 'c1', 'UPCOMING']) {
    assert.ok(!html.includes(secret), `leaked: ${secret}`);
  }
  assert.ok(!/3\s*[-:–]\s*1/.test(html), 'no score');
});

// --- Arabic / English ---------------------------------------------------------

test('Arabic: right-to-left page, Arabic date, Latin digits, ar_AR locale', async () => {
  const { html } = await run(`/share/match/${ID}?lang=ar`, { fetchImpl: fakeFetch([row()]) });
  assert.match(html, /<html lang="ar" dir="rtl">/);
  assert.equal(tag(html, 'og:locale'), 'ar_AR');
  const description = tag(html, 'og:description');
  assert.match(description, /أكتوبر/);
  assert.match(description, /16/);
  assert.match(description, /8:00/);
  assert.ok(!/[٠-٩]/.test(description), 'digits stay Latin, as in the app');
  assert.match(html, /فتح المباراة في Go Play/);
});

test('English: left-to-right page and en_US locale', async () => {
  const { html } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([row()]) });
  assert.match(html, /<html lang="en" dir="ltr">/);
  assert.equal(tag(html, 'og:locale'), 'en_US');
  assert.match(html, /Open the match in Go Play/);
});

test('language: the link decides, then Accept-Language, then the app default (Arabic)', async () => {
  const f = () => fakeFetch([row()]);
  let r = await run(`/share/match/${ID}?lang=en`, { fetchImpl: f(), init: { headers: { 'accept-language': 'ar' } } });
  assert.match(r.html, /lang="en"/);
  r = await run(`/share/match/${ID}`, { fetchImpl: f(), init: { headers: { 'accept-language': 'en-GB,en;q=0.9' } } });
  assert.match(r.html, /lang="en"/);
  assert.equal(tag(r.html, 'og:url'), `${BASE}/share/match/${ID}`, 'no lang in og:url unless the link carried one');
  r = await run(`/share/match/${ID}`, { fetchImpl: f() });
  assert.match(r.html, /lang="ar"/);
  r = await run(`/share/match/${ID}?lang=fr`, { fetchImpl: f(), init: { headers: { 'accept-language': 'fr' } } });
  assert.match(r.html, /lang="ar"/);
  assert.equal(tag(r.html, 'og:url'), `${BASE}/share/match/${ID}`, 'an unsupported lang is not echoed');
});

test('the generic preview is available in both languages', async () => {
  const en = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([]) });
  const ar = await run(`/share/match/${ID}?lang=ar`, { fetchImpl: fakeFetch([]) });
  assert.equal(tag(en.html, 'og:title'), 'Match invitation on Go Play');
  assert.equal(tag(ar.html, 'og:title'), 'دعوة إلى مباراة على Go Play');
});

// --- escaping and hygiene -----------------------------------------------------

test('dynamic text is HTML-escaped everywhere and cannot add markup or script', async () => {
  const evil = row({
    title: `<img src=x onerror=alert(1)>"'&`,
    location: `</script><script>alert(2)</script>`,
    community_name: `"><svg onload=alert(3)>`,
  });
  const { html } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([evil]) });
  assert.ok(!html.includes('<img src=x'));
  assert.ok(!html.includes('<svg'));
  assert.ok(!html.includes('alert(2)</script>'));
  assert.equal((html.match(/<script>/g) ?? []).length, 1, 'only the redirect script exists');
  assert.equal(tag(html, 'og:title'), '&lt;img src=x onerror=alert(1)&gt;&quot;&#39;&amp;');
  // every attribute value stayed inside its quotes
  assert.ok(!/content="[^"]*"[^>]*onerror/i.test(html));
});

test('control and bidi-override characters are removed and long text is bounded', async () => {
  const long = 'x'.repeat(500);
  const { html } = await run(`/share/match/${ID}?lang=en`, {
    fetchImpl: fakeFetch([row({ title: `Line1\nLine2\u202eevil${long}`, location: long, community_name: long })]),
  });
  const title = tag(html, 'og:title');
  assert.ok(!/[\n\r\u202e]/.test(title));
  assert.ok(Array.from(title).length <= 80);
  assert.ok(Array.from(tag(html, 'og:description')).length <= 200);
});

test('a match with no title is named by its venue, which is not then repeated', async () => {
  const { html } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([row({ title: '  ', location: 'Sohar Pitch' })]) });
  assert.equal(tag(html, 'og:title'), 'Sohar Pitch');
  assert.ok(!/Sohar Pitch •|• Sohar Pitch/.test(tag(html, 'og:description')));
});

// --- unavailable / failure: a safe generic preview -----------------------------

test('a match that is not public gets the generic preview, with no data and a normal redirect', async () => {
  const { status, html, headers } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([]) });
  assert.equal(status, 200);
  assert.equal(tag(html, 'og:title'), 'Match invitation on Go Play');
  assert.ok(!html.includes('Sohar'));
  assert.equal(tag(html, 'og:image'), `${BASE}/og/go-play-match-invite.jpg`);
  assert.match(html, new RegExp(`location\\.replace\\("/#/match/${ID}"\\)`));
  assert.equal(headers.get('cache-control'), 'public, max-age=60');
});

test('upstream failures never become an error page and are never cached', async () => {
  const cases = {
    'http 500': fakeFetch({ message: 'boom' }, { status: 500 }),
    'not an array': fakeFetch({ message: 'weird' }),
    'network error': async () => { throw new TypeError('fetch failed'); },
  };
  for (const [name, impl] of Object.entries(cases)) {
    const { status, html, headers } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: impl });
    assert.equal(status, 200, name);
    assert.equal(tag(html, 'og:title'), 'Match invitation on Go Play', name);
    assert.equal(headers.get('cache-control'), 'no-store', name);
  }
});

test('a slow Supabase is cut off by the timeout and answered generically', { timeout: 15000 }, async () => {
  const hang = (url, { signal }) => new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason)));
  const started = Date.now();
  const { status, html } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: hang });
  assert.equal(status, 200);
  assert.equal(tag(html, 'og:title'), 'Match invitation on Go Play');
  assert.ok(Date.now() - started < 8000);
});

test('without the runtime bindings the function answers generically and makes no request', async () => {
  for (const env of [{}, { SUPABASE_URL: ENV.SUPABASE_URL }, { SUPABASE_ANON_KEY: 'k' }, { ...ENV, SUPABASE_URL: 'http://insecure.example' }]) {
    const f = fakeFetch([row()]);
    const { status, html, headers } = await run(`/share/match/${ID}?lang=en`, { env, fetchImpl: f });
    assert.equal(status, 200);
    assert.equal(f.calls.length, 0);
    assert.equal(tag(html, 'og:title'), 'Match invitation on Go Play');
    assert.equal(headers.get('cache-control'), 'no-store');
  }
});

// --- identifiers ---------------------------------------------------------------

test('invalid identifiers are rejected before any lookup', async () => {
  const bad = ['not-a-uuid', '', '../../etc/passwd', `${ID}x`, ID.slice(1), '%3Cscript%3E', `${ID}/extra`, 'g'.repeat(36), `${ID}'; drop table matches;--`, undefined, null, 42];
  for (const id of bad) {
    const f = fakeFetch([row()]);
    // `handle` directly: the `run` helper would swap an undefined id for a valid one.
    const res = await fn.handle(request('/share/match/x'), ENV, id, f);
    const html = await res.text();
    assert.equal(res.status, 404, String(id));
    assert.equal(f.calls.length, 0, `looked up ${String(id)}`);
    assert.ok(!html.includes('#/match/'), 'no match route for a non-match');
    assert.equal(tag(html, 'og:title'), 'دعوة إلى مباراة على Go Play');
  }
});

test('an upper-case UUID is accepted and normalised to lower case', async () => {
  const f = fakeFetch([row()]);
  const { status, html } = await run('/share/match/x', { id: ID.toUpperCase(), fetchImpl: f });
  assert.equal(status, 200);
  assert.deepEqual(JSON.parse(f.calls[0].init.body), { p_match_id: ID });
  assert.equal(tag(html, 'og:url'), `${BASE}/share/match/${ID}`);
});

test('isUuid accepts only canonical UUIDs', () => {
  assert.equal(fn.isUuid(ID), true);
  for (const v of ['', 'abc', ID + '0', ' ' + ID, ID.replace(/-/g, '')]) assert.equal(fn.isUuid(v), false, v);
});

// --- navigation ----------------------------------------------------------------

test('people are sent on to the app route client-side, with a visible fallback link and no meta refresh', async () => {
  const { html } = await run(`/share/match/${ID}?lang=en`, { fetchImpl: fakeFetch([row()]) });
  assert.match(html, new RegExp(`<script>location\\.replace\\("/#/match/${ID}"\\);</script>`));
  assert.match(html, new RegExp(`<a id="open" href="/#/match/${ID}">Open the match in Go Play</a>`));
  assert.ok(!/http-equiv="refresh"/i.test(html));
  // the OG tags are plain HTML: present without running any script
  assert.equal(tag(html.replace(/<script>[\s\S]*?<\/script>/g, ''), 'og:title'), 'Friday Football');
});

// --- methods and the Pages entry point -----------------------------------------

test('HEAD answers like GET without a body; other methods are refused', async () => {
  const head = await fn.handle(new Request(`${BASE}/share/match/${ID}`, { method: 'HEAD' }), ENV, ID, fakeFetch([row()]));
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
  const post = await fn.handle(new Request(`${BASE}/share/match/${ID}`, { method: 'POST' }), ENV, ID, fakeFetch([row()]));
  assert.equal(post.status, 405);
  assert.equal(post.headers.get('allow'), 'GET, HEAD');
});

test('onRequest is the Pages entry point and reads the id from the route params', async () => {
  const ok = await fn.onRequest({ request: request(`/share/match/${ID}`), env: {}, params: { id: ID } });
  assert.equal(ok.status, 200);
  const bad = await fn.onRequest({ request: request('/share/match/zzz'), env: {}, params: { id: 'zzz' } });
  assert.equal(bad.status, 404);
  const none = await fn.onRequest({ request: request('/share/match/'), env: {}, params: {} });
  assert.equal(none.status, 404);
});

// --- source and asset contracts --------------------------------------------------

test('the source reads only the public RPC and never mentions a privileged key', () => {
  const source = readFileSync(functionFile, 'utf8');
  assert.ok(!/service_role|SERVICE_ROLE|SUPABASE_SERVICE/.test(source));
  const rpcs = [...source.matchAll(/rest\/v1\/rpc\/([a-z_]+)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(rpcs)], ['public_match_detail']);
  assert.ok(!/rest\/v1\/(?!rpc\/)/.test(source), 'no direct table reads');
  assert.ok(!/process\.env|console\.(log|error)/.test(source), 'no ambient config, nothing logged');
});

test('the thumbnail ships with the web build: a JPEG, 1200x630, small enough for chat previews', () => {
  const file = path.join(root, 'app', 'web', 'og', 'go-play-match-invite.jpg');
  const bytes = readFileSync(file);
  assert.deepEqual([...bytes.subarray(0, 3)], [0xff, 0xd8, 0xff], 'JPEG signature');
  assert.ok(statSync(file).size < 300 * 1024, 'under 300 KB');
  // read the frame header: SOF0/SOF2 carry height then width
  let i = 2;
  let size = null;
  while (i < bytes.length) {
    if (bytes[i] !== 0xff) { i += 1; continue; }
    const marker = bytes[i + 1];
    const length = bytes.readUInt16BE(i + 2);
    if (marker === 0xc0 || marker === 0xc2) {
      size = { height: bytes.readUInt16BE(i + 5), width: bytes.readUInt16BE(i + 7) };
      break;
    }
    i += 2 + length;
  }
  assert.deepEqual(size, { width: 1200, height: 630 });
});
