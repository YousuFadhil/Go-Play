const { Hero, HeroBar, Sheet, IconButton, Chip, SectionHeading, StatTile, CommunityLogo,
  SegmentedControl, ListRow, Icon, Avatar } = window.GoPlayDesignSystem_984b89;
const { RowGroup } = window;

function ProfileScreen({ go, review }) {
  const d = window.T(review);
  const [period, setPeriod] = React.useState('all');
  return (
    <>
      <Hero>
        <HeroBar title="Profile" onBack={() => go('home')} right={<IconButton icon="edit" label="Edit profile" onHero />} />
        <div style={{ padding: '0 18px', color: '#fff', display: 'flex', gap: 15, alignItems: 'center' }}>
          <Avatar name={d.me.name} size={62} style={{ background: 'rgba(255,255,255,.16)', color: '#fff', boxShadow: 'inset 0 0 0 2px rgba(255,255,255,.3)' }} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ font: '700 21px/1.2 var(--font-sans)', letterSpacing: '-.7px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{d.me.name}</div>
            <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
              <Chip tone="onHero">{d.me.position}</Chip>
              <Chip tone="onHero">{d.communities.length} communities</Chip></div>
          </div>
          <div style={{ textAlign: 'center', flex: '0 0 auto' }}>
            <div style={{ font: '700 30px/1 var(--font-sans)', letterSpacing: '-1.4px' }}>{d.me.rating}</div>
            <div style={{ font: '500 10px/1 var(--font-sans)', letterSpacing: '.08em', textTransform: 'uppercase', color: 'rgba(255,255,255,.7)', marginTop: 6 }}>Rating</div></div>
        </div>
      </Hero>
      <Sheet>
        <div style={{ padding: '8px 14px 0' }}>
          <SegmentedControl value={period} onChange={setPeriod}
            options={[{ value: 'week', label: 'This week' }, { value: 'month', label: 'This month' }, { value: 'all', label: 'All time' }]} />
        </div>
        <SectionHeading title="Record" />
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 9, padding: '0 14px' }}>
          {d.stats.map(s => <StatTile key={s.label} {...s} />)}
        </div>
        <SectionHeading title="Form" count="last 6" />
        <div style={{ padding: '0 14px' }}>
          <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)',
            padding: '14px 16px', display: 'flex', alignItems: 'flex-end', gap: 7, height: 76, boxSizing: 'border-box' }}>
            {d.me.form.map((v, i) => (
              <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
                <span style={{ width: '100%', height: (v / 5) * 40, borderRadius: 5, background: i === d.me.form.length - 1 ? 'var(--gp-primary-deep)' : '#CFE3D3' }} />
                <span style={{ font: '500 10px/1 var(--font-sans)', color: 'var(--gp-outline)' }}>{v.toFixed(1)}</span></div>
            ))}
          </div>
        </div>
        <SectionHeading title="Communities" count={d.communities.length} />
        <div style={{ padding: '0 14px' }}>
          <RowGroup>
            {d.communities.map(c => (
              <ListRow key={c.id} leading={<CommunityLogo name={c.name} size={38} />} title={c.name}
                subtitle={c.role + ' · ' + c.members + ' members'} chevron onClick={() => go('community', c)} />
            ))}
          </RowGroup>
        </div>
        <SectionHeading title="Account" />
        <div style={{ padding: '0 14px 92px' }}>
          <RowGroup>
            <ListRow icon="settings" title="Settings" chevron onClick={() => {}} />
            <ListRow icon="notifications" title="Notifications" chevron onClick={() => go('notifications')} />
            <ListRow icon="logout" title="Log out" onClick={() => {}} />
          </RowGroup>
        </div>
      </Sheet>
    </>
  );
}
window.ProfileScreen = ProfileScreen;
