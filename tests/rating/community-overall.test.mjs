import test from 'node:test';
import assert from 'node:assert/strict';
import {harness,activate,seed,addMatch,record,uuid,functionSql,current} from './harness.mjs';

// 0109: the community 'overall' rating runs the weighted Global formula; the
// weekly and monthly windows keep 0081's additive body. Real extracted SQL only.
async function install(db, file) {
  await db.exec(functionSql('supabase/migrations/' + file, 'community_scoped_rating'));
}
async function scoped(db, type, key) {
  return (await db.query(
    'select user_id, rating::text as rating, matches_played from community_scoped_rating($1,$2,$3) order by user_id',
    [uuid(900), type, key])).rows;
}
async function keys(db, type) {
  return (await db.query('select distinct statistics_period_key(start_at,$1) as k from matches order by 1', [type])).rows.map(r => r.k);
}

test('community overall rating shares the weighted Global formula; weekly and monthly are unchanged', async t => {
  const db = await harness();
  t.after(() => db.close());
  for (const fn of ['statistics_period_zone', 'statistics_period_key'])
    await db.exec(functionSql('supabase/migrations/0028_community_statistics.sql', fn));
  await db.exec(functionSql('supabase/migrations/0046_guest_statistics_isolation.sql', 'match_result_contribution'));
  await seed(db, 4);
  // Spread matches over two months and several ISO weeks, with goals and MVPs.
  for (const n of [35, 36, 40, 63]) await addMatch(db, n);
  await record(db, 2, 2, 0, uuid(3));

  await install(db, '0081_community_scoped_rating_and_public_results.sql');
  const legacy = {};
  for (const type of ['weekly', 'monthly'])
    for (const k of await keys(db, type)) legacy[type + ':' + k] = await scoped(db, type, k);
  assert.ok(Object.keys(legacy).length >= 4);

  await activate(db);
  await install(db, '0109_community_overall_weighted_rating.sql');

  await t.test('weekly and monthly outputs are identical to 0081', async () => {
    for (const [scope, rows] of Object.entries(legacy)) {
      const [type, k] = scope.split(':');
      assert.deepEqual(await scoped(db, type, k), rows, scope);
    }
  });

  await t.test('a single-community player gets exactly their Global Rating', async () => {
    const rows = await scoped(db, 'overall', 'overall');
    assert.equal(rows.length, 4);
    for (const r of rows) {
      assert.equal(Number(r.rating), await current(db, r.user_id), r.user_id);
      const played = (await db.query(
        'select count(*)::int n from match_team_assignments a join match_results x on x.match_id=a.match_id where a.user_id=$1',
        [r.user_id])).rows[0].n;
      assert.equal(r.matches_played, played);
    }
  });

  await t.test('a lineup-less scorer or MVP is listed at the prior and scores nothing', async () => {
    const before = await scoped(db, 'overall', 'overall');
    await db.query('insert into users(id) values($1)', [uuid(6)]);
    await db.query('insert into match_goals(match_id,user_id,goals) values($1,$2,1)', [uuid(101), uuid(6)]);
    await db.query('update match_results set mvp_user_id=$1 where match_id=$2', [uuid(6), uuid(104)]);
    const rows = await scoped(db, 'overall', 'overall');
    assert.deepEqual(rows.find(r => r.user_id === uuid(6)), { user_id: uuid(6), rating: '5.000', matches_played: 0 });
    assert.deepEqual(rows.filter(r => r.user_id !== uuid(6)), before);
  });
});
