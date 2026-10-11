// Reads supabase/migrations in order and works out which tables, views and
// functions exist once all of them have run. Pure functions, no dependencies:
// the checker (check-docs.mjs) and its tests import from here.

const MODES = new Set(['in', 'out', 'inout', 'variadic']);
const MULTIWORD_TYPES = [
  'double precision', 'character varying', 'timestamp with time zone',
  'timestamp without time zone', 'time with time zone', 'time without time zone',
  'bit varying',
];
const TYPE_ALIASES = {
  int: 'integer', int4: 'integer', int8: 'bigint', int2: 'smallint', bool: 'boolean',
  varchar: 'character varying', timestamptz: 'timestamp with time zone',
  timestamp: 'timestamp without time zone', float8: 'double precision', float4: 'real',
};

/**
 * Splits SQL into top-level statements. Comments are dropped, dollar-quoted
 * bodies (function bodies, DO blocks) are replaced by a placeholder so that
 * statements inside them are never mistaken for migration-level statements.
 * String literals are kept: COMMENT ON ... IS '...' needs them.
 */
export function splitStatements(sql) {
  const out = [];
  let cur = '';
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    const d = sql[i + 1];
    if (c === '-' && d === '-') {
      while (i < n && sql[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && d === '*') {
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (sql[i] === '/' && sql[i + 1] === '*') { depth++; i += 2; }
        else if (sql[i] === '*' && sql[i + 1] === '/') { depth--; i += 2; }
        else i++;
      }
      cur += ' ';
      continue;
    }
    if (c === "'") {
      let j = i + 1;
      let s = "'";
      while (j < n) {
        if (sql[j] === "'") {
          if (sql[j + 1] === "'") { s += "''"; j += 2; continue; }
          s += "'";
          j++;
          break;
        }
        s += sql[j];
        j++;
      }
      cur += s;
      i = j;
      continue;
    }
    if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 64));
      if (m) {
        const tag = m[0];
        const end = sql.indexOf(tag, i + tag.length);
        const stop = end === -1 ? n : end + tag.length;
        if (/^\s*comment\s+on\b/i.test(cur)) {
          const inner = sql.slice(i + tag.length, end === -1 ? n : end).replace(/'/g, "''");
          cur += `'${inner}'`;
        } else {
          cur += ' $body$ ';
        }
        i = stop;
        continue;
      }
    }
    if (c === '"') {
      let j = i + 1;
      while (j < n && sql[j] !== '"') j++;
      cur += sql.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    if (c === ';') {
      if (cur.trim()) out.push(cur.trim());
      cur = '';
      i++;
      continue;
    }
    cur += c;
    i++;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

const IDENT = '(?:"[^"]+"|[a-z_][a-z0-9_$]*)';
const QNAME = `${IDENT}(?:\\.${IDENT})?`;

/** `public.Foo` / `"Foo"` / `foo` -> `foo`; objects outside `public` -> null. */
export function publicName(raw) {
  const parts = raw.match(new RegExp(IDENT, 'gi')) ?? [];
  const clean = parts.map((p) => p.replace(/"/g, '').toLowerCase());
  if (clean.length === 1) return clean[0];
  if (clean.length === 2 && clean[0] === 'public') return clean[1];
  return null;
}

/** Index of the parenthesis matching the one at `open`, or -1. */
function matchParen(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '(') depth++;
    else if (text[i] === ')') { depth--; if (depth === 0) return i; }
  }
  return -1;
}

function splitTopLevel(text, sep = ',') {
  const parts = [];
  let depth = 0;
  let cur = '';
  for (const ch of text) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === sep && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  return parts;
}

function normalizeType(t) {
  let s = t.trim().toLowerCase().replace(/\s+/g, ' ').replace(/\s*\(.*?\)/g, '');
  const array = /(\[\]\s*)+$/.test(s) || /\barray\b/.test(s);
  s = s.replace(/(\[\]\s*)+$/, '').replace(/\barray\b/, '').trim();
  s = s.replace(/^public\./, '');
  if (TYPE_ALIASES[s]) s = TYPE_ALIASES[s];
  return array ? `${s}[]` : s;
}

/** Argument list text -> array of normalised types (names, modes, defaults removed). */
export function argTypes(argText) {
  const types = [];
  for (const raw of splitTopLevel(argText)) {
    let a = raw.trim().replace(/\s+/g, ' ');
    if (!a) continue;
    a = a.replace(/\s+(default\b|=\s).*$/i, '');
    const tokens = a.split(' ');
    if (MODES.has(tokens[0].toLowerCase())) {
      if (tokens[0].toLowerCase() === 'out') continue; // OUT params are not part of the call signature
      tokens.shift();
    }
    let rest = tokens.join(' ');
    const lower = rest.toLowerCase();
    const multi = MULTIWORD_TYPES.some((m) => lower.startsWith(m));
    if (tokens.length >= 2 && !multi) rest = tokens.slice(1).join(' ');
    types.push(normalizeType(rest));
  }
  return types;
}

function firstSentence(text) {
  const t = text.replace(/\s+/g, ' ').trim();
  const cut = t.search(/(?<=[.؟!])\s/);
  const s = cut > 5 ? t.slice(0, cut) : t;
  if (s.length <= 150) return s;
  const clipped = s.slice(0, 147);
  return `${clipped.slice(0, clipped.lastIndexOf(' ') > 60 ? clipped.lastIndexOf(' ') : 147)}...`;
}

/**
 * Applies migrations (array of {number, text}) in order and returns the objects
 * that exist at the end: {tables, views, functions, warnings}.
 * Each object: {name, introduced, changed, purpose}. Functions are tracked per
 * signature so that "create the new overload, drop the old one" is understood.
 */
export function buildCatalog(migrations) {
  const tables = new Map();
  const views = new Map();
  const fns = new Map(); // key `name(type,type)` -> entry
  const everIntroduced = new Map(); // `kind:name` -> first migration number
  const purposes = new Map(); // `kind:name` -> text
  const warnings = [];

  const intro = (kind, name, number) => {
    const k = `${kind}:${name}`;
    if (!everIntroduced.has(k)) everIntroduced.set(k, number);
    return everIntroduced.get(k);
  };

  for (const { number, text } of migrations) {
    for (const raw of splitStatements(text)) {
      const stmt = raw.replace(/\s+/g, ' ').trim();
      const low = stmt.toLowerCase();
      let m;

      if ((m = new RegExp(`^create (?:(global |local )?(temp|temporary|unlogged) )?table (?:if not exists )?(${QNAME})`, 'i').exec(stmt))) {
        if (m[2] && /temp/i.test(m[2])) continue;
        const name = publicName(m[3]);
        if (!name) continue;
        const prev = tables.get(name);
        tables.set(name, { name, introduced: prev?.introduced ?? intro('table', name, number), changed: number });
        continue;
      }
      if ((m = new RegExp(`^create (?:or replace )?(temp |temporary )?(?:recursive )?(?:materialized )?view (${QNAME})`, 'i').exec(stmt))) {
        if (m[1]) continue;
        const name = publicName(m[2]);
        if (!name) continue;
        const prev = views.get(name);
        views.set(name, { name, introduced: prev?.introduced ?? intro('view', name, number), changed: number });
        continue;
      }
      if ((m = new RegExp(`^create (?:or replace )?function (${QNAME})\\s*\\(`, 'i').exec(stmt))) {
        const name = publicName(m[1]);
        if (!name) continue;
        const open = stmt.indexOf('(', m.index + m[0].length - 1);
        const close = matchParen(stmt, open);
        const sig = argTypes(stmt.slice(open + 1, close));
        const key = `${name}(${sig.join(',')})`;
        const prev = fns.get(key);
        fns.set(key, { name, sig, key, introduced: prev?.introduced ?? intro('function', name, number), changed: number });
        continue;
      }
      if ((m = /^drop (table|view|materialized view|function) (?:if exists )?(.+?)(?: cascade| restrict)?$/i.exec(stmt))) {
        const kind = m[1].toLowerCase();
        const body = m[2];
        if (kind === 'function') {
          // `drop function [if exists] a(args), b(args)` -- walk the list entry by entry.
          let rest = body;
          const head = new RegExp(`^\\s*,?\\s*(${QNAME})\\s*`, 'i');
          for (let hm = head.exec(rest); hm; hm = head.exec(rest)) {
            const name = publicName(hm[1]);
            rest = rest.slice(hm[0].length);
            let argText = null;
            if (rest.startsWith('(')) {
              const close = matchParen(rest, 0);
              argText = rest.slice(1, close);
              rest = rest.slice(close + 1);
            }
            if (!name) continue;
            if (argText === null) {
              for (const f of [...fns.values()]) if (f.name === name) fns.delete(f.key);
              continue;
            }
            const sig = argTypes(argText);
            if (fns.delete(`${name}(${sig.join(',')})`)) continue;
            const same = [...fns.values()].filter((f) => f.name === name);
            const byArity = same.filter((f) => f.sig.length === sig.length);
            if (byArity.length === 1) fns.delete(byArity[0].key);
            else if (same.length === 1) fns.delete(same[0].key);
            else if (!/^drop function if exists /i.test(stmt)) warnings.push(`${number}: DROP FUNCTION ${name}(${sig}) matched no known signature`);
          }
        } else {
          const map = kind === 'table' ? tables : views;
          for (const part of splitTopLevel(body)) {
            const name = publicName(part.trim());
            if (name) map.delete(name);
          }
        }
        continue;
      }
      if ((m = new RegExp(`^alter (table|view|function) (?:if exists )?(?:only )?(${QNAME})(.*)$`, 'i').exec(stmt))) {
        const kind = m[1].toLowerCase();
        const name = publicName(m[2]);
        if (!name) continue;
        const tail = m[3];
        if (kind === 'function') {
          const rn = /rename to (\S+)/i.exec(tail);
          const open = tail.indexOf('(');
          const close = open >= 0 ? matchParen(tail, open) : -1;
          const sig = open >= 0 ? argTypes(tail.slice(open + 1, close)) : null;
          const entry = [...fns.values()].find((f) => f.name === name && (sig === null || f.key === `${name}(${sig.join(',')})`));
          if (entry) {
            if (rn) {
              fns.delete(entry.key);
              const to = publicName(rn[1]);
              if (to) { const key = `${to}(${entry.sig.join(',')})`; fns.set(key, { ...entry, name: to, key, changed: number }); }
            } else {
              entry.changed = number;
            }
          }
          continue;
        }
        const map = kind === 'table' ? tables : views;
        const entry = map.get(name);
        if (!entry) continue;
        const rn = /^\s*rename to (\S+)\s*$/i.exec(tail);
        if (rn) {
          const to = publicName(rn[1]);
          map.delete(name);
          if (to) {
            everIntroduced.set(`${kind}:${to}`, everIntroduced.get(`${kind}:${name}`) ?? entry.introduced);
            map.set(to, { ...entry, name: to, changed: number });
          }
        } else if (!/^\s*(rename column|rename constraint|owner to|enable|disable|force|no force)/i.test(tail) || /rename column/i.test(tail)) {
          entry.changed = number;
        }
        continue;
      }
      if ((m = new RegExp(`^comment on (table|view|function|materialized view) (${QNAME})(?:\\s*\\([^)]*\\))? is '((?:[^']|'')*)'`, 'i').exec(stmt))) {
        const name = publicName(m[2]);
        if (name) purposes.set(`${m[1].toLowerCase() === 'materialized view' ? 'view' : m[1].toLowerCase()}:${name}`, firstSentence(m[3].replace(/''/g, "'")));
        continue;
      }
      void low;
    }
  }

  const withPurpose = (kind, e) => ({ ...e, purpose: purposes.get(`${kind}:${e.name}`) ?? '' });
  const collapse = new Map();
  for (const f of fns.values()) {
    const prev = collapse.get(f.name);
    if (!prev) collapse.set(f.name, { ...f, overloads: 1 });
    else collapse.set(f.name, {
      ...prev,
      introduced: Math.min(prev.introduced, f.introduced),
      changed: Math.max(prev.changed, f.changed),
      overloads: prev.overloads + 1,
    });
  }
  const byName = (a, b) => a.name.localeCompare(b.name);
  return {
    tables: [...tables.values()].map((e) => withPurpose('table', e)).sort(byName),
    views: [...views.values()].map((e) => withPurpose('view', e)).sort(byName),
    functions: [...collapse.values()].map((e) => withPurpose('function', e)).sort(byName),
    warnings,
  };
}
