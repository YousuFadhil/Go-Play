const { Hero, HeroBar, Sheet, IconButton, CommunityLogo, Chip, Button, SectionHeading,
  MatchCard, MemberRow, EmptyState, BottomSheet, ListRow, Divider, Icon } = window.GoPlayDesignSystem_984b89;

function CommunityDetailsScreen({ go, community, review }) {
  const d = window.T(review);
  const base = community || d.communities[0];
  const c = { ...base, role: (review && review.role) || base.role };
  const [sheet, setSheet] = React.useState(false);
  const [tab, setTab] = React.useState('upcoming');
  const mine = d.matches.filter(m => m.community === c.name);
  const shown = mine.filter(m => tab === 'upcoming' ? m.status !== 'completed' : m.status === 'completed');
  const organizer = c.role === 'Admin' || c.role === 'Owner';
  const alt = window.screenState(review, { empty: <EmptyState icon="sports_soccer" message="No matches in this community yet." /> });
  const Tab = ({ v, label, n }) => (
    <button type="button" onClick={() => setTab(v)} style={{ border: 'none', background: 'transparent', cursor: 'pointer',
      padding: '0 0 9px', font: (tab === v ? 700 : 500) + ' 14px/1 var(--font-sans)', whiteSpace: 'nowrap',
      color: tab === v ? 'var(--gp-on-surface)' : 'var(--gp-outline)',
      borderBottom: '2.5px solid ' + (tab === v ? 'var(--gp-primary-deep)' : 'transparent') }}>
      {label}<span style={{ color: 'var(--gp-outline)', fontWeight: 500, unicodeBidi: 'isolate' }}> · {n}</span></button>
  );
  return (
    <>
      <Hero>
        <HeroBar onBack={() => go('communities')} right={<IconButton icon="more_vert" label="Community actions" onHero onClick={() => setSheet(true)} />} />
        <div style={{ padding: '0 18px', color: '#fff', display: 'flex', gap: 14, alignItems: 'center' }}>
          <CommunityLogo name={c.name} size={58} onHero />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ font: '700 22px/1.2 var(--font-sans)', letterSpacing: '-.7px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.name}</span>
              {c.role !== 'Player' ? <Chip tone="onHero" square>{c.role}</Chip> : null}
            </div>
            <div style={{ font: '400 12.5px/1.4 var(--font-sans)', color: 'rgba(255,255,255,.75)', marginTop: 4 }}>{c.description}</div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 18, padding: '14px 18px 0', color: '#fff' }}>
          {[[c.members, 'Members'], [c.upcoming, 'Upcoming'], [c.played, 'Played']].map(([v, l]) => (
            <div key={l} style={{ display: 'flex', alignItems: 'baseline', gap: 5 }}>
              <span style={{ font: '700 17px/1 var(--font-sans)' }}>{v}</span>
              <span style={{ font: '400 12px/1 var(--font-sans)', color: 'rgba(255,255,255,.7)', whiteSpace: 'nowrap' }}>{l}</span></div>
          ))}
        </div>
        {organizer ? (
          <div style={{ display: 'flex', gap: 8, padding: '14px 18px 0' }}>
            <Button variant="onHero" size="compact" icon="add" style={{ flex: 1 }} onClick={() => go('create', c)}>Create match</Button>
            <Button variant="ghost" size="compact" icon="person_add" onClick={() => go('invite', c)}>Invite</Button>
          </div>
        ) : (
          <div style={{ padding: '14px 18px 0' }}><Button variant="onHero" size="compact" fullWidth>Join community</Button></div>
        )}
      </Hero>
      <Sheet>
        <div style={{ display: 'flex', gap: 20, padding: '12px 18px 0', borderBottom: '1px solid var(--border-hairline)', margin: '0 0 4px' }}>
          <Tab v="upcoming" label="Matches" n={mine.filter(m => m.status !== 'completed').length} />
          <Tab v="past" label="Played" n={mine.filter(m => m.status === 'completed').length} />
        </div>
        {alt ? <div style={{ paddingTop: 12 }}>{alt}</div> : <>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9, padding: '10px 14px 0' }}>
          {shown.length ? shown.map(m => (
            <MatchCard key={m.id} {...m} weekday={m.wd} day={m.d} month={m.mo} onClick={() => go('match', m)} />
          )) : <EmptyState icon="sports_soccer" message="No matches in this community yet." />}
        </div>
        <SectionHeading title="Members" count={c.members} action={organizer ? 'Manage' : undefined} onAction={() => go('members', c)} />
        <div style={{ padding: '0 14px 92px' }}>
          <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', overflow: 'hidden' }}>
            {d.members.slice(0, 3).map((m, i) => (
              <div key={m.name} style={{ borderTop: i ? '1px solid var(--border-hairline)' : 'none' }}>
                <MemberRow {...m} trailing={m.role !== 'Player' ? <Chip tone="role" square>{m.role}</Chip> : null} /></div>
            ))}
            <div style={{ borderTop: '1px solid var(--border-hairline)', padding: '11px 16px', textAlign: 'center',
              font: '600 13.5px/1 var(--font-sans)', color: 'var(--gp-primary)', cursor: 'pointer' }} onClick={() => go('members', c)}>
              See all {c.members} members</div>
          </div>
        </div></>}
      </Sheet>
      {sheet ? (
        <div onClick={() => setSheet(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.34)', display: 'flex', alignItems: 'flex-end', zIndex: 30 }}>
          <div style={{ width: '100%' }} onClick={e => e.stopPropagation()}>
            <BottomSheet title={c.name}>
              {organizer ? <ListRow icon="ios_share" title="Share invitation" subtitle={'Join code ' + (c.code || '—')} onClick={() => { setSheet(false); go('invite', c); }} /> : null}
              {c.role === 'Owner' ? <ListRow icon="lock_open" title="Joining" subtitle={c.joinPolicy} onClick={() => setSheet(false)} /> : null}
              <ListRow icon="group" title="Manage members" onClick={() => { setSheet(false); go('members', c); }} />
              <ListRow icon="logout" title="Leave community" onClick={() => setSheet(false)} />
              {c.role === 'Owner' ? <><Divider tight /><ListRow icon="delete" title="Delete community" danger onClick={() => setSheet(false)} /></> : null}
            </BottomSheet>
          </div>
        </div>
      ) : null}
    </>
  );
}
window.CommunityDetailsScreen = CommunityDetailsScreen;
