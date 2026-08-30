import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** One figure from a record. Laid out three per row: at two per row the tiles
 *  are wider than the number needs and the grid starts to look like a
 *  dashboard. */
export function StatTile({ icon, value, label, tone = 'accent', style }) {
  return (
    <div style={{
      background: 'var(--surface-card)', borderRadius: 'var(--radius-control)',
      boxShadow: 'var(--elevation-card)', padding: '12px 8px', textAlign: 'center', ...style,
    }}>
      {icon ? <Icon name={icon} size={18} fill color={tone === 'accent' ? 'var(--gp-primary-mid)' : 'var(--gp-on-surface-variant)'} /> : null}
      <div style={{ font: '700 20px/1 var(--font-sans)', letterSpacing: '-.5px', color: 'var(--gp-on-surface)', marginTop: 8 }}>{value}</div>
      <div style={{ font: '500 11px/1.3 var(--font-sans)', color: 'var(--gp-outline)', marginTop: 6 }}>{label}</div>
    </div>
  );
}
