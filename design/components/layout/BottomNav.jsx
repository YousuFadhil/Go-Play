import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** The floating navigation bar. It sits above the content rather than closing
 *  the page off, so a scrolling list runs under it and the screen keeps its
 *  full height. The selected destination is a filled pill behind the icon *and*
 *  a heavier label — either alone is easy to miss at a glance. */
export function BottomNav({ items, value, onChange, floating = true, style }) {
  const base = {
    display: 'grid', gridAutoFlow: 'column', gridAutoColumns: '1fr',
    height: 58, background: 'var(--surface-card)',
  };
  const pos = floating
    ? { position: 'absolute', insetInline: 14, bottom: 14, borderRadius: 'var(--radius-control)', boxShadow: 'var(--elevation-nav)', zIndex: 5 }
    : { borderTop: '1px solid var(--border-hairline)' };
  return (
    <nav style={{ ...base, ...pos, ...style }}>
      {items.map((it) => {
        const on = it.value === value;
        return (
          <button key={it.value} type="button" onClick={() => onChange && onChange(it.value)}
            style={{ border: 'none', background: 'transparent', cursor: 'pointer', padding: 0,
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3 }}>
            <span style={{ width: 46, height: 26, borderRadius: 13, display: 'grid', placeItems: 'center',
              background: on ? 'var(--status-open-bg)' : 'transparent',
              transition: 'background var(--duration-fast) var(--easing-standard)' }}>
              <Icon name={it.icon} size={21} fill={on} color={on ? 'var(--gp-primary-deep)' : '#8C978D'} />
            </span>
            <span style={{ font: (on ? 600 : 400) + ' 10.5px/1 var(--font-sans)', color: on ? 'var(--gp-primary-deep)' : '#8C978D' }}>{it.label}</span>
          </button>
        );
      })}
    </nav>
  );
}
