import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** A community's crest: its initials in a rounded square. Not a circle — a
 *  circle is a person in this product, and the two appear side by side often
 *  enough that the shape has to carry the difference. The schema has no logo
 *  column, so this *is* a community's mark. */
export function CommunityLogo({ name = '', size = 56, onHero, style }) {
  const initials = String(name).trim().split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const skin = onHero
    ? { background: 'rgba(255,255,255,.15)', border: '1.5px solid rgba(255,255,255,.3)', color: '#fff' }
    : { background: 'var(--status-open-bg)', border: 'none', color: 'var(--gp-primary-deep)' };
  return (
    <span style={{
      width: size, height: size, flex: '0 0 auto', borderRadius: 'var(--radius-crest)',
      display: 'grid', placeItems: 'center', boxSizing: 'border-box', ...skin,
      fontFamily: 'var(--font-sans)', fontSize: size * 0.34, fontWeight: 700, lineHeight: 1, letterSpacing: '-.5px', ...style,
    }}>
      {initials || <Icon name="groups" size={size * 0.46} fill />}
    </span>
  );
}
