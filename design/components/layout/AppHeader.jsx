import React from 'react';
import { Icon } from '../core/Icon.jsx';
import { Avatar } from '../core/Avatar.jsx';

/** One bar for every signed-in screen. The screen's own actions come first;
 *  the signed-in player is appended after them, where it stays put as those
 *  actions differ from screen to screen. */
export function AppHeader({ title, onBack, actions, user, scrolled, style }) {
  return (
    <header style={{
      display: 'flex', alignItems: 'center', gap: 'var(--gap-xs)',
      minHeight: 'var(--appbar-height)', padding: '0 var(--gap-xs)',
      background: 'var(--gp-surface)',
      boxShadow: scrolled ? 'var(--elevation-scrolled)' : 'none',
      position: 'sticky', top: 0, zIndex: 10, ...style,
    }}>
      {onBack ? (
        <button type="button" aria-label="Back" onClick={onBack} style={{
          width: 48, height: 48, border: 'none', background: 'transparent', cursor: 'pointer',
          display: 'grid', placeItems: 'center', color: 'var(--gp-on-surface)', borderRadius: 'var(--radius-pill)',
        }}><Icon name="arrow_back" size={24} /></button>
      ) : <span style={{ width: 'var(--gap-md)' }} />}
      <h1 style={{ flex: 1, minWidth: 0, font: 'var(--type-title-large)', letterSpacing: 'var(--tracking-title-large)', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</h1>
      <div style={{ display: 'flex', alignItems: 'center', gap: 0 }}>{actions}</div>
      {user ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--gap-sm)', padding: '0 var(--gap-md) 0 var(--gap-xs)', cursor: 'pointer' }}>
          <Avatar name={user.name} src={user.avatarUrl} size={32} />
          <span style={{ font: 'var(--type-label-large)', color: 'var(--gp-on-surface)', maxWidth: 96, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {String(user.name || '').trim().split(/\s+/)[0]}
          </span>
        </div>
      ) : null}
    </header>
  );
}
