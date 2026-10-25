import fs from 'node:fs';
import {harness,activate,uuid,current,expected} from './harness.mjs';
// Input MUST be an anonymous SELECT export. Never commit the export.
// Usage: node tests/rating/replay-snapshot.mjs <private-local-json-path>
const snapshot=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const db=await harness();
try {
  const uid=p=>uuid((p.startsWith('P')?0:p.startsWith('G')?10000:20000)+Number(p.slice(1)));
  await db.query('insert into communities(id) values($1)',[uuid(900)]);
  for(const p of snapshot.players) await db.query('insert into users(id) values($1)',[uid(p.p)]);
  for(const m of snapshot.matches){
    await db.query('insert into matches(id,start_at,end_at,community_id) values($1,$2,$3,$4)',[uid(m.m),m.start,m.end,uuid(900)]);
    for(const l of m.lineup)await db.query('insert into match_team_assignments(match_id,user_id,professional_guest_id,team) values($1,$2,$3,$4)',[uid(m.m),l.p.startsWith('P')?uid(l.p):null,l.p.startsWith('G')?uid(l.p):null,l.team]);
    for(const g of m.goals)await db.query('insert into match_goals(match_id,user_id,professional_guest_id,goals) values($1,$2,$3,$4)',[uid(m.m),g.p.startsWith('P')?uid(g.p):null,g.p.startsWith('G')?uid(g.p):null,g.g]);
    await db.query('insert into match_results(match_id,team_a_score,team_b_score,mvp_user_id,mvp_professional_guest_id) values($1,$2,$3,$4,$5)',[uid(m.m),m.a,m.b,m.mvp?.startsWith('P')?uid(m.mvp):null,m.mvp?.startsWith('G')?uid(m.mvp):null]);
    await db.query('select apply_match_rating_effects($1)',[uid(m.m)]);
  }
  let oldError=0;
  for(const p of snapshot.players)oldError=Math.max(oldError,Math.abs(await current(db,uid(p.p))-p.old));
  const start=Date.now();await activate(db);const elapsed=Date.now()-start;
  let rawError=0,storageError=0;const changes=[];
  for(const p of snapshot.players){
    const r=(await db.query('select raw_rating_after from rating_history where user_id=$1 order by entry_no desc limit 1',[uid(p.p)])).rows[0];
    const raw=Number(r?.raw_rating_after??5),actual=await current(db,uid(p.p));
    rawError=Math.max(rawError,Math.abs(raw-await expected(db,uid(p.p))));
    storageError=Math.max(storageError,Math.abs(actual-raw));changes.push({old:p.old,raw,actual});
  }
  console.log(JSON.stringify({
    asof:snapshot.asof,matches:snapshot.matches.length,players:snapshot.players.length,
    oldReplayMaxError:oldError,weightedRawMaxError:rawError,storageMaxError:storageError,
    elapsedMs:elapsed,historyRows:(await db.query('select count(*)::int n from rating_history')).rows[0].n,
    oldMean:changes.reduce((s,p)=>s+p.old,0)/changes.length,
    newMean:changes.reduce((s,p)=>s+p.actual,0)/changes.length,
    newMin:Math.min(...changes.map(p=>p.actual)),newMax:Math.max(...changes.map(p=>p.actual)),
    maxDecrease:Math.max(...changes.map(p=>p.old-p.actual)),
    down:changes.filter(p=>p.actual<p.old).length,up:changes.filter(p=>p.actual>p.old).length
  },null,2));
  if(oldError>0.001 || rawError>1e-11 || storageError>0.001)process.exitCode=1;
} finally { await db.close(); }
