import React from 'react';
import { Icon } from './Icon.jsx';

const TONES = {
  open:      { background: 'var(--status-open-bg)', color: 'var(--status-open-fg)' },
  full:      { background: 'var(--status-full-bg)', color: 'var(--status-full-fg)' },
  completed: { background: '#E4E9E2', color: 'var(--gp-on-surface-variant)' },
  reserve:   { background: 'var(--gp-tertiary-container)', color: 'var(--gp-on-tertiary-container)' },
  neutral:   { background: '#EDF1EB', color: 'var(--gp-on-surface-variant)' },
  accent:    { background: 'var(--status-open-bg)', color: 'var(--status-open-fg)' },
  danger:    { background: 'var(--gp-error-container)', color: 'var(--gp-on-error-container)' },
  onHero:    { background: 'rgba(255,255,255,.16)', color: '#fff' },
  role:      { background: '#EDF1EB', color: 'var(--gp-on-surface-variant)' },
};

/** A pill that reports state. Never interactive — a chip in this product is a
 *  reading, not a control. `square` is the role marker: a role is a property of
 *  a person, not a status of a thing, and the shape says so. */
export function Chip({ tone = 'neutral', icon, square, children, style, ...rest }) {
  const t = TONES[tone] || TONES.neutral;
  return (
    <span
      style={{
        ...t, display: 'inline-flex', alignItems: 'center', gap: 5,
        padding: square ? '3px 8px' : '5px 11px',
        borderRadius: square ? 6 : 'var(--radius-pill)',
        font: square ? '700 10.5px/1.6 var(--font-sans)' : '700 11.5px/1.35 var(--font-sans)',
        letterSpacing: square ? '.06em' : 0,
        textTransform: square ? 'uppercase' : 'none',
        whiteSpace: 'nowrap', ...style,
      }}
      {...rest}
    >
      {icon ? <Icon name={icon} size={14} /> : null}
      {children}
    </span>
  );
}
