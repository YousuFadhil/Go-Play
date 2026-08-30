import React from 'react';
import { Icon } from './Icon.jsx';

function initialsOf(name = '') {
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '';
  return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

/** A player's picture, or their initials when they have not set one. The
 *  initials are not a placeholder — they are what an account without a picture
 *  looks like, and a picture that fails to load falls back to the same thing. */
export function Avatar({ src, name, size = 40, tone = 'accent', style }) {
  const initials = initialsOf(name);
  const tonal = tone === 'accent'
    ? { background: 'var(--gp-primary-container)', color: 'var(--gp-on-primary-container)' }
    : { background: 'var(--gp-surface-container-highest)', color: 'var(--gp-on-surface-variant)' };
  return (
    <span style={{
      width: size, height: size, borderRadius: '50%', overflow: 'hidden', flex: '0 0 auto',
      display: 'inline-grid', placeItems: 'center', ...tonal,
      font: 'var(--type-title-medium)', fontSize: size * 0.4, fontWeight: 600, ...style,
    }}>
      {src
        ? <img src={src} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        : initials || <Icon name="person" size={size * 0.55} fill />}
    </span>
  );
}
