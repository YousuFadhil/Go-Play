const { Button, Icon, Avatar, Chip, SectionHeading, EmptyState } = window.GoPlayDesignSystem_984b89;
const { TaskBar, TaskBody, RowGroup, ActionBar } = window;

function ResultScreen({ go, match, setToast, review }) {
  const d = window.T(review);
  const m = match || d.matches[2];
  const [a, setA] = React.useState(3);
  const [b, setB] = React.useState(2);
  const [goals, setGoals] = React.useState({ 'Yousuf Fadhil': 2, 'Omar Al Harthy': 1 });
  const [motm, setMotm] = React.useState('Yousuf Fadhil');
  const all = [...d.teams.a, ...d.teams.b];
  const scored = Object.values(goals).reduce((s, n) => s + n, 0);
  const mismatch = scored !== a + b;

  const Stepper = ({ v, set, label, tone }) => (
    <div style={{ flex: 1, textAlign: 'center' }}>
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, font: '700 12px/1 var(--font-sans)', color: '#fff', opacity: .85 }}>
        <span style={{ width: 18, height: 18, borderRadius: 5, background: tone, display: 'grid', placeItems: 'center', font: '700 10px/1 var(--font-sans)' }}>{label.slice(-1)}</span>
        {label}</div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, marginTop: 10 }}>
        <button type="button" onClick={() => set(Math.max(0, v - 1))} style={{ width: 34, height: 34, borderRadius: 17, border: '1.5px solid rgba(255,255,255,.32)', background: 'transparent', color: '#fff', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
          <Icon name="remove" size={17} /></button>
        <span style={{ font: '700 38px/1 var(--font-sans)', letterSpacing: '-1.6px', color: '#fff', minWidth: 40 }}>{v}</span>
        <button type="button" onClick={() => set(v + 1)} style={{ width: 34, height: 34, borderRadius: 17, border: 'none', background: '#fff', color: 'var(--gp-primary-deep)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
          <Icon name="add" size={17} /></button>
      </div>
    </div>
  );

  const bump = (name, n) => setGoals(g => { const v = Math.max(0, (g[name] || 0) + n); const next = { ...g }; if (v) next[name] = v; else delete next[name]; return next; });

  return (
    <>
      <TaskBar title="Match result" onBack={() => go('match', m)} />
      <TaskBody style={{ padding: '12px 14px 20px' }}>
        <div style={{ background: 'var(--gp-primary-deep)', borderRadius: 'var(--radius-card)', padding: '16px 14px' }}>
          <div dir="ltr" style={{ display: 'flex', alignItems: 'flex-start' }}>
            <Stepper v={a} set={setA} label="Team A" tone="rgba(255,255,255,.25)" />
            <div style={{ alignSelf: 'center', font: '700 20px/1 var(--font-sans)', color: 'rgba(255,255,255,.4)', padding: '0 4px', marginTop: 18 }}>–</div>
            <Stepper v={b} set={setB} label="Team B" tone="var(--gp-tertiary)" />
          </div>
          <div style={{ textAlign: 'center', marginTop: 14, font: '400 12.5px/1 var(--font-sans)', color: 'rgba(255,255,255,.72)' }}>
            {a === b ? 'Draw' : (a > b ? 'Team A' : 'Team B') + ' wins'}</div>
        </div>
        <SectionHeading title="Goalscorers" count={scored + ' of ' + (a + b)} style={{ padding: '18px 4px 9px' }} />
        <RowGroup>
          {all.map(p => {
            const n = goals[p.name] || 0;
            return (
              <div key={p.name} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 16px', minHeight: 54 }}>
                <Avatar name={p.guest ? '' : p.name} size={34} tone={n ? 'accent' : 'neutral'} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ font: '600 14px/1.3 var(--font-sans)', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {p.guest ? 'Professional (' + p.name + ')' : p.name}</div>
                  <div style={{ font: '400 12px/1.3 var(--font-sans)', color: 'var(--gp-outline)', marginTop: 3 }}>{p.guest ? 'Professional guest' : p.position}</div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
                  <button type="button" onClick={() => bump(p.name, -1)} disabled={!n}
                    style={{ width: 30, height: 30, borderRadius: 15, border: '1.5px solid #CBD8C9', background: 'transparent', display: 'grid', placeItems: 'center', opacity: n ? 1 : .35, cursor: n ? 'pointer' : 'default' }}>
                    <Icon name="remove" size={15} color="var(--gp-primary-deep)" /></button>
                  <span style={{ minWidth: 14, textAlign: 'center', font: '700 15px/1 var(--font-sans)', color: n ? 'var(--gp-on-surface)' : 'var(--gp-outline)' }}>{n}</span>
                  <button type="button" onClick={() => bump(p.name, 1)}
                    style={{ width: 30, height: 30, borderRadius: 15, border: 'none', background: 'var(--status-open-bg)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                    <Icon name="add" size={15} color="var(--gp-primary-deep)" /></button>
                </div>
              </div>
            );
          })}
        </RowGroup>
        {mismatch ? (
          <div style={{ display: 'flex', gap: 9, marginTop: 10, padding: '11px 14px', background: 'var(--gp-error-container)', borderRadius: 'var(--radius-control)' }}>
            <Icon name="error" size={18} color="var(--gp-on-error-container)" />
            <span style={{ flex: 1, font: '400 12.5px/1.45 var(--font-sans)', color: 'var(--gp-on-error-container)' }}>
              Goalscorers add up to {scored}, but the score is {a + b}. Adjust one of them before saving.</span>
          </div>
        ) : null}
        <SectionHeading title="Player of the match" count="optional" style={{ padding: '18px 4px 9px' }} />
        <RowGroup>
          {all.slice(0, 4).map(p => (
            <div key={p.name} onClick={() => setMotm(motm === p.name ? null : p.name)}
              style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 16px', cursor: 'pointer',
                background: motm === p.name ? 'var(--status-open-bg)' : 'transparent' }}>
              <Icon name={motm === p.name ? 'star' : 'star_outline'} size={20} fill={motm === p.name}
                color={motm === p.name ? 'var(--gp-primary-deep)' : 'var(--gp-outline)'} />
              <span style={{ flex: 1, font: '500 14px/1.3 var(--font-sans)', color: 'var(--gp-on-surface)' }}>{p.guest ? 'Professional (' + p.name + ')' : p.name}</span>
              {motm === p.name ? <Chip tone="open" square>MOTM</Chip> : null}
            </div>
          ))}
        </RowGroup>
        <div style={{ padding: '16px 4px 0', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
          Saving the result closes the match and updates every participant's statistics and rating. Editing it later takes the old figures back first.</div>
      </TaskBody>
      <ActionBar>
        <Button fullWidth disabled={mismatch} onClick={() => { setToast('Match result saved.'); go('match', m); }}>Save result</Button>
      </ActionBar>
    </>
  );
}
window.ResultScreen = ResultScreen;
