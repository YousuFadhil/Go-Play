import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** One row in a grouped card: a leading glyph or avatar, a title, a quieter
 *  second line, and whatever the row is for on the end. */
export function ListRow({ icon, leading, title, subtitle, trailing, chevron, danger, onClick, style }) {
  const color = danger ? 'var(--gp-error)' : 'var(--gp-on-surface)';
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--gap-lg)',
        padding: 'var(--gap-md) var(--gap-lg)', minHeight: 'var(--tap-min)',
        cursor: onClick ? 'pointer' : undefined,
        transition: 'background var(--duration-fast) var(--easing-standard)', ...style,
      }}
      onMouseEnter={(e) => { if (onClick) e.currentTarget.style.background = 'color-mix(in srgb, var(--gp-on-surface) 5%, transparent)'; }}
      onMouseLeave={(e) => { if (onClick) e.currentTarget.style.background = 'transparent'; }}
    >
      {leading || (icon ? <Icon name={icon} size={24} color={danger ? 'var(--gp-error)' : 'var(--gp-on-surface-variant)'} /> : null)}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ font: 'var(--type-body-large)', color, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</div>
        {subtitle ? <div style={{ font: 'var(--type-body-small)', color: 'var(--text-muted)', marginTop: 2 }}>{subtitle}</div> : null}
      </div>
      {trailing}
      {chevron ? <Icon name="chevron_right" size={22} color="var(--gp-on-surface-variant)" /> : null}
    </div>
  );
}
