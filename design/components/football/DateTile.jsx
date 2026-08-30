import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** The day a match falls on, stacked: weekday, date, month. A played match
 *  shows a tick — its date has stopped being the useful thing about it. */
export function DateTile({ weekday, day, month, status = 'open', size = 'default', style }) {
  const done = status === 'completed';
  const w = size === 'compact' ? 46 : 50, h = size === 'compact' ? 52 : 56;
  const bg = done ? '#EDF1EB' : status === 'full' ? 'var(--gp-warn-container)' : 'var(--status-open-bg)';
  const fg = done ? 'var(--gp-outline)' : status === 'full' ? 'var(--gp-on-warn-container)' : 'var(--gp-primary-deep)';
  const soft = done ? 'var(--gp-outline)' : status === 'full' ? 'var(--gp-on-warn-container)' : 'var(--gp-primary-mid)';
  return (
    <div style={{ width: w, height: h, flex: '0 0 auto', background: bg, borderRadius: 14,
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', ...style }}>
      {done ? <Icon name="event_available" size={22} fill color={fg} /> : (
        <>
          <span style={{ font: '700 10px/1 var(--font-sans)', letterSpacing: '.08em', color: soft }}>{String(weekday).toUpperCase()}</span>
          <span style={{ font: '700 21px/1.2 var(--font-sans)', letterSpacing: '-.8px', color: fg }}>{day}</span>
          <span style={{ font: '500 10px/1 var(--font-sans)', color: soft }}>{month}</span>
        </>
      )}
    </div>
  );
}
