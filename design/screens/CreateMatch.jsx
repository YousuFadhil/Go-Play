const { Button, Icon, CapacityBar, Chip, CommunityLogo } = window.GoPlayDesignSystem_984b89;
const { TaskBar, TaskBody, RowGroup, FieldRow, ActionBar } = window;

function CreateMatchScreen({ go, community, setToast, review }) {
  const d = window.T(review);
  const c = community || d.communities[0];
  const [n, setN] = React.useState(12);
  const [saving, setSaving] = React.useState(false);
  const step = (v) => setN(Math.max(4, Math.min(30, n + v)));
  // The harness's error state stands in for a failed submit — the one failure
  // this screen can actually show a reader.
  const invalid = review && review.state === 'error';
  return (
    <>
      <TaskBar title="Create match" onBack={() => go('community', c)} />
      <TaskBody style={{ padding: '12px 14px 20px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 4px' }}>
          <CommunityLogo name={c.name} size={18} />
          <span style={{ font: '400 13px/1.3 var(--font-sans)', color: 'var(--gp-on-surface-variant)' }}>
            In <b style={{ color: 'var(--gp-on-surface)' }}>{c.name}</b> · {c.members} members will be notified</span>
        </div>
        <RowGroup>
          <FieldRow label="Match title" value={invalid ? '—' : d.matches[0].title} onClick={() => {}}
            error={invalid ? 'Match title is required.' : undefined} />
          <FieldRow label="Location" value={d.matches[0].location} onClick={() => {}} />
        </RowGroup>
        <RowGroup>
          <FieldRow icon="calendar_month" label="Date" value="Thursday, 13 August 2026" onClick={() => {}} />
          <FieldRow icon="schedule" label="Start" value="17:25" onClick={() => {}} />
          <FieldRow icon="schedule" label="End" value={invalid ? '17:00' : '18:35'} onClick={() => {}}
            error={invalid ? 'The end time must be after the start time.' : undefined} />
        </RowGroup>
        <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)', boxShadow: 'var(--elevation-card)', padding: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ font: '600 11.5px/1 var(--font-sans)', letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--gp-outline)' }}>Starting players</div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 6 }}>
                <span style={{ font: '700 30px/1 var(--font-sans)', letterSpacing: '-1.3px', color: 'var(--gp-primary-deep)' }}>{n}</span>
                <span style={{ font: '400 13px/1 var(--font-sans)', color: 'var(--gp-on-surface-variant)' }}>{n % 2 === 0 ? (n / 2) + ' a side' : 'uneven sides'}</span></div>
            </div>
            <button type="button" onClick={() => step(-2)} style={{ width: 40, height: 40, borderRadius: 20, border: '1.5px solid #CBD8C9', background: 'transparent', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
              <Icon name="remove" size={19} color="var(--gp-primary-deep)" /></button>
            <button type="button" onClick={() => step(2)} style={{ width: 40, height: 40, borderRadius: 20, border: 'none', background: 'var(--gp-primary-deep)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
              <Icon name="add" size={19} color="#fff" /></button>
          </div>
          <CapacityBar registered={0} starting={n} reserve={6} showLabel={false} style={{ marginTop: 15 }} />
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, font: '400 12px/1 var(--font-sans)', color: 'var(--gp-outline)' }}>
            <span><b style={{ color: 'var(--gp-on-surface)' }}>{n}</b> starting</span>
            <span><b style={{ color: 'var(--gp-on-surface)' }}>6</b> reserve · {n + 6} maximum</span></div>
        </div>
        <div style={{ padding: '0 4px', font: '400 12.5px/1.5 var(--font-sans)', color: 'var(--gp-outline)' }}>
          Reserve places are added automatically and cannot be entered by hand. Between 4 and 30 starting players.</div>
      </TaskBody>
      <ActionBar>
        <Button fullWidth loading={saving} disabled={invalid}
          onClick={() => { setSaving(true); setTimeout(() => { setSaving(false); setToast('Match created. Community members were notified.'); go('community', c); }, 700); }}>
          Create match</Button>
      </ActionBar>
    </>
  );
}
window.CreateMatchScreen = CreateMatchScreen;
