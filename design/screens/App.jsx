const { BottomNav, Snackbar, Hero, HeroBar, Sheet, IconButton, SectionHeading, CommunityLogo,
  Chip, Button, ListRow, Icon, MatchCard, EmptyState, Avatar } = window.GoPlayDesignSystem_984b89;
const { TaskBar, TaskBody, RowGroup } = window;

function DiscoverScreen({ go, review }) {
  const d = window.T(review);
  return (
    <>
      <Hero>
        <HeroBar right={<IconButton icon="search" label="Search" onHero />} />
        <div style={{ padding: '0 18px', color: '#fff' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            <span style={{ width: 28, height: 28, borderRadius: 14, background: '#fff', display: 'grid', placeItems: 'center' }}>
              <Icon name="sports_soccer" size={17} fill color="var(--gp-primary-deep)" /></span>
            <span style={{ font: '700 16px/1 var(--font-sans)', letterSpacing: '.2px' }}>Go Play</span></div>
          <div style={{ font: '700 23px/1.2 var(--font-sans)', letterSpacing: '-.8px', marginTop: 12 }}>Football, with your people.</div>
          <div style={{ font: '400 13px/1.45 var(--font-sans)', color: 'rgba(255,255,255,.78)', marginTop: 5 }}>
            Find a community near you and take your place on the pitch.</div>
          <div style={{ display: 'flex', gap: 7, marginTop: 12 }}>
            <Chip tone="onHero" icon="groups">{d.communities.length} communities</Chip>
            <Chip tone="onHero" icon="sports_soccer">2 upcoming</Chip></div>
        </div>
      </Hero>
      <Sheet>
        <SectionHeading title="Open matches" count={2} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9, padding: '0 14px' }}>
          {d.matches.filter(m => m.status !== 'completed').map(m => (
            <MatchCard key={m.id} {...m} weekday={m.wd} day={m.d} month={m.mo} communityName={m.community} onClick={() => go('match', m)} />
          ))}
        </div>
        <SectionHeading title="Communities" count={d.communities.length} />
        <div style={{ padding: '0 14px 92px' }}>
          <RowGroup>
            {d.communities.map(c => (
              <ListRow key={c.id} leading={<CommunityLogo name={c.name} size={40} />} title={c.name}
                subtitle={c.members + ' members · ' + c.upcoming + ' upcoming'}
                trailing={<Button variant="tonal" size="small" onClick={() => go('community', c)}>Open</Button>}
                onClick={() => go('community', c)} />
            ))}
          </RowGroup>
        </div>
      </Sheet>
    </>
  );
}

