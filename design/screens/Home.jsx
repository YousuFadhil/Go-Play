const { Hero, HeroBar, Sheet, IconButton, Avatar, Chip, Icon, Button, SectionHeading,
  MatchCard, CapacityBar, Card, EmptyState } = window.GoPlayDesignSystem_984b89;

function HomeScreen({ go, review }) {
  const d = window.T(review);
  const next = d.matches.find(m => m.next);
  const rest = d.matches.filter(m => !m.next);
  const alt = window.screenState(review);
  return (
    <>
      <Hero>
        <HeroBar right={<>
          <IconButton icon="notifications" label="Notifications" badge={d.notifications} onHero onClick={() => go('notifications')} />
          <span onClick={() => go('profile')} style={{ marginInlineEnd: 12, cursor: 'pointer' }}>
            <Avatar name={d.me.name} size={30} tone="neutral" style={{ background: 'rgba(255,255,255,.18)', color: '#fff' }} /></span></>} />
        <div style={{ padding: '0 18px 2px', color: '#fff' }}>
          <div style={{ font: '400 13px/1 var(--font-sans)', color: 'rgba(255,255,255,.7)' }}>Thursday 13 August</div>
          <div style={{ font: '700 24px/1.2 var(--font-sans)', letterSpacing: '-.8px', marginTop: 5 }}>Hello, Yousuf</div>
          <div style={{ display: 'flex', gap: 7, marginTop: 12 }}>
            <Chip tone="onHero" icon="groups">{d.communities.length} communities</Chip>
            <Chip tone="onHero" icon="sports_soccer">2 upcoming</Chip></div>
        </div>
      </Hero>
      <Sheet>
        {alt ? <div style={{ paddingTop: 14 }}>{alt}</div> : <>
        {next ? (
          <div style={{ padding: '6px 14px 0' }}>
            <Card outlined padded={false} onClick={() => go('match', next)}>
              <div style={{ padding: '14px 16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                  <span style={{ width: 7, height: 7, borderRadius: 4, background: 'var(--gp-primary-mid)' }} />
                  <span style={{ font: '700 11.5px/1 var(--font-sans)', letterSpacing: '.08em', textTransform: 'uppercase', color: 'var(--gp-primary)', whiteSpace: 'nowrap' }}>
                    Next up · in {next.inHours}h</span>
                  <span style={{ flex: 1 }} />
                  <Chip tone="open">You are in</Chip>
                </div>
                <div style={{ font: '700 19px/1.25 var(--font-sans)', letterSpacing: '-.4px', color: 'var(--gp-on-surface)', marginTop: 9 }}>{next.title}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 5, minWidth: 0, font: '400 13px/1.4 var(--font-sans)', color: 'var(--gp-on-surface-variant)' }}>
                  <Icon name="schedule" size={14} color="var(--gp-outline)" />
                  <span style={{ unicodeBidi: 'isolate', whiteSpace: 'nowrap', flex: '0 0 auto' }}>{next.time}</span>
                  <span style={{ opacity: .5, flex: '0 0 auto' }}>·</span>
                  <Icon name="place" size={14} color="var(--gp-outline)" style={{ flex: '0 0 auto' }} />
                  <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{next.location}</span></div>
                <CapacityBar registered={next.registered} starting={next.starting} reserve={next.reserve} style={{ marginTop: 12 }} />
                <div style={{ display: 'flex', gap: 8, marginTop: 13 }}>
                  <Button size="compact" style={{ flex: 1 }} onClick={() => go('match', next)}>Open match</Button>
                  <Button variant="outlined" size="compact" icon="ios_share" aria-label="Share" />
                </div>
              </div>
            </Card>
          </div>
        ) : null}
        <SectionHeading title="This week" count={rest.length} action="See all" />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9, padding: '0 14px' }}>
          {rest.length ? rest.map(m => (
            <MatchCard key={m.id} {...m} weekday={m.wd} day={m.d} month={m.mo} communityName={m.community} onClick={() => go('match', m)} />
          )) : <EmptyState icon="sports_soccer" tone="accent" message={'No upcoming matches.\nJoin a community to get started.'} />}
        </div></>}
        <div style={{ height: 92 }} />
      </Sheet>
    </>
  );
}
window.HomeScreen = HomeScreen;
