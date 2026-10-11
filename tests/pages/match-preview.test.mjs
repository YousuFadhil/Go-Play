import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Load the Pages ES module without adding an npm package to the Flutter repo.
const source = await readFile(new URL('../../functions/share/match/[id].js', import.meta.url), 'utf8');
const { onRequest } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const id = '11111111-2222-4333-8444-555555555555';
const key = `e30.${Buffer.from(JSON.stringify({ role: 'anon' })).toString('base64url')}.test`;
const env = { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: key };
const match = { match_id: id, title: 'Friday Football', location: 'Sohar Pitch', start_at: '2026-10-16T16:00:00Z', end_at: '2026-10-16T18:00:00Z', mvp_display_name: 'DO_NOT_PUBLISH', join_code: 'PRIVATE_CODE' };
function context(language = 'en', overrides = {}) {
  return { request: new Request(`https://go-play.example/share/match/${id}?lang=${language}`), params: { id }, env, ...overrides };
}
function rpc(t, rows = [match], status = 200) {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (...args) => {
    calls.push(args);
    return new Response(JSON.stringify(rows), { status });
  });
  return calls;
}
for (const language of ['en', 'ar']) {
  test(`crawler receives metadata without running JavaScript (${language})`, async t => {
    const calls = rpc(t);
    const response = await onRequest(context(language));
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'text/html; charset=utf-8');
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], 'https://example.supabase.co/rest/v1/rpc/public_match_detail');
    assert.deepEqual(JSON.parse(calls[0][1].body), { p_match_id: id });
    assert.equal(calls[0][1].headers.apikey, key);
    assert.equal(calls[0][1].headers.Authorization, `Bearer ${key}`);
    assert.ok(calls[0][1].signal instanceof AbortSignal);
    for (const property of ['title', 'description', 'image', 'url', 'type']) {
      assert.ok(html.includes(`property="og:${property}"`));
    }
    assert.ok(html.includes('Friday Football — Go Play'));
    assert.ok(html.includes('https://go-play.example/share/go-play-thumbnail.png'));
    assert.ok(html.includes(`https://go-play.example/share/match/${id}?lang=${language}`));
    assert.ok(html.includes(`https://go-play.example/#/match/${id}`));
    assert.ok(html.includes("location.replace(document.getElementById('open-match').href)"));
    assert.ok(html.includes(language === 'ar' ? 'الموقع: Sohar Pitch' : 'Location: Sohar Pitch'));
    assert.ok(html.includes(language === 'ar' ? '٨:٠٠' : '8:00'));
    assert.ok(!html.includes('DO_NOT_PUBLISH'));
    assert.ok(!html.includes('PRIVATE_CODE'));
    assert.ok(!html.includes(key));
    assert.equal(response.headers.get('location'), null);
  });
}
test('dynamic content is HTML escaped and never inserted into JavaScript', async t => {
  rpc(t, [{ ...match, title: '</script><script>alert("x")</script>', location: 'A & B\'s "Pitch"' }]);
  const html = await (await onRequest(context())).text();
  assert.ok(html.includes('&lt;/script&gt;&lt;script&gt;'));
  assert.ok(html.includes('A &amp; B&#39;s &quot;Pitch&quot;'));
  assert.ok(!html.includes('<script>alert'));
});
test('missing public match uses generic metadata, retaining the ordinary app route', async t => {
  rpc(t, []);
  const response = await onRequest(context());
  const html = await response.text();
  assert.equal(response.status, 404);
  assert.ok(html.includes('Go Play — Match invitation'));
  assert.ok(!html.includes('Sohar Pitch'));
  assert.ok(html.includes(`/#/match/${id}`));
});
test('invalid identifiers never query Supabase or enter the redirect', async t => {
  const calls = rpc(t);
  for (const value of ['not-a-uuid', '<script>', `${id}/extra`, [id], undefined]) {
    const response = await onRequest(context('en', { params: { id: value } }));
    assert.equal(response.status, 400);
    assert.ok(!(await response.text()).includes('/#/match/'));
  }
  assert.equal(calls.length, 0);
});
test('uppercase UUIDs normalize to the existing route', async t => {
  const hexId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  rpc(t, [{ ...match, match_id: hexId }]);
  const html = await (await onRequest(context('en', { params: { id: hexId.toUpperCase() } }))).text();
  assert.ok(html.includes(`/#/match/${hexId}`));
});
test('absent configuration, privileged keys and malformed base URLs fail closed', async t => {
  const calls = rpc(t);
  const serviceRole = `e30.${Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url')}.test`;
  for (const badEnv of [{}, { ...env, SUPABASE_ANON_KEY: serviceRole }, { ...env, SUPABASE_ANON_KEY: 'sb_secret_bad' }, { ...env, SUPABASE_URL: 'https://example.supabase.co/rest/v1/' }, { ...env, SUPABASE_URL: 'http://example.test/' }]) {
    const response = await onRequest(context('en', { env: badEnv }));
    assert.equal(response.status, 503);
    assert.ok(!(await response.text()).includes('Friday Football'));
  }
  assert.equal(calls.length, 0);
});
test('publishable keys use apikey without being sent as a JWT', async t => {
  const calls = rpc(t);
  const response = await onRequest(context('en', { env: { ...env, SUPABASE_ANON_KEY: 'sb_publishable_test' } }));
  assert.equal(response.status, 200);
  assert.equal(calls[0][1].headers.apikey, 'sb_publishable_test');
  assert.equal(calls[0][1].headers.Authorization, undefined);
});
test('RPC failures and malformed results disclose only generic metadata', async t => {
  const cases = [() => { throw new Error('PRIVATE_API_ERROR'); }, () => new Response('PRIVATE_API_ERROR', { status: 403 }), () => new Response('not-json'), () => new Response('{}')];
  for (const stub of cases) {
    t.mock.method(globalThis, 'fetch', stub);
    const response = await onRequest(context());
    const html = await response.text();
    assert.equal(response.status, 503);
    assert.ok(!html.includes('PRIVATE_API_ERROR'));
    assert.ok(!html.includes('Friday Football'));
  }
});
test('unknown languages default to Arabic and HEAD has no body', async t => {
  rpc(t);
  const html = await (await onRequest(context('unknown'))).text();
  assert.ok(html.includes('lang="ar" dir="rtl"'));
  const request = new Request(context().request.url, { method: 'HEAD' });
  const response = await onRequest(context('en', { request }));
  assert.equal(response.status, 200);
  assert.equal(await response.text(), '');
});
test('unsupported methods do not call the read API', async t => {
  const calls = rpc(t);
  const request = new Request(context().request.url, { method: 'POST' });
  const response = await onRequest(context('en', { request }));
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('allow'), 'GET, HEAD');
  assert.equal(calls.length, 0);
});
test('thumbnail is a real 1200x630 PNG and function routing excludes normal app assets', async () => {
  const image = await readFile(new URL('../../app/web/share/go-play-thumbnail.png', import.meta.url));
  assert.deepEqual([...image.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(image.readUInt32BE(16), 1200);
  assert.equal(image.readUInt32BE(20), 630);
  const routes = JSON.parse(await readFile(new URL('../../app/web/_routes.json', import.meta.url)));
  assert.deepEqual(routes, { version: 1, include: ['/share/match/*'], exclude: [] });
});
