import React from 'react';
import { Icon } from './Icon.jsx';

/** A bar action: a glyph in a 44px tap target, optionally carrying a count. */
export function IconButton({ icon, label, badge, active, onHero, onClick, size = 22, style, ...rest }) {
  return (
    <button
      type="button" aria-label={label} title={label} onClick={onClick}
      style={{
        position: 'relative', width: 44, height: 44, flex: '0 0 auto', borderRadius: 'var(--radius-pill)',
        border: 'none', background: 'transparent', cursor: 'pointer',
        color: onHero ? '#fff' : active ? 'var(--gp-primary)' : 'var(--gp-on-surface)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        transition: 'background var(--duration-fast) var(--easing-standard)', ...style,
      }}
      onMouseEnter={(e) => { e.currentTarget.style.background = onHero ? 'rgba(255,255,255,.14)' : 'rgba(17,26,19,.06)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}
      {...rest}
    >
      <Icon name={icon} size={size} />
      {badge ? (
        <span dir="ltr" style={{ position: 'absolute', top: 5, insetInlineEnd: 3, minWidth: 16, height: 16, padding: '0 4px',
          borderRadius: 'var(--radius-pill)', background: '#E4572E', color: '#fff',
          font: '700 10px/16px var(--font-sans)', textAlign: 'center' }}>{badge}</span>
      ) : null}
    </button>
  );
}
