const { Button, IconButton, Chip, MemberRow, SectionHeading, TextField, BottomSheet,
  ListRow, Divider, Icon, EmptyState } = window.GoPlayDesignSystem_984b89;
const { TaskBar, TaskBody, RowGroup } = window;

function MembersScreen({ go, community, setToast, review }) {
  const d = window.T(review);
  const base = community || d.communities[0];
  const role = (review && review.role) || base.role;
  const c = { ...base, role };
  const [q, setQ] = React.useState('');
  const [acting, setActing] = React.useState(null);
  const owner = role === 'Owner';
  const organizer = role !== 'Player';
  const list = d.members.filter(m => m.name.toLowerCase().includes(q.toLowerCase()));
  // A player can read the roster but never act on it, so the trailing column
  // is absent rather than disabled — a control nobody can use is still a
  // control somebody will try.
  const canAct = (m) => organizer && !m.you && m.role !== 'Owner' && (owner || m.role === 'Player');
  const alt = window.screenState(review, { empty: <EmptyState icon="person_search" message="This community has no members yet." /> });
  return (
    <>
      <TaskBar title="Members" onBack={() => go('community', c)}
        right={organizer ? <IconButton icon="person_add" label="Invite" onClick={() => go('invite', c)} /> : null} />
      <TaskBody style={{ padding: '12px 14px 20px' }}>
        {alt ? alt : <>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: 'var(--surface-card)',
          borderRadius: 'var(--radius-control)', boxShadow: 'var(--elevation-card)', padding: '0 14px', height: 46 }}>
          <Icon name="search" size={19} color="var(--gp-outline)" />
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search by name"
            style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', font: '400 15px/1 var(--font-sans)', color: 'var(--gp-on-surface)' }} />
        </div>
        <SectionHeading title={c.name} count={c.members + ' members'} style={{ padding: '18px 4px 9px' }} />
        {list.length ? (
          <RowGroup>
            {list.map(m => (
              <MemberRow key={m.name} {...m}
                trailing={<div style={{ display: 'flex', alignItems: 'center', gap: 4, flex: '0 0 auto' }}>
                  {m.role !== 'Player' ? <Chip tone={m.role === 'Owner' ? 'open' : 'role'} square>{m.role}</Chip> : null}
                  {canAct(m) ? <IconButton icon="more_vert" label={'Actions for ' + m.name} size={19} onClick={() => setActing(m)} /> : <span style={{ width: 8 }} />}
                </div>} />
            ))}
          </RowGroup>
        ) : <EmptyState icon="person_search" message="No players found." />}
        <div style={{ padding: '18px 4px 0', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
          {owner ? 'Only the owner can transfer ownership or change an admin. Removing a member also withdraws them from every match in this community.'
            : organizer ? 'Admins can promote and remove players. Only the owner can change another admin.'
            : 'Only the owner and admins can change who is in this community.'}</div></>}
      </TaskBody>
      {acting ? (
        <div onClick={() => setActing(null)} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.34)', display: 'flex', alignItems: 'flex-end', zIndex: 30 }}>
          <div style={{ width: '100%' }} onClick={e => e.stopPropagation()}>
            <BottomSheet title={acting.name}>
              <ListRow icon="person" title="View profile" onClick={() => setActing(null)} />
              {acting.role === 'Player'
                ? <ListRow icon="shield_person" title="Make admin" subtitle="Can create matches and manage the roster" onClick={() => { setActing(null); setToast('Member role updated.'); }} />
                : <ListRow icon="person" title="Make player" onClick={() => { setActing(null); setToast('Member role updated.'); }} />}
              {owner ? <ListRow icon="swap_horiz" title="Transfer ownership" subtitle="You become an admin" onClick={() => { setActing(null); setToast('Ownership transferred. You are now an admin.'); }} /> : null}
              <Divider tight />
              <ListRow icon="person_remove" title="Remove from community" danger onClick={() => { setActing(null); setToast('Member removed from the community.'); }} />
            </BottomSheet>
          </div>
        </div>
      ) : null}
    </>
  );
}
window.MembersScreen = MembersScreen;
