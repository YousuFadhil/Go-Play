import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
export const root = new URL('../../', import.meta.url);
export const read = p => fs.readFileSync(new URL(p, root), 'utf8').replaceAll('\r\n', '\n');
export const uuid = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
export const functionSql = (path, name) => {
  const source = read(path);
  const start = source.indexOf('create or replace function public.' + name + '(');
  if (start < 0) throw new Error('Missing source function: ' + name);
  const end = source.indexOf('$$;', start);
  return source.slice(start, end + 3);
};
export async function harness() {
  const db = new PGlite();
  // Isolated PostgreSQL fixture: real rating/result functions, simplified tables
  // and explicit auth/statistics stubs. No production URL or credentials.
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select '00000000-0000-4000-8000-000000000001'::uuid $$;
    create table users(id uuid primary key, overall_rating numeric(5,3) default 5 not null);
    create table communities(id uuid primary key, is_active boolean default true);
    create table matches(id uuid primary key, start_at timestamptz not null,
      end_at timestamptz not null, status text default 'completed',
      community_id uuid references communities);
    create table match_results(match_id uuid primary key references matches on delete cascade,
      team_a_score int, team_b_score int, mvp_user_id uuid,
      mvp_professional_guest_id uuid, recorded_by uuid);
    create table match_goals(match_id uuid references matches on delete cascade,
      user_id uuid, professional_guest_id uuid, goals int);
    create table match_team_assignments(match_id uuid references matches on delete cascade,
      user_id uuid, professional_guest_id uuid, team text, assigned_position text,
      unique(match_id, user_id));
    create table rating_history(
      id uuid primary key default gen_random_uuid(),
      entry_no bigint generated always as identity,
      user_id uuid not null references users on delete cascade,
      match_id uuid not null references matches on delete cascade,
      change_reason text not null check (change_reason in (
        'PARTICIPATION','WIN','DRAW','LOSS','GOAL','MVP','REVERSAL')),
      delta numeric(5,3) not null, rating_before numeric(5,3) not null,
      rating_after numeric(5,3) not null,
      reverses_id uuid references rating_history on delete cascade,
      created_at timestamptz default now() not null);
    create unique index rating_history_reverses_id_idx on rating_history(reverses_id)
      where reverses_id is not null;
    create index on rating_history(user_id);
    create index on rating_history(match_id);
    create function is_current_user_active() returns boolean language sql as $$ select true $$;
    create function is_match_community_admin(uuid, uuid) returns boolean
      language sql as $$ select true $$;
    create function apply_match_statistics(uuid, int) returns void
      language plpgsql as $$ begin return; end $$;
  `);
  for (const [file, fn] of [
    ['0101_platform_admin_account_merge.sql', 'merge_rating_scope_excludes'],
    ['0101_platform_admin_account_merge.sql', 'apply_rating_delta'],
    ['0078_rating_goal_mvp_values.sql', 'apply_match_rating_effects'],
    ['0022_match_results.sql', 'reverse_match_rating_effects'],
    ['0022_match_results.sql', 'reject_rating_history_update'],
    ['0022_match_results.sql', 'reverse_match_effects_before_delete'],
    ['0074_all_state_match_management.sql', 'record_match_result'],
    ['0029_completed_match_editing.sql', 'detach_match_effects'],
    ['0029_completed_match_editing.sql', 'attach_match_effects'],
  ]) await db.exec(functionSql('supabase/migrations/' + file, fn));
  await db.exec(`
    create trigger rating_history_immutable before update on rating_history
      for each row execute function reject_rating_history_update();
    create trigger matches_reverse_result_effects before delete on matches
      for each row execute function reverse_match_effects_before_delete();
  `);
  await db.exec('begin;' + read('supabase/migrations/0082_rating_engine_0078_historical_rebase.sql') + 'commit;');
  return db;
}
// Two real deployment steps: the inert migration (db push), then the separate
// manual activation script, which carries its own begin/commit.
export async function migrate(db) {
  await db.exec('begin;' + read('supabase/migrations/0108_weighted_rating_v1.sql') + 'commit;');
}
export async function activate(db) {
  await migrate(db);
  await db.exec(read('supabase/activation/0108_weighted_rating_v1_activate.sql'));
}
export async function seed(db, count = 4) {
  await db.query('insert into communities(id) values($1)', [uuid(900)]);
  for (let i = 1; i <= 5; i++) await db.query('insert into users(id) values($1)', [uuid(i)]);
  for (let i = 1; i <= count; i++) await addMatch(db, i);
}
export async function addMatch(db, n) {
  await db.query('insert into matches(id,start_at,end_at,community_id) values($1,$2,$3,$4)',
    [uuid(100+n), new Date(Date.UTC(2026,0,n)).toISOString(),
      new Date(Date.UTC(2026,0,n,2)).toISOString(), uuid(900)]);
  for (let p = 1; p <= 4; p++)
    await db.query("insert into match_team_assignments(match_id,user_id,team) values($1,$2,$3)",
      [uuid(100+n),uuid(p),p <= 2 ? 'A' : 'B']);
  const a = n % 3, b = (n+1) % 3;
  await record(db, n, a, b, n % 2 ? uuid(1) : null);
}
export async function record(db, n, a, b, mvp = null) {
  const goals = [];
  if(a) goals.push({user_id:uuid(1),goals:a});
  if(b) goals.push({user_id:uuid(3),goals:b});
  await db.query('select record_match_result($1,$2,$3,$4,$5::jsonb)',
    [uuid(100+n),a,b,mvp,JSON.stringify(goals)]);
}
// Independent closed-form reference: no recurrence copied from SQL.
export function closedForm(scores) {
  const n=scores.length, q=26/27;
  const numerator=70*q**n + scores.reduce((s,x,i)=>s+x*q**(n-1-i),0);
  const denominator=14*q**n + scores.reduce((s,_,i)=>s+q**(n-1-i),0);
  return ((70+scores.reduce((a,b)=>a+b,0))/(14+n)+numerator/denominator)/2;
}
export function matchScore(outcome, goals, mvp) {
  const base={WIN:8.8,DRAW:4.4,LOSS:0}[outcome];
  const budget={WIN:1.2,DRAW:.6,LOSS:.7}[outcome];
  return base + budget*(2*goals/(3*(goals+2)) + (mvp ? 1/3 : 0));
}
export const stored = x => Math.min(9.999, Math.round(x*1000)/1000);
export async function evidence(db, id) {
  return (await db.query(`
    select m.id, m.start_at, a.team, mr.team_a_score as a, mr.team_b_score as b,
      coalesce(mr.mvp_user_id=$1,false) as mvp,
      coalesce((select sum(g.goals) from match_goals g
        where g.match_id=m.id and g.user_id=$1),0)::integer as goals
    from matches m join match_results mr on mr.match_id=m.id
      join match_team_assignments a on a.match_id=m.id and a.user_id=$1
    order by m.start_at, m.id
  `,[id])).rows;
}
export async function expected(db,id) {
  const rows=await evidence(db,id);
  return closedForm(rows.map(r => matchScore(r.a===r.b?'DRAW':
    ((r.team==='A')===(r.a>r.b))?'WIN':'LOSS',r.goals,r.mvp)));
}
export async function current(db,id) {
  return Number((await db.query('select overall_rating from users where id=$1',[id])).rows[0].overall_rating);
}
export async function legacyExpected(db,id) {
  let rating=5;
  for(const r of await evidence(db,id)) {
    const steps=[.005,r.a===r.b?.01:((r.team==='A')===(r.a>r.b))?.1:-.1];
    if(r.goals) steps.push(Math.min(.07,.01*r.goals));
    if(r.mvp) steps.push(.02);
    for(const d of steps) rating=Math.round(Math.max(0,Math.min(10,rating+d))*1000)/1000;
  }
  return rating;
}
