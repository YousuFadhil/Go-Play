import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runChecks, renderCatalog, CATALOG_PATH, ARCHITECTURE_DOC } from '../../tool/check-docs.mjs';

/** A tiny repository in which every check passes; tests then break one thing. */
function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'check-docs-'));
  const tracked = new Set();
  const w = (rel, text) => {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), text);
    tracked.add(rel);
  };
  w('supabase/migrations/0001_base.sql', 'create table public.a (id int);');
  w('supabase/migrations/0095_later.sql', 'create function public.f() returns int language sql as $$ select 1 $$;');
  w('supabase/functions/fn1/README.md', '# `fn1`\n\nDoes one thing. Then another.\n');
  w(ARCHITECTURE_DOC, '# Architecture\n\nEdge Function `fn1`.\n');
  w('CHANGELOG.md', '# Changes\n\n- 0095 adds f.\n');
  w('CLAUDE.md', 'See `Docs/README.md`.\n');
  w('Docs/README.md', 'Index. See `01-PRD.md`.\n');
  w('Docs/01-PRD.md', '# PRD\n');
  w('SETUP.md', '# Setup\n');
  w('Docs/12-Testing.md', '# Testing\n');
  w(CATALOG_PATH, '');
  fs.writeFileSync(path.join(root, CATALOG_PATH), renderCatalog(root));
  return { root, tracked, w, check: () => runChecks({ root, tracked: [...tracked] }) };
}
const checks = (fails) => fails.map((f) => f.check);

test('a repository whose docs are in step passes', () => {
  assert.deepEqual(fixture().check(), []);
});

test('a migration not named in the CHANGELOG fails', () => {
  const f = fixture();
  f.w('supabase/migrations/0096_new.sql', 'create table public.b (id int);');
  fs.writeFileSync(path.join(f.root, CATALOG_PATH), renderCatalog(f.root));
  const fails = f.check();
  assert.deepEqual(checks(fails), ['changelog']);
  assert.match(fails[0].message, /0096/);
});

test('a stale catalog fails until it is regenerated', () => {
  const f = fixture();
  f.w('supabase/migrations/0002_more.sql', 'create table public.c (id int);');
  assert.deepEqual(checks(f.check()), ['catalog']);
  fs.writeFileSync(path.join(f.root, CATALOG_PATH), renderCatalog(f.root));
  assert.deepEqual(f.check(), []);
});

test('an Edge Function without a README, or not in the architecture doc, fails', () => {
  const f = fixture();
  f.w('supabase/functions/fn2/index.ts', 'export {};');
  fs.writeFileSync(path.join(f.root, CATALOG_PATH), renderCatalog(f.root));
  const messages = f.check().map((x) => x.message).join('\n');
  assert.match(messages, /fn2 has no README/);
  assert.match(messages, /"fn2" is not named/);
});

test('a path that no longer exists (or only differs in case) fails; bare names resolve under Docs/', () => {
  const f = fixture();
  f.w('CLAUDE.md', 'See `docs/ai/AI_PROTOCOL.md` and `Docs/README.md` and `01-PRD.md`.\n');
  f.w('Docs/AI_PROTOCOL.md', '# Protocol\n');
  const fails = f.check();
  assert.deepEqual(checks(fails), ['references']);
  assert.match(fails[0].message, /docs\/ai\/AI_PROTOCOL\.md/);
});

test('placeholders and URLs in backticks are not treated as paths', () => {
  const f = fixture();
  f.w('SETUP.md', '# Setup\n\n`app_xx.arb` `supabase/migrations/NNNN_name.sql` `https://x.test/a.md` `<name>.md`\n');
  assert.deepEqual(f.check(), []);
});

test('numbers that go stale in prose fail, in English and in Arabic', () => {
  const f = fixture();
  f.w('Docs/README.md', 'Index. Schema through migration `0035`. See `01-PRD.md`.\n');
  f.w('SETUP.md', '# Setup (`v0.6.0-mvp`)\n\nاختبارات الوحدة فقط (54 ناجح، 4 متجاوَز).\n');
  f.w('Docs/12-Testing.md', '**Last executed: 172 passed, 7 skipped**\n');
  const messages = f.check().filter((x) => x.check === 'volatile').map((x) => x.message).join('\n');
  assert.match(messages, /Docs\/README\.md:1 .*migration number/);
  assert.match(messages, /SETUP\.md:1 .*version stamp in the title/);
  assert.match(messages, /SETUP\.md:3 .*test count/);
  assert.match(messages, /Docs\/12-Testing\.md:1 .*test count/);
  assert.match(messages, /Docs\/12-Testing\.md:1 .*last executed/);
});
