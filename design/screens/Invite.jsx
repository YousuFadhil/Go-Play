const { Hero, HeroBar, Sheet, CommunityLogo, Chip, Button, Icon, SectionHeading, MatchCard, IconButton } = window.GoPlayDesignSystem_984b89;
const { RowGroup } = window;

/** Two readings of one screen: the organizer sharing an invitation, and the
 *  person who has just opened the link. `mode` decides which. */
function InviteScreen({ go, community, mode = 'share', setToast, review }) {
  const d = window.T(review);
  const c = community || d.communities[0];
  const link = 'goplay.app/join/' + (c.code || '481902').replace(/\s/g, '');
  const visitor = mode === 'landing';
  return (
    <>
      <Hero>
        <HeroBar title={visitor ? 'Invitation' : 'Share invitation'} onBack={() => go(visitor ? 'discover' : 'community', c)} />
        <div style={{ padding: '0 18px', color: '#fff', textAlign: visitor ? 'center' : 'start' }}>
          <div style={{ display: 'flex', flexDirection: visitor ? 'column' : 'row', alignItems: 'center', gap: visitor ? 12 : 14 }}>
            <CommunityLogo name={c.name} size={visitor ? 66 : 52} onHero />
            <div style={{ flex: visitor ? undefined : 1, minWidth: 0, textAlign: visitor ? 'center' : 'start' }}>
              {visitor ? <div style={{ font: '400 13px/1 var(--font-sans)', color: 'rgba(255,255,255,.72)' }}>You have been invited to</div> : null}
              <div style={{ font: '700 22px/1.2 var(--font-sans)', letterSpacing: '-.7px', marginTop: visitor ? 6 : 0 }}>{c.name}</div>
              <div style={{ font: '400 12.5px/1.4 var(--font-sans)', color: 'rgba(255,255,255,.75)', marginTop: 4 }}>{c.description}</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 7, marginTop: 13, justifyContent: visitor ? 'center' : 'flex-start' }}>
            <Chip tone="onHero" icon="group">{c.members} members</Chip>
            <Chip tone="onHero" icon="sports_soccer">{c.upcoming} upcoming</Chip>
          </div>
        </div>
      </Hero>
      <Sheet>
        {visitor ? (
          <>
            <div style={{ padding: '10px 14px 0' }}>
              <Button fullWidth onClick={() => { setToast('You joined the community.'); go('community', c); }}>Join community</Button>
              <div style={{ textAlign: 'center', padding: '12px 0 0', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
                Joining puts you in the community. Matches are browsed afterwards — you register for each one yourself.</div>
            </div>
            <SectionHeading title="What is coming up" count={c.upcoming} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9, padding: '0 14px 24px' }}>
              {d.matches.filter(m => m.community === c.name && m.status !== 'completed').map(m => (
                <MatchCard key={m.id} {...m} weekday={m.wd} day={m.d} month={m.mo} />
              ))}
            </div>
          </>
        ) : (
          <>
            <div style={{ padding: '10px 14px 0', display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', padding: '18px 16px', textAlign: 'center' }}>
                <div style={{ font: '600 11.5px/1 var(--font-sans)', letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--gp-outline)' }}>Join code</div>
                <div dir="ltr" style={{ font: '700 34px/1 var(--font-sans)', letterSpacing: '6px', color: 'var(--gp-primary-deep)', marginTop: 12 }}>{c.code}</div>
                <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
                  <Button size="compact" icon="ios_share" style={{ flex: 1 }} onClick={() => setToast('Invitation copied. Paste it wherever you share it.')}>Share link</Button>
                  <Button variant="outlined" size="compact" icon="content_copy" onClick={() => setToast('Join code copied')}>Copy code</Button>
                </div>
              </div>
              <RowGroup>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px' }}>
                  <Icon name="link" size={19} color="var(--gp-outline)" />
                  <span dir="ltr" style={{ flex: 1, minWidth: 0, font: '400 14px/1.3 var(--font-sans)', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', textAlign: 'start' }}>{link}</span>
                  <Button variant="text" size="small" onClick={() => setToast('Invitation copied. Paste it wherever you share it.')}>Copy</Button>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px' }}>
                  <Icon name="lock_open" size={19} color="var(--gp-outline)" />
                  <div style={{ flex: 1 }}><div style={{ font: '400 14px/1.3 var(--font-sans)', color: 'var(--gp-on-surface)' }}>Joining</div>
                    <div style={{ font: '400 12px/1.3 var(--font-sans)', color: 'var(--gp-outline)', marginTop: 3 }}>{c.joinPolicy}</div></div>
                  <Icon name="chevron_right" size={19} color="#BFC9BE" />
                </div>
              </RowGroup>
              <div style={{ padding: '0 4px', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
                Anyone with this link or code can join the community. Both carry the same code.</div>
              <Button variant="outlined" fullWidth icon="autorenew" onClick={() => setToast('New code issued. The old one no longer works.')}>Regenerate code</Button>
              <div style={{ padding: '0 4px 24px', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
                The current link and code stop working immediately, so anyone still holding them cannot join. People already in the community stay members.</div>
            </div>
          </>
        )}
      </Sheet>
    </>
  );
}
window.InviteScreen = InviteScreen;
