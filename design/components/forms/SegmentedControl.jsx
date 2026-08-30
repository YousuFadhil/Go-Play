import React from 'react';

/** Material's segmented button: one row, one selection, an outline around the
 *  set and a tonal fill behind the chosen segment. Used for the statistics
 *  period and the language switch. */
export function SegmentedControl({ options, value, onChange, fullWidth = true, style }) {
  return (
    <div role="radiogroup" style={{
      display: fullWidth ? 'grid' : 'inline-grid',
      gridAutoFlow: 'column', gridAutoColumns: '1fr',
      border: '1px solid var(--gp-outline-variant)', borderRadius: 'var(--radius-pill)',
      overflow: 'hidden', width: fullWidth ? '100%' : undefined, ...style,
    }}>
      {options.map((o, i) => {
        const v = o.value ?? o; const label = o.label ?? o;
        const selected = v === value;
        return (
          <button key={v} type="button" role="radio" aria-checked={selected} onClick={() => onChange && onChange(v)}
            style={{
              minHeight: 40, padding: '0 var(--gap-sm)', border: 'none',
              borderInlineStart: i === 0 ? 'none' : '1px solid var(--gp-outline-variant)',
              background: selected ? 'var(--gp-secondary-container)' : 'transparent',
              color: selected ? 'var(--gp-on-secondary-container)' : 'var(--gp-on-surface)',
              font: 'var(--type-label-large)', cursor: 'pointer',
              transition: 'background var(--duration-fast) var(--easing-standard)',
            }}>{label}</button>
        );
      })}
    </div>
  );
}
