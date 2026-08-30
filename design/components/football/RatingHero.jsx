import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** The one figure a player's record is built around. Flat deep green, not a
 *  gradient: the rating is a number to read, and a gradient behind a number is
 *  decoration the number did not ask for. */
export function RatingHero({ value, label = 'Current rating', form, style }) {
  return (
    <div style={{
      background: 'var(--gp-primary-deep)', color: '#fff', borderRadius: 'var(--radius-card)',
      padding: 'var(--gap-lg) var(--gap-xl)', display: 'flex', alignItems: 'center', gap: 'var(--gap-xl)', ...style,
    }}>
      <div>
        <div style={{ font: '700 36px/1 var(--font-sans)', letterSpacing: '-1.6px' }}>{value}</div>
        <div style={{ font: '500 10.5px/1 var(--font-sans)', letterSpacing: '.08em', textTransform: 'uppercase', color: 'rgba(255,255,255,.7)', marginTop: 7 }}>{label}</div>
      </div>
      {form && form.length ? (
        <div style={{ flex: 1, display: 'flex', alignItems: 'flex-end', gap: 5, height: 46 }}>
          {form.map((v, i) => (
            <span key={i} style={{ flex: 1, height: Math.max(8, (v / 5) * 46), borderRadius: 3,
              background: i === form.length - 1 ? '#fff' : 'rgba(255,255,255,.3)' }} />
          ))}
        </div>
      ) : null}
    </div>
  );
}
