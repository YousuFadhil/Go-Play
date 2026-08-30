const { Hero, HeroBar, Sheet, IconButton, Chip, Button, SectionHeading, ParticipantRow,
  CapacityBar, Card, Dialog, Icon, EmptyState } = window.GoPlayDesignSystem_984b89;
const { OwnerLine, HeroFacts } = window;

function MatchDetailsScreen({ go, match, setToast, review }) {
  const d = window.T(review);
  const m = match || d.matches[0];
  const reg = (review && review.reg) || 'confirmed';
  const [joined, setJoined] = React.useState(reg !== 'none');
  const [onReserve, setOnReserve] = React.useState(reg === 'reserve');
  React.useEffect(() => { setJoined(reg !== 'none'); setOnReserve(reg === 'reserve'); }, [reg]);
  const [confirm, setConfirm] = React.useState(false);
  const done = m.status === 'completed';
  const organizer = (review && review.role ? review.role : m.role) !== 'Player';
  const wouldReserve = !joined && m.registered >= m.starting;
  const alt = window.screenState(review, { skeleton: <window.MatchListSkeleton rows={3} /> });

  return (
    <>
      <Hero>
        <HeroBar title="Match" onBack={() => go('home')}
          right={organizer ? <IconButton icon="settings" label="Match management" onHero /> : null} />
        <div style={{ padding: '0 18px', color: '#fff' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <OwnerLine community={m.community} role={m.role} onHero />
            <Chip tone={done ? 'completed' : m.status}>{done ? 'Played' : m.status === 'full' ? 'Full' : 'Open'}</Chip>
          </div>
          <div style={{ font: '700 23px/1.2 var(--font-sans)', letterSpacing: '-.8px', marginTop: 9 }}>{m.title}</div>
          <HeroFacts items={[['calendar_month', m.wd + ' ' + m.d + ' ' + m.mo], ['schedule', m.time], ['place', m.location]]} />
        </div>
      </Hero>
      <Sheet>
        {alt ? <div style={{ paddingTop: 14 }}>{alt}</div> : <>
        <div style={{ padding: '6px 14px 0', display: 'flex', flexDirection: 'column', gap: 10 }}>
          {done ? (
            <Card style={{ background: 'var(--gp-primary-deep)', color: '#fff' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                <div style={{ flex: 1 }}>
                  <div style={{ font: '500 10.5px/1 var(--font-sans)', letterSpacing: '.08em', textTransform: 'uppercase', color: 'rgba(255,255,255,.7)' }}>Final score</div>
                  <div style={{ font: '700 30px/1 var(--font-sans)', letterSpacing: '-1.2px', marginTop: 8 }}>{m.score}</div>
                  <div style={{ font: '400 12.5px/1 var(--font-sans)', color: 'rgba(255,255,255,.75)', marginTop: 7 }}>Team A won · you played</div>
                </div>
                <Button variant="onHero" size="small" onClick={() => go('result', m)}>Result</Button>
              </div>
            </Card>
          ) : (
            <Card outlined padded={false}>
              <div style={{ padding: '13px 16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <Icon name={onReserve ? 'hourglass_top' : joined ? 'check_circle' : 'group'} size={20} fill={joined}
                    color={onReserve ? 'var(--gp-tertiary)' : joined ? 'var(--gp-primary-deep)' : 'var(--gp-outline)'} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ font: '700 14.5px/1.25 var(--font-sans)', color: 'var(--gp-on-surface)' }}>
                      {onReserve ? 'You are on the reserve list' : joined ? 'You have a confirmed place'
                        : wouldReserve ? 'This match is full' : m.registered + ' of ' + m.starting + ' places filled'}</div>
                    <div style={{ font: '400 12.5px/1.35 var(--font-sans)', color: 'var(--gp-on-surface-variant)', marginTop: 3 }}>
                      {onReserve ? 'Position 1. You take the first place that opens up.'
                        : joined ? m.registered + ' of ' + m.starting + ' places filled · ' + d.reserve.length + ' on the reserve list'
                        : wouldReserve ? 'Joining now adds you to the reserve list.' : (m.starting - m.registered) + ' places left'}</div>
                  </div>
                </div>
                <CapacityBar registered={m.registered} starting={m.starting} reserve={m.reserve} status={m.status} showLabel={false} style={{ marginTop: 12 }} />
                <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 7, font: '400 11.5px/1 var(--font-sans)', color: 'var(--gp-outline)' }}>
                  <span><b style={{ color: 'var(--gp-on-surface)' }}>{m.registered}</b> of {m.starting} starting</span>
                  <span>{d.reserve.length} of {m.reserve} reserve</span></div>
                <div style={{ marginTop: 13 }}>
                  {joined
                    ? <Button variant="outlined" size="compact" fullWidth onClick={() => setConfirm(true)}>{onReserve ? 'Leave the reserve list' : 'Withdraw'}</Button>
                    : <Button size="compact" fullWidth onClick={() => { setJoined(true); setToast(wouldReserve ? 'The match is full. You were added to the reserve list.' : 'You joined the match.'); }}>
                        {wouldReserve ? 'Join the reserve list' : 'Join match'}</Button>}
                </div>
              </div>
            </Card>
          )}
          {organizer ? (
            <div style={{ display: 'flex', gap: 8 }}>
              <Button variant="tonal" size="compact" icon="group" style={{ flex: 1 }} onClick={() => go('teams', m)}>Teams</Button>
              <Button variant="tonal" size="compact" icon="scoreboard" style={{ flex: 1 }} onClick={() => go('result', m)}>{done ? 'Edit result' : 'Enter result'}</Button>
            </div>
          ) : null}
        </div>
        <SectionHeading title="Starting" count={d.roster.length + ' / ' + m.starting}
          action={organizer ? 'Arrange' : undefined} onAction={() => go('arrange', m)} />
        <div style={{ padding: '0 14px' }}>
          <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', overflow: 'hidden' }}>
            {d.roster.map((p, i) => (
              <div key={p.name + i} style={{ borderTop: i ? '1px solid var(--border-hairline)' : 'none' }}><ParticipantRow {...p} /></div>
            ))}
          </div>
        </div>
        <SectionHeading title="Reserve" count={d.reserve.length} />
        <div style={{ padding: '0 14px 92px' }}>
          <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', overflow: 'hidden' }}>
            {d.reserve.length ? d.reserve.map((p, i) => (
              <div key={p.name} style={{ borderTop: i ? '1px solid var(--border-hairline)' : 'none' }}>
                <ParticipantRow {...p} reserve index={i + 1} trailing={<Chip tone="reserve">Next in</Chip>} /></div>
            )) : <EmptyState icon="hourglass_empty" message="Nobody is on the reserve list." />}
          </div>
        </div></>}
      </Sheet>
      {confirm ? (
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.34)', display: 'grid', placeItems: 'center', padding: 16, zIndex: 30 }}>
          <Dialog title="Withdraw from this match?" body="If you have a confirmed seat, the first reserve will take your place."
            cancelLabel="Back" confirmLabel="Withdraw" destructive onCancel={() => setConfirm(false)}
            onConfirm={() => { setConfirm(false); setJoined(false); setToast('You withdrew from the match.'); }} />
        </div>
      ) : null}
    </>
  );
}
window.MatchDetailsScreen = MatchDetailsScreen;
