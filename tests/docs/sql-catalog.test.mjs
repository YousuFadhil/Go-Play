import test from 'node:test';
import assert from 'node:assert/strict';
import { splitStatements, argTypes, buildCatalog, publicName } from '../../tool/sql-catalog.mjs';

const run = (...texts) => buildCatalog(texts.map((text, i) => ({ number: i + 1, text })));
const names = (list) => list.map((e) => e.name);

test('comments and dollar-quoted bodies never create objects', () => {
  const c = run(`
    -- create table fake_in_comment (id int);
    /* create table fake_in_block (id int); */
    create table public.real_one (id int);
    create or replace function public.f() returns void language plpgsql as $fn$
    begin
      create temp table inside_body (x int);
      perform 1; -- ; a semicolon in a comment
    end;
    $fn$;
    do $$ begin execute 'create table dynamic_one (id int)'; end $$;
  `);
  assert.deepEqual(names(c.tables), ['real_one']);
  assert.deepEqual(names(c.functions), ['f']);
});

test('semicolons inside string literals do not split a statement', () => {
  const stmts = splitStatements(`comment on table t is 'one; two'; select 1;`);
  assert.equal(stmts.length, 2);
  assert.match(stmts[0], /one; two/);
});

test('rename keeps the original introduction (groups -> communities)', () => {
  const c = run(
    `create table public.groups (id int);`,
    `alter table public.groups rename to communities;`,
    `alter table public.communities add column wilayat_code int;`,
  );
  assert.deepEqual(names(c.tables), ['communities']);
  assert.equal(c.tables[0].introduced, 1);
  assert.equal(c.tables[0].changed, 3);
});

test('dropped objects disappear, recreated ones keep their first introduction', () => {
  const c = run(
    `create table public.a (id int); create table public.b (id int);`,
    `drop table if exists public.a, public.b cascade;`,
    `create table public.b (id int, extra int);`,
  );
  assert.deepEqual(names(c.tables), ['b']);
  assert.equal(c.tables[0].introduced, 1);
  assert.equal(c.tables[0].changed, 3);
});

test('a new overload plus a drop of the old signature leaves the new one', () => {
  const c = run(
    `create function public.create_community(p_name text, p_pitch text) returns uuid language sql as $$ select null::uuid $$;`,
    `create function public.create_community(p_name text, p_pitch text, p_wilayat integer default null) returns uuid language sql as $$ select null::uuid $$;
     drop function if exists public.create_community(text, text);`,
  );
  assert.equal(c.functions.length, 1);
  assert.equal(c.functions[0].overloads, 1);
  assert.equal(c.functions[0].introduced, 1);
  assert.equal(c.functions[0].changed, 2);
});

test('create or replace updates "changed" without a second entry', () => {
  const c = run(
    `create function public.g(a uuid) returns int language sql as $$ select 1 $$;`,
    `create or replace function public.g(a uuid) returns int language sql as $$ select 2 $$;`,
  );
  assert.equal(c.functions.length, 1);
  assert.equal(c.functions[0].changed, 2);
});

test('objects in other schemas are ignored', () => {
  const c = run(`create table auth.thing (id int); create function storage.helper() returns int language sql as $$ select 1 $$;`);
  assert.equal(c.tables.length, 0);
  assert.equal(c.functions.length, 0);
});

test('COMMENT ON supplies the purpose, first sentence only', () => {
  const c = run(`
    create function public.h() returns int language sql as $$ select 1 $$;
    comment on function public.h() is 'Returns one. It never writes anything.';
  `);
  assert.equal(c.functions[0].purpose, 'Returns one.');
});

test('argument parsing ignores names, modes and defaults and normalises aliases', () => {
  assert.deepEqual(argTypes('p_id uuid, in p_n int default 3, out p_x text, p_when timestamptz, double precision'),
    ['uuid', 'integer', 'timestamp with time zone', 'double precision']);
  assert.deepEqual(argTypes(''), []);
});

test('publicName', () => {
  assert.equal(publicName('public."Foo"'), 'foo');
  assert.equal(publicName('foo'), 'foo');
  assert.equal(publicName('auth.users'), null);
});