function CommunitiesScreen({ go, review }) {
  const d = window.T(review);
  return (
    <>
      <Hero>
        <HeroBar right={<IconButton icon="add" label="Create community" onHero />} />
        <div style={{ padding: '0 18px', color: '#fff' }}>
          <div style={{ font: '700 23px/1.2 var(--font-sans)', letterSpacing: '-.8px' }}>Your communities</div>
          <div style={{ font: '400 13px/1.45 var(--font-sans)', color: 'rgba(255,255,255,.75)', marginTop: 5 }}>
            You organize one and play in another.</div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <Button variant="onHero" size="compact" icon="add" style={{ flex: 1 }}>Create</Button>
            <Button variant="ghost" size="compact" icon="key">Join by code</Button></div>
        </div>
      </Hero>
      <Sheet>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '10px 14px 92px' }}>
          {d.communities.map(c => (
            <div key={c.id} onClick={() => go('community', c)}
              style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', padding: 14, cursor: 'pointer' }}>
              <div style={{ display: 'flex', gap: 13, alignItems: 'center' }}>
                <CommunityLogo name={c.name} size={48} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                    <span style={{ flex: 1, minWidth: 0, font: '700 16px/1.3 var(--font-sans)', letterSpacing: '-.2px', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.name}</span>
                    {c.codeRequired ? <Icon name="key" size={14} color="var(--gp-outline)" /> : null}
                    {c.role !== 'Player' ? <Chip tone="role" square>{c.role}</Chip> : null}</div>
                  <div style={{ font: '400 12.5px/1.4 var(--font-sans)', color: 'var(--gp-on-surface-variant)', marginTop: 3 }}>{c.description}</div>
                  <div style={{ display: 'flex', gap: 14, marginTop: 7, font: '400 12px/1 var(--font-sans)', color: 'var(--gp-outline)' }}>
                    <span style={{ display: 'inline-flex', gap: 5, alignItems: 'center', whiteSpace: 'nowrap' }}><Icon name="person" size={13} /><span style={{ unicodeBidi: 'plaintext' }}>{c.members} members</span></span>
                    <span style={{ display: 'inline-flex', gap: 5, alignItems: 'center', whiteSpace: 'nowrap' }}><Icon name="sports_soccer" size={13} /><span style={{ unicodeBidi: 'plaintext' }}>{c.upcoming} upcoming</span></span></div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </Sheet>
    </>
  );
}

function NotificationsScreen({ go, review }) {
  const items = [
    { icon: 'group_add', title: 'You were promoted from the reserve list to the starting players.', when: 'Thursday practice · 2h ago', unread: true },
    { icon: 'schedule', title: 'The match time has changed.', when: 'Friday five-a-side · yesterday', unread: true },
    { icon: 'scoreboard', title: 'The match result was saved.', when: 'Sunday league · 2 days ago', unread: true },
    { icon: 'groups', title: 'You have been invited to a community.', when: 'Al Bahar · 3 days ago' },
  ];
  return (
    <>
      <TaskBar title="Notifications" onBack={() => go('home')} right={<Button variant="text" size="small">Mark all read</Button>} />
      <TaskBody style={{ padding: '12px 14px 20px' }}>
        <RowGroup>
          {items.map((n, i) => (
            <div key={i} style={{ display: 'flex', gap: 13, padding: '13px 16px', background: n.unread ? 'rgba(220,238,223,.35)' : 'transparent' }}>
              <span style={{ width: 34, height: 34, borderRadius: 17, flex: '0 0 auto', background: 'var(--status-open-bg)', display: 'grid', placeItems: 'center' }}>
                <Icon name={n.icon} size={18} color="var(--gp-primary-deep)" /></span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ font: (n.unread ? 600 : 400) + ' 14px/1.4 var(--font-sans)', color: 'var(--gp-on-surface)' }}>{n.title}</div>
                <div style={{ font: '400 12px/1.3 var(--font-sans)', color: 'var(--gp-outline)', marginTop: 4 }}>{n.when}</div></div>
              {n.unread ? <span style={{ width: 8, height: 8, borderRadius: 4, background: 'var(--gp-primary-mid)', marginTop: 6, flex: '0 0 auto' }} /> : null}
            </div>
          ))}
        </RowGroup>
      </TaskBody>
    </>
  );
}

const TABS = [
  { value: 'discover', label: 'Discover', icon: 'explore' },
  { value: 'home', label: 'Home', icon: 'home' },
  { value: 'communities', label: 'Communities', icon: 'groups' },
];
/** Screens that are a task rather than a place drop the bottom nav. */
const TASKS = ['create', 'members', 'teams', 'arrange', 'result', 'notifications'];

/** The review harness. Not part of the product — it is how a reviewer or a
 *  Flutter engineer reaches the states and roles the design has to cover
 *  without needing a backend to produce them. */
