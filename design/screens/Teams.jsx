const { Button, IconButton, Chip, ParticipantRow, SectionHeading, SegmentedControl, Icon, Avatar, EmptyState } = window.GoPlayDesignSystem_984b89;
const { TaskBar, TaskBody, RowGroup } = window;

/** Teams and Arrange participants are one screen with two modes: both are the
 *  organizer moving people between two lists, and splitting them into separate
 *  screens made a player look up two different rosters for the same match. */
function TeamsScreen({ go, match, setToast, initial = 'teams', review }) {
  const d = window.T(review);
  const m = match || d.matches[0];
  const [mode, setMode] = React.useState(initial);
  const [picked, setPicked] = React.useState(null);

  const TeamPanel = ({ name, players, tone }) => (
    <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '11px 16px',
        background: tone === 'a' ? 'var(--gp-primary-deep)' : 'var(--gp-tertiary)', color: '#fff' }}>
        <span style={{ width: 24, height: 24, borderRadius: 7, background: 'rgba(255,255,255,.2)', display: 'grid', placeItems: 'center', font: '700 12px/1 var(--font-sans)' }}>
          {name.slice(-1)}</span>
        <span style={{ flex: 1, font: '700 14.5px/1 var(--font-sans)' }}>{name}</span>
        <span style={{ font: '500 12px/1 var(--font-sans)', opacity: .8 }}>{players.length} players</span>
      </div>
      {players.map((p, i) => (
        <div key={p.name} style={{ borderTop: i ? '1px solid var(--border-hairline)' : 'none' }}>
          <ParticipantRow {...p} /></div>
      ))}
    </div>
  );

  const ArrangeRow = ({ p, i, reserve }) => {
    const on = picked === p.name;
    return (
      <div onClick={() => setPicked(on ? null : on ? null : picked ? null : p.name)}
        style={{ background: on ? 'var(--status-open-bg)' : 'transparent', cursor: 'pointer' }}>
        <ParticipantRow {...p} index={i + 1} reserve={reserve} handle
          trailing={picked && !on
            ? <Button variant="tonal" size="small" onClick={(e) => { setPicked(null); setToast('Order updated.'); }}>Swap</Button>
            : <Chip tone="role" square>{reserve ? 'RES' : 'START'}</Chip>} />
      </div>
    );
  };

  return (
    <>
      <TaskBar title={mode === 'teams' ? 'Teams' : 'Arrange participants'} onBack={() => go('match', m)}
        right={mode === 'teams' ? <IconButton icon="ios_share" label="Share lineup" onClick={() => setToast('Lineup card ready to share.')} /> : null} />
      <div style={{ padding: '12px 14px 0', flex: '0 0 auto', background: 'var(--surface-sheet)' }}>
        <SegmentedControl value={mode} onChange={(v) => { setMode(v); setPicked(null); }}
          options={[{ value: 'teams', label: 'Teams' }, { value: 'arrange', label: 'Arrange' }]} />
      </div>
      <TaskBody style={{ padding: '0 14px 20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '14px 4px 0' }}>
          <Icon name="sports_soccer" size={16} color="var(--gp-outline)" />
          <span style={{ font: '400 12.5px/1.4 var(--font-sans)', color: 'var(--gp-on-surface-variant)' }}>
            {m.title} · {m.wd} {m.d} {m.mo}</span>
        </div>
        {mode === 'teams' ? (
          <>
            <SectionHeading title="Generated lineup" count="balanced" style={{ padding: '16px 4px 9px' }} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <TeamPanel name="Team A" players={d.teams.a} tone="a" />
              <TeamPanel name="Team B" players={d.teams.b} tone="b" />
            </div>
            <div style={{ padding: '16px 4px 0', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
              Teams are split from the confirmed players by rating and position. Regenerating replaces the current split.</div>
            <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
              <Button variant="outlined" size="compact" icon="autorenew" style={{ flex: 1 }} onClick={() => setToast('Teams generated.')}>Regenerate</Button>
              <Button size="compact" icon="ios_share" style={{ flex: 1 }} onClick={() => setToast('Lineup card ready to share.')}>Share</Button>
            </div>
          </>
        ) : (
          <>
            <div style={{ display: 'flex', alignItems: 'center', gap: 9, margin: '14px 0 0', padding: '11px 14px',
              background: picked ? 'var(--status-open-bg)' : 'var(--gp-surface-container)', borderRadius: 'var(--radius-control)' }}>
              <Icon name={picked ? 'swap_vert' : 'info'} size={18} color={picked ? 'var(--status-open-fg)' : 'var(--gp-outline)'} />
              <span style={{ flex: 1, font: '400 12.5px/1.45 var(--font-sans)', color: picked ? 'var(--status-open-fg)' : 'var(--gp-on-surface-variant)' }}>
                {picked ? picked + ' selected. Tap another participant to swap their places.' : 'Drag the handle to reorder a list. Tap a participant, then tap another to swap.'}</span>
              {picked ? <Button variant="text" size="small" onClick={() => setPicked(null)}>Cancel</Button> : null}
            </div>
            <SectionHeading title="Starting" count={d.roster.length + ' / ' + m.starting} style={{ padding: '16px 4px 9px' }} />
            <RowGroup>{d.roster.map((p, i) => <ArrangeRow key={p.name} p={p} i={i} />)}</RowGroup>
            <SectionHeading title="Reserve" count={d.reserve.length} style={{ padding: '16px 4px 9px' }} />
            <RowGroup>{d.reserve.map((p, i) => <ArrangeRow key={p.name} p={p} i={i} reserve />)}</RowGroup>
            <div style={{ padding: '16px 4px 0', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
              Players start in the order they joined, with professional guests after them. Your first change makes your own order the one that counts.</div>
          </>
        )}
      </TaskBody>
    </>
  );
}
window.TeamsScreen = TeamsScreen;
