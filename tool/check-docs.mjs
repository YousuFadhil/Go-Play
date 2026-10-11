#!/usr/bin/env node
// Documentation drift guard.
//
//   node tool/check-docs.mjs            run every check, exit 1 on any failure
//   node tool/check-docs.mjs --write    regenerate Docs/engineering/DB_Object_Catalog.md, then check
//
// The idea: whatever can be derived from the repository is generated, and
// whatever must be written by hand is checked against the repository, so the
// documentation cannot fall behind silently. No dependencies; needs Node 18+
// and git on the PATH.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { buildCatalog } from './sql-catalog.mjs';

export const CATALOG_PATH = 'Docs/engineering/DB_Object_Catalog.md';
export const ARCHITECTURE_DOC = 'Docs/03-Technical-Architecture.md';
/** Migrations from this number on must be named in CHANGELOG.md. */
export const CHANGELOG_FLOOR = 95;
/** Documents whose repository paths must resolve, and where bare names may live. */
const REFERENCE_DOCS = ['CLAUDE.md', 'SETUP.md', 'Docs/README.md'];
const REFERENCE_BASES = ['', 'Docs/', 'Docs/engineering/', 'supabase/migrations/', 'app/'];
/** Facts that go stale the day after they are written: point to the source instead. */
const VOLATILE = [
  { files: ['SETUP.md', 'Docs/README.md', 'Docs/12-Testing.md'], re: /schema (?:as it stands )?(?:through|after) migration\s*`?\d{4}/i, why: 'a migration number written in prose (the newest file in supabase/migrations is the truth)' },
  { files: ['SETUP.md', 'Docs/README.md', 'Docs/12-Testing.md'], re: /\b\d+\s+(?:passed|tests? passed)\b|\d+\s+ناجح|\d+\s+اختبار(?:اً|ا)?\s+(?:ناجح|تكامل)/i, why: 'a test count written in prose (run the suite for the current number)' },
  { files: ['SETUP.md'], re: /^#\s.*`v\d+\.\d+\.\d+[^`]*`/, why: 'a version stamp in the title (see CHANGELOG.md)' },
  { files: ['Docs/README.md', 'Docs/12-Testing.md'], re: /Last executed:/i, why: 'a "last executed" result (it is stale on the next commit)' },
  { files: ['Docs/README.md', 'SETUP.md'], re: /Current as of\s+`?v?\d/i, why: 'a version stamp in prose (see CHANGELOG.md)' },
];

const read = (root, rel) => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const exists = (root, rel) => fs.existsSync(path.join(root, rel));
const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, ' ');
const pad4 = (n) => String(n).padStart(4, '0');

export function readMigrations(root) {
  const dir = path.join(root, 'supabase/migrations');
  return fs.readdirSync(dir)
    .filter((f) => /^\d{4}.*\.sql$/.test(f))
    .sort()
    .map((f) => ({ file: f, number: parseInt(f.slice(0, 4), 10), text: fs.readFileSync(path.join(dir, f), 'utf8') }));
}

function firstSentenceOfReadme(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const start = lines.findIndex((l, i) => i > 0 && l.trim() && !l.startsWith('#'));
  if (start < 0) return '';
  const para = [];
  for (let i = start; i < lines.length && lines[i].trim(); i++) para.push(lines[i].trim());
  const flat = para.join(' ').replace(/`/g, '');
  const cut = flat.search(/\.\s/);
  const s = cut > 0 ? flat.slice(0, cut + 1) : flat;
  return s.length > 170 ? `${s.slice(0, 167)}...` : s;
}

export function listEdgeFunctions(root) {
  const dir = path.join(root, 'supabase/functions');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_'))
    .map((d) => {
      const readme = `supabase/functions/${d.name}/README.md`;
      return { name: d.name, readme: exists(root, readme) ? readme : null, purpose: exists(root, readme) ? firstSentenceOfReadme(read(root, readme)) : '' };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function listPagesFunctions(root) {
  const base = path.join(root, 'functions');
  if (!fs.existsSync(base)) return [];
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) walk(full);
      else if (/\.(js|mjs|ts)$/.test(e.name)) {
        const rel = path.relative(root, full).split(path.sep).join('/');
        const route = `/${rel.slice('functions/'.length).replace(/\.(js|mjs|ts)$/, '').replace(/\/index$/, '').replace(/\[([^\]]+)\]/g, ':$1')}`;
        out.push({ file: rel, route });
      }
    }
  };
  walk(base);
  return out.sort((a, b) => a.file.localeCompare(b.file));
}

export function listWorkflows(root) {
  const dir = path.join(root, '.github/workflows');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => /\.ya?ml$/.test(f)).sort().map((f) => {
    const lines = read(root, `.github/workflows/${f}`).split('\n');
    const name = (lines.find((l) => l.startsWith('name:')) ?? '').replace(/^name:\s*/, '').replace(/^["']|["']$/g, '');
    const onAt = lines.findIndex((l) => /^on:/.test(l));
    const triggers = [];
    if (onAt >= 0) {
      for (let i = onAt + 1; i < lines.length; i++) {
        if (/^\S/.test(lines[i]) && lines[i].trim()) break;
        const m = /^ {2}([a-z_]+):/.exec(lines[i]);
        if (m) triggers.push(m[1]);
      }
    }
    return { file: `.github/workflows/${f}`, name, triggers: triggers.join(', ') || (lines[onAt] ?? '').replace(/^on:\s*/, '') };
  });
}

/** Table specifications under Docs/engineering, keyed by the table they describe. */
export function listTableSpecs(root) {
  const dir = path.join(root, 'Docs/engineering');
  if (!fs.existsSync(dir)) return new Map();
  const map = new Map();
  for (const f of fs.readdirSync(dir).filter((x) => /_Table_Specification\.md$/.test(x)).sort()) {
    const heading = read(root, `Docs/engineering/${f}`).split('\n').find((l) => l.startsWith('# ')) ?? '';
    const m = /\(`([a-z_0-9]+)`\)/.exec(heading);
    if (m) map.set(m[1], f);
  }
  return map;
}

export function renderCatalog(root) {
  const migrations = readMigrations(root);
  const cat = buildCatalog(migrations);
  const newest = migrations[migrations.length - 1];
  const specs = listTableSpecs(root);
  const edge = listEdgeFunctions(root);
  const pages = listPagesFunctions(root);
  const flows = listWorkflows(root);
  const mig = (n) => `\`${pad4(n)}\``;
  const L = [];
  L.push('# Database and Platform Catalog');
  L.push('');
  L.push('> **Generated file. Do not edit by hand.** Regenerate it with `node tool/check-docs.mjs --write`;');
  L.push('> `node tool/check-docs.mjs` fails when it is out of date.');
  L.push('');
  L.push(`Source of truth: the ${migrations.length} files in \`supabase/migrations/\`, newest ${mig(newest.number)}.`);
  L.push('');
  L.push('This is an **index** of what exists and which migration made it, not a specification. Behaviour is described');
  L.push('in each migration\'s header comment, in the table specifications under `Docs/engineering/`, and in');
  L.push('`Docs/10-Design-Decisions.md`.');
  L.push('');
  L.push('*Introduced* is the first migration that created the object; *Last changed* is the latest one that replaced or altered it.');
  L.push('*Purpose* is the first sentence of the object\'s `COMMENT ON` when its migration wrote one, and empty otherwise.');
  L.push('');
  L.push(`## Tables (${cat.tables.length})`);
  L.push('');
  L.push('| Table | Introduced | Last changed | Specification | Purpose |');
  L.push('|---|---|---|---|---|');
  for (const t of cat.tables) {
    const spec = specs.get(t.name);
    L.push(`| \`${t.name}\` | ${mig(t.introduced)} | ${mig(t.changed)} | ${spec ? `[${spec.replace('_Table_Specification.md', '')}](${spec})` : ''} | ${esc(t.purpose)} |`);
  }
  const unbuilt = [...specs.entries()].filter(([table]) => !cat.tables.some((t) => t.name === table));
  if (unbuilt.length) {
    L.push('');
    L.push('### Specified, but no such table exists after all migrations');
    L.push('');
    L.push('A table specification exists for each of these, and no migration leaves a table of that name behind.');
    L.push('Treat the specification as the design as approved, not as the schema; the migration headers say what was built instead.');
    L.push('');
    for (const [table, file] of unbuilt) L.push(`- \`${table}\` — [${file}](${file})`);
  }
  L.push('');
  L.push(`## Views (${cat.views.length})`);
  L.push('');
  L.push('| View | Introduced | Last changed | Purpose |');
  L.push('|---|---|---|---|');
  for (const v of cat.views) L.push(`| \`${v.name}\` | ${mig(v.introduced)} | ${mig(v.changed)} | ${esc(v.purpose)} |`);
  L.push('');
  L.push(`## Functions (${cat.functions.length})`);
  L.push('');
  L.push('RPCs, helpers and trigger functions in the `public` schema, by name. Overloads are counted once.');
  L.push('');
  L.push('| Function | Introduced | Last changed | Purpose |');
  L.push('|---|---|---|---|');
  for (const f of cat.functions) {
    L.push(`| \`${f.name}\`${f.overloads > 1 ? ` (${f.overloads} overloads)` : ''} | ${mig(f.introduced)} | ${mig(f.changed)} | ${esc(f.purpose)} |`);
  }
  L.push('');
  L.push(`## Edge Functions (${edge.length})`);
  L.push('');
  L.push('| Function | Purpose | README |');
  L.push('|---|---|---|');
  for (const e of edge) L.push(`| \`${e.name}\` | ${esc(e.purpose)} | ${e.readme ? `[README](../../${e.readme})` : '**missing**'} |`);
  if (pages.length) {
    L.push('');
    L.push(`## Cloudflare Pages Functions (${pages.length})`);
    L.push('');
    L.push('| Route | File |');
    L.push('|---|---|');
    for (const p of pages) L.push(`| \`${p.route}\` | \`${p.file}\` |`);
  }
  L.push('');
  L.push(`## GitHub Actions workflows (${flows.length})`);
  L.push('');
  L.push('| Workflow | Name | Triggers |');
  L.push('|---|---|---|');
  for (const w of flows) L.push(`| \`${w.file}\` | ${esc(w.name)} | ${esc(w.triggers)} |`);
  L.push('');
  return L.join('\n');
}

/** Returns a list of {check, message}; empty means the documentation is in step. */
export function runChecks({ root, tracked }) {
  const fails = [];
  const fail = (check, message) => fails.push({ check, message });
  const trackedSet = new Set(tracked);

  // 1. The generated catalog matches the migrations.
  if (!exists(root, CATALOG_PATH)) fail('catalog', `${CATALOG_PATH} is missing. Run: node tool/check-docs.mjs --write`);
  else if (read(root, CATALOG_PATH).trimEnd() !== renderCatalog(root).trimEnd()) {
    fail('catalog', `${CATALOG_PATH} is out of date with supabase/migrations, supabase/functions, functions/ or .github/workflows. Run: node tool/check-docs.mjs --write`);
  }

  // 2. Every recent migration is named in the CHANGELOG.
  if (!exists(root, 'CHANGELOG.md')) fail('changelog', 'CHANGELOG.md is missing');
  else {
    const changelog = read(root, 'CHANGELOG.md');
    for (const m of readMigrations(root)) {
      if (m.number >= CHANGELOG_FLOOR && !new RegExp(`\\b${pad4(m.number)}\\b`).test(changelog)) {
        fail('changelog', `migration ${pad4(m.number)} (${m.file}) is not named in CHANGELOG.md. Add one line about what it changes.`);
      }
    }
  }

  // 3. Every Edge Function and Pages Function has a README / is described in the architecture document.
  const arch = exists(root, ARCHITECTURE_DOC) ? read(root, ARCHITECTURE_DOC) : '';
  for (const e of listEdgeFunctions(root)) {
    if (!e.readme) fail('functions', `supabase/functions/${e.name} has no README.md`);
    if (!arch.includes(e.name)) fail('functions', `Edge Function "${e.name}" is not named in ${ARCHITECTURE_DOC}`);
  }
  for (const p of listPagesFunctions(root)) {
    if (!arch.includes(p.file) && !arch.includes(p.route)) fail('functions', `Pages Function ${p.file} is not described in ${ARCHITECTURE_DOC}`);
  }

  // 4. Repository paths written in the entry-point documents still exist (case-sensitively).
  for (const doc of REFERENCE_DOCS) {
    if (!exists(root, doc)) continue;
    const text = read(root, doc);
    const seen = new Set();
    for (const m of text.matchAll(/`([^`\n]+)`/g)) {
      const token = m[1].trim();
      if (seen.has(token)) continue;
      seen.add(token);
      if (/[<>*{}$\s]|\.\.\.|\bxx\b|NNNN|^https?:|^\.\.?\/|^~|^[A-Za-z]:\\/.test(token)) continue;
      if (!/\.(md|sql|ya?ml|dart|mjs|js|ts|json|toml|txt)$/.test(token)) continue;
      const pathLike = token.includes('/') || /^\d{2}-.*\.md$/.test(token) || /^[A-Z][A-Z0-9_]+\.md$/.test(token);
      if (!pathLike) continue;
      const found = REFERENCE_BASES.some((b) => trackedSet.has(b + token));
      if (!found) fail('references', `${doc} mentions \`${token}\` but no such tracked file exists`);
    }
  }

  // 5. No volatile facts written into prose.
  for (const rule of VOLATILE) {
    for (const file of rule.files) {
      if (!exists(root, file)) continue;
      read(root, file).split('\n').forEach((line, i) => {
        if (rule.re.test(line)) fail('volatile', `${file}:${i + 1} contains ${rule.why}`);
      });
    }
  }
  return fails;
}

// Tracked files plus untracked files that are not ignored, so a new file can be
// referenced before its first commit. CI checks out only committed files, so it
// is the stricter judge.
function trackedFiles(root) {
  const out = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return out.split('\0').filter(Boolean);
}

function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  if (process.argv.includes('--write')) {
    fs.writeFileSync(path.join(root, CATALOG_PATH), renderCatalog(root), 'utf8');
    console.log(`wrote ${CATALOG_PATH}`);
  }
  const fails = runChecks({ root, tracked: trackedFiles(root) });
  if (!fails.length) {
    console.log('docs in step with the repository: all checks passed');
    return;
  }
  const groups = new Map();
  for (const f of fails) groups.set(f.check, [...(groups.get(f.check) ?? []), f.message]);
  for (const [check, messages] of groups) {
    console.error(`\nFAIL ${check} (${messages.length})`);
    for (const m of messages) console.error(`  - ${m}`);
  }
  console.error(`\n${fails.length} problem(s). See CLAUDE.md section 13 for what to update.`);
  process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
