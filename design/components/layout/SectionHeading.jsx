import React from 'react';

/** A heading over a group of rows. Tight by Club standards — 18px above, 9px
 *  below — because the sheet already separates sections and a 32px gap on top
 *  of that is space the list wanted. */
export function SectionHeading({ title, count, action, onAction, style }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--gap-sm)', padding: '18px var(--gap-lg) 9px', ...style }}>
      <h2 style={{ flex: 1, minWidth: 0, font: '700 16.5px/1.25 var(--font-sans)', letterSpacing: '-.3px', color: 'var(--gp-on-surface)' }}>
        {title}{count != null ? <span style={{ color: 'var(--gp-outline)', fontWeight: 500, unicodeBidi: 'isolate' }}> · {count}</span> : null}
      </h2>
      {action ? <button type="button" onClick={onAction} style={{ border: 'none', background: 'transparent', font: '600 13px/1 var(--font-sans)', color: 'var(--gp-primary)', cursor: 'pointer', padding: 0 }}>{action}</button> : null}
    </div>
  );
}
