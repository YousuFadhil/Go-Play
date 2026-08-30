const { Icon, CommunityLogo, Chip, Button, IconButton, Skeleton, ErrorState, EmptyState } = window.GoPlayDesignSystem_984b89;

/** The placeholder a match list shows while it loads. Shaped like the cards it
 *  is standing in for, so the page does not jump when the data lands. */
function MatchListSkeleton({ rows = 2 }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 9, padding: '0 14px' }}>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)',
          boxShadow: 'var(--elevation-card)', padding: '12px 16px', display: 'flex', gap: 12 }}>
          <Skeleton width={50} height={56} radius="14px" />
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8, paddingTop: 2 }}>
            <Skeleton width="70%" height={15} radius="6px" />
            <Skeleton width="45%" height={11} radius="5px" />
            <Skeleton width="90%" height={11} radius="5px" />
            <Skeleton height={5} radius="3px" />
          </div>
        </div>
      ))}
    </div>
  );
}

/** Reads the review harness and returns the non-populated body a screen should
 *  render instead of its content, or null when the screen should render
 *  normally. One place, so loading and failure look the same everywhere. */
function screenState(review, { skeleton, empty, onRetry } = {}) {
  const s = review && review.state;
  if (s === 'loading') return skeleton || <MatchListSkeleton />;
  if (s === 'error') return <ErrorState onRetry={onRetry} />;
  if (s === 'empty') return empty || <EmptyState icon="sports_soccer" tone="accent" message={'No upcoming matches.\nJoin a community to get started.'} />;
  return null;
}

/** The light page a task screen sits on. A place screen gets this from Sheet;
 *  a task screen has no Sheet, so it paints its own — without it the phone's
 *  deep-green base shows through everything between the cards. */
function TaskBody({ children, style }) {
  return (
    <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', background: 'var(--surface-sheet)', ...style }}>
      {children}
    </div>
  );
}

/** A screen that is a task, not a place: plain white bar, no bottom nav. */
function TaskBar({ title, onBack, right }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4, minHeight: 54, padding: '0 6px',
      background: 'var(--surface-card)', borderBottom: '1px solid var(--border-hairline)', flex: '0 0 auto' }}>
      {onBack ? <IconButton icon="arrow_back" label="Back" onClick={onBack} /> : <span style={{ width: 12 }} />}
      <span style={{ flex: 1, minWidth: 0, font: '700 17px/1.25 var(--font-sans)', letterSpacing: '-.2px',
        color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</span>
      {right}
    </div>
  );
}

/** The community line every match-side screen carries: crest, name, role. */
function OwnerLine({ community, role, onHero }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
      <CommunityLogo name={community} size={18} onHero={onHero} />
      <span style={{ font: '600 12.5px/1 var(--font-sans)', color: onHero ? 'rgba(255,255,255,.85)' : 'var(--gp-primary)' }}>{community}</span>
      {role && role !== 'Player' ? <Chip tone={onHero ? 'onHero' : 'role'} square>{role}</Chip> : null}
    </div>
  );
}

/** A row of facts on the hero, under the title. */
function HeroFacts({ items }) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px 16px', marginTop: 10 }}>
      {items.map(([ic, t]) => (
        <span key={t} style={{ display: 'inline-flex', alignItems: 'center', gap: 6,
          font: '400 12.5px/1.3 var(--font-sans)', color: 'rgba(255,255,255,.8)',
          unicodeBidi: 'plaintext', whiteSpace: 'nowrap' }}>
          <Icon name={ic} size={14} />{t}</span>
      ))}
    </div>
  );
}

/** A grouped list card. Rows divide with a hairline; the card never nests. */
function RowGroup({ children, style }) {
  const rows = React.Children.toArray(children).filter(Boolean);
  return (
    <div style={{ background: 'var(--surface-card)', borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)', overflow: 'hidden', ...style }}>
      {rows.map((r, i) => (
        <div key={i} style={{ borderTop: i ? '1px solid var(--border-hairline)' : 'none' }}>{r}</div>
      ))}
    </div>
  );
}

/** A labelled value in a task form. Tapping opens the real control. */
function FieldRow({ label, value, icon, chevron = true, onClick, error }) {
  return (
    <div onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '11px 16px', cursor: onClick ? 'pointer' : undefined }}>
      {icon ? <Icon name={icon} size={19} color="var(--gp-outline)" /> : null}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ font: '600 11.5px/1 var(--font-sans)', letterSpacing: '.06em', textTransform: 'uppercase',
          color: error ? 'var(--gp-error)' : 'var(--gp-outline)' }}>{label}</div>
        <div style={{ font: '500 15.5px/1.35 var(--font-sans)', color: 'var(--gp-on-surface)', marginTop: 5,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{value}</div>
        {error ? <div style={{ font: '400 12px/1.3 var(--font-sans)', color: 'var(--gp-error)', marginTop: 4 }}>{error}</div> : null}
      </div>
      {chevron && onClick ? <Icon name="chevron_right" size={19} color="#BFC9BE" /> : null}
    </div>
  );
}

/** The bar that pins a task's one commit action to the bottom of the screen. */
function ActionBar({ children }) {
  return (
    <div style={{ flex: '0 0 auto', padding: '12px 16px 16px', background: 'var(--surface-card)',
      borderTop: '1px solid var(--border-hairline)' }}>{children}</div>
  );
}

Object.assign(window, { TaskBar, TaskBody, OwnerLine, HeroFacts, RowGroup, FieldRow, ActionBar, MatchListSkeleton, screenState });