function ReviewBar({ review, set }) {
  const Group = ({ label, k, opts }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <span style={{ font: '600 10px/1 var(--font-sans)', letterSpacing: '.08em', textTransform: 'uppercase', color: '#7C857B' }}>{label}</span>
      <div style={{ display: 'flex', background: '#fff', borderRadius: 8, padding: 2, boxShadow: 'var(--elevation-card)' }}>
        {opts.map(([v, l]) => (
          <button key={v} type="button" onClick={() => set(k, v)}
            style={{ border: 'none', cursor: 'pointer', padding: '5px 9px', borderRadius: 6,
              background: review[k] === v ? 'var(--gp-primary-deep)' : 'transparent',
              color: review[k] === v ? '#fff' : '#5D6A5E', font: '600 11px/1 var(--font-sans)' }}>{l}</button>
        ))}
      </div>
    </div>
  );
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 14, justifyContent: 'center', alignItems: 'center', padding: '10px 12px' }}>
      <Group label="Role" k="role" opts={[['Owner', 'Owner'], ['Admin', 'Admin'], ['Player', 'Player']]} />
      <Group label="State" k="state" opts={[['ready', 'Populated'], ['loading', 'Loading'], ['empty', 'Empty'], ['error', 'Error']]} />
      <Group label="You" k="reg" opts={[['confirmed', 'Confirmed'], ['reserve', 'Reserve'], ['none', 'Not in']]} />
      <Group label="Dir" k="dir" opts={[['ltr', 'EN'], ['rtl', 'العربية']]} />
      <Group label="Width" k="w" opts={[[320, '320'], [412, '412'], [480, '480']]} />
    </div>
  );
}

function App() {
  const [screen, setScreen] = React.useState('home');
  const [review, setReview] = React.useState({ role: 'Admin', state: 'ready', reg: 'confirmed', dir: 'ltr', w: 412 });
  const setR = (k, v) => setReview(r => ({ ...r, [k]: v }));
  const [community, setCommunity] = React.useState(null);
  const [match, setMatch] = React.useState(null);
  const [toast, setToast] = React.useState(null);
  const scroller = React.useRef(null);

  React.useEffect(() => { if (scroller.current) scroller.current.scrollTop = 0; }, [screen]);
  React.useEffect(() => { if (!toast) return; const t = setTimeout(() => setToast(null), 3200); return () => clearTimeout(t); }, [toast]);

  const go = (next, payload) => {
    if (payload && payload.members != null) setCommunity(payload);
    if (payload && payload.starting != null) setMatch(payload);
    setScreen(next);
  };
  const tab = TABS.some(t => t.value === screen) ? screen
    : ['community', 'members', 'create', 'invite', 'landing'].includes(screen) ? 'communities' : 'home';

  const p = { go, review, setToast };
  const body = {
    discover: <DiscoverScreen {...p} />,
    home: <window.HomeScreen {...p} />,
    communities: <CommunitiesScreen {...p} />,
    community: <window.CommunityDetailsScreen {...p} community={community} />,
    match: <window.MatchDetailsScreen {...p} match={match} />,
    create: <window.CreateMatchScreen {...p} community={community} />,
    profile: <window.ProfileScreen {...p} />,
    members: <window.MembersScreen {...p} community={community} />,
    invite: <window.InviteScreen {...p} community={community} mode="share" />,
    landing: <window.InviteScreen {...p} community={community} mode="landing" />,
    teams: <window.TeamsScreen {...p} match={match} initial="teams" />,
    arrange: <window.TeamsScreen {...p} match={match} initial="arrange" />,
    result: <window.ResultScreen {...p} match={match} />,
    notifications: <NotificationsScreen {...p} />,
  }[screen];

  const isTask = TASKS.includes(screen);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
      <ReviewBar review={review} set={setR} />
      <div className="gp-phone" ref={scroller} dir={review.dir}
        style={{ width: review.w, fontFamily: review.dir === 'rtl' ? 'var(--font-arabic)' : 'var(--font-sans)' }}>
        {body}
        {toast ? <div style={{ position: 'absolute', insetInline: 0, bottom: isTask ? 76 : 82, zIndex: 40 }}><Snackbar>{toast}</Snackbar></div> : null}
        {!isTask ? <BottomNav items={TABS} value={tab} onChange={(v) => setScreen(v)} /> : null}
      </div>
    </div>
  );
}
window.GoPlayApp = App;
