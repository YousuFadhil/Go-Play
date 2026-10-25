import test from 'node:test';
import assert from 'node:assert/strict';
import {harness,migrate,activate,seed,record,addMatch,uuid,read,closedForm,matchScore,stored,expected,current,legacyExpected} from './harness.mjs';

test('weighted SQL lifecycle and legacy rollback on isolated PostgreSQL', async t => {
  const db=await harness();
  t.after(()=>db.close());
  await seed(db);
  const before=(await db.query('select id,overall_rating from users order by id')).rows;
  const legacyRows=(await db.query('select count(*)::int as n from rating_history')).rows[0].n;
  await activate(db);
  async function allRatings() {
    for(const {id} of (await db.query('select id from users')).rows) {
      assert.equal(await current(db,id),stored(await expected(db,id)),id);
      const raw=(await db.query(`select raw_rating_after from rating_history h
        where user_id=$1 and reverses_id is null
        and not exists(select 1 from rating_history x where x.reverses_id=h.id)
        order by played_at desc,match_id desc limit 1`,[id])).rows[0];
      if(raw) assert.ok(Math.abs(Number(raw.raw_rating_after)-await expected(db,id))<1e-11);
    }
  }
  await t.test('activation archives legacy evidence and matches the closed-form oracle',async()=>{
    assert.equal((await db.query("select count(*)::int as n from rating_history_archive where rebase_version='0108_weighted_v1'")).rows[0].n,legacyRows);
    assert.deepEqual((await db.query("select user_id as id,overall_rating from user_rating_archive where rebase_version='0108_weighted_v1' order by user_id")).rows,before);
    await allRatings();
    await assert.rejects(db.exec("select rebase_rating_engine_v1('0108_weighted_v1')"), /REBASE_ALREADY_COMPLETED/);
    assert.equal(await current(db,uuid(5)),5);
    await assert.rejects(db.exec('update rating_history set delta=0'), /IMMUTABLE/);
    await assert.rejects(db.exec('delete from rating_history_archive'), /UNDELETABLE/);
  });
  await t.test('score is bounded and strictly rewards goals and MVP, independently of participation count',async()=>{
    for(const outcome of ['WIN','DRAW','LOSS']) {
      let last=-1;
      for(const goals of [0,1,2,7,8,100,2147483647]) {
        const r=(await db.query('select weighted_match_score_v1($1,$2,false) as a, weighted_match_score_v1($1,$2,true) as b',[outcome,goals])).rows[0];
        assert.ok(Number(r.a)>last);
        assert.ok(Number(r.b)>Number(r.a));
        assert.ok(Number(r.b)<10);
        assert.ok(Math.abs(Number(r.a)-matchScore(outcome,goals,false))<1e-12);
        last=Number(r.a);
      }
    }
    assert.ok(closedForm([...Array(80).fill(9.99),...Array(20).fill(.7)])<10);
    assert.ok(closedForm([...Array(20).fill(.7),...Array(80).fill(9.99)])>
      closedForm([...Array(80).fill(9.99),...Array(20).fill(.7)]));
    assert.equal((await db.query('select weighted_rating_storage_v1(9.999999) as n')).rows[0].n,'9.999');
    await assert.rejects(db.query("select weighted_match_score_v1('WIN',-1,false)"),/NEGATIVE_GOALS/);
  });
  await t.test('old result correction recomputes later ratings through the real record_match_result RPC',async()=>{
    await record(db,1,3,0,uuid(2)); await allRatings();
    const net=Number((await db.query('select 5+sum(delta) as n from rating_history where user_id=$1',[uuid(1)])).rows[0].n);
    assert.equal(net,await current(db,uuid(1)));
  });
  await t.test('reapplying unchanged evidence is idempotent',async()=>{
    const n=(await db.query('select count(*)::int as n from rating_history')).rows[0].n;
    await db.query('select apply_match_rating_effects($1)',[uuid(101)]);
    assert.equal((await db.query('select count(*)::int as n from rating_history')).rows[0].n,n);
  });
  await t.test('out-of-order insertion uses played date, and tied dates use match UUID',async()=>{
    const count=(await db.query('select count(*)::int n from rating_history')).rows[0].n;
    const prefix=(await db.query('select id from rating_history where match_id=$1 order by id',[uuid(104)])).rows;
    await addMatch(db,6);
    assert.equal((await db.query('select count(*)::int n from rating_history')).rows[0].n,count+4);
    assert.deepEqual((await db.query('select id from rating_history where match_id=$1 order by id',[uuid(104)])).rows,prefix);
    await addMatch(db,5); await allRatings();
    await db.exec('begin');
    await db.query('update matches set start_at=(select start_at from matches where id=$1) where id=$2',[uuid(101),uuid(106)]);
    await db.exec('commit'); await allRatings();
  });
  await t.test('removing a played participant and replacing MVP reverses their complete effect',async()=>{
    await record(db,2,0,1,null);
    await db.exec('begin');
    await db.query('select detach_match_effects($1)',[uuid(102)]);
    await db.query('delete from match_team_assignments where match_id=$1 and user_id=$2',[uuid(102),uuid(2)]);
    await db.query('select attach_match_effects($1)',[uuid(102)]);
    await db.exec('commit'); await allRatings();
  });
  await t.test('deleting a played match runs the real BEFORE DELETE reversal before cascading its history',async()=>{
    await db.query('delete from matches where id=$1',[uuid(101)]); await allRatings();
    for(let p=1;p<=4;p++) {
      const sum=Number((await db.query('select coalesce(sum(delta),0)+5 as n from rating_history where user_id=$1',[uuid(p)])).rows[0].n);
      assert.equal(sum,await current(db,uuid(p)));
    }
  });
  await t.test('account merge scoped reversal/replay returns to baseline without moving others',async()=>{
    const other=await current(db,uuid(3));
    await db.exec('begin');
    await db.query("select set_config('goplay.account_merge','tx:'||txid_current()::text,true), set_config('goplay.rating_replay_user',$1,true)",[uuid(1)]);
    const matches=(await db.query(`select distinct h.match_id from rating_history h where h.user_id=$1
      and h.reverses_id is null and not exists(select 1 from rating_history x where x.reverses_id=h.id)`,[uuid(1)])).rows;
    for(const r of matches) await db.query('select reverse_match_rating_effects($1)',[r.match_id]);
    assert.equal(await current(db,uuid(1)),5);
    assert.equal(await current(db,uuid(3)),other);
    for(const r of matches.reverse()) await db.query('select apply_match_rating_effects($1)',[r.match_id]);
    await db.exec('commit'); await allRatings();
  });
  await t.test('transaction failure leaves both audit and rating unchanged',async()=>{
    const snapshot=JSON.stringify((await db.query('select * from users order by id')).rows);
    const n=(await db.query('select count(*)::int as n from rating_history')).rows[0].n;
    await assert.rejects(db.transaction(async tx=>{
      await tx.query('select reverse_match_rating_effects($1)',[uuid(103)]);
      await tx.exec("select 1/0");
    }));
    assert.equal(JSON.stringify((await db.query('select * from users order by id')).rows),snapshot);
    assert.equal((await db.query('select count(*)::int as n from rating_history')).rows[0].n,n);
  });
  await t.test('clients cannot call replay, rebase or internal score helpers',async()=>{
    for(const role of ['anon','authenticated']) {
      await db.exec('set role '+role);
      await assert.rejects(db.query('select replay_weighted_player_v1($1,$2,true)',[uuid(1),uuid(102)]),/permission denied/);
      await assert.rejects(db.exec("select rebase_rating_engine_v1('unapproved')"),/permission denied/);
      await db.exec('reset role');
    }
  });
  await t.test('rollback preserves new football and archives weighted inputs, then restores legacy calculation',async()=>{
    await addMatch(db,7);
    const count=(await db.query('select count(*)::int as n from matches')).rows[0].n;
    await db.exec(read('supabase/rollback/0108_weighted_rating_v1_rollback.sql'));
    assert.equal((await db.query('select count(*)::int as n from matches')).rows[0].n,count);
    for(let p=1;p<=5;p++) assert.equal(await current(db,uuid(p)),await legacyExpected(db,uuid(p)));
    assert.ok((await db.query("select count(*)::int as n from rating_history_archive where rebase_version='0108_rollback_0078' and engine_version='weighted_v1' and raw_rating_after is not null")).rows[0].n>0);
    await assert.rejects(db.exec(read('supabase/rollback/0108_weighted_rating_v1_rollback.sql')),/WEIGHTED_ENGINE_NOT_ACTIVE/);
    await db.exec('rollback');
  });
});

test('migration alone is inert: the live legacy result path keeps working until activation',async()=>{
  const db=await harness();
  try {
    await seed(db);
    await migrate(db);
    await addMatch(db,6);
    await record(db,1,3,0,uuid(2));
    await db.query("update matches set start_at=start_at+interval '1 hour' where id=$1",[uuid(102)]);
    await db.query('delete from matches where id=$1',[uuid(103)]);
    for(let p=1;p<=5;p++) assert.equal(await current(db,uuid(p)),await legacyExpected(db,uuid(p)));
    assert.equal((await db.query("select count(*)::int as n from rating_history where engine_version is not null")).rows[0].n,0);
    assert.equal((await db.query('select count(*)::int as n from rating_rebase_runs')).rows[0].n,
      (await db.query("select count(*)::int as n from rating_rebase_runs where rebase_version<>'0108_weighted_v1'")).rows[0].n);
  } finally { await db.close(); }
});
