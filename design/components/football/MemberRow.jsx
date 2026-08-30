import React from 'react';
import { Avatar } from '../core/Avatar.jsx';
import { Chip } from '../core/Chip.jsx';
import { Icon } from '../core/Icon.jsx';

/** A person in a community list. Name, then role and position on one quiet
 *  line, then whatever this screen lets you do about them. The role marker is
 *  a square chip so it never reads as a match status. */
export function MemberRow({ name, role, position, you, trailing, onClick, style }) {
  const meta = [role, position].filter(Boolean).join(' · ');
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--gap-md)',
        padding: '10px var(--gap-lg)', minHeight: 56, cursor: onClick ? 'pointer' : undefined,
        transition: 'background var(--duration-fast) var(--easing-standard)', ...style,
      }}
      onMouseEnter={(e) => { if (onClick) e.currentTarget.style.background = '#F7FAF6'; }}
      onMouseLeave={(e) => { if (onClick) e.currentTarget.style.background = 'transparent'; }}
    >
      <Avatar name={name} size={38} tone={role === 'Owner' ? 'accent' : 'neutral'} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
          <span style={{ flex: '0 1 auto', minWidth: 0, font: '600 14.5px/1.3 var(--font-sans)', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
          {you ? <Chip tone="open" square>You</Chip> : null}
        </div>
        {meta ? <div style={{ font: '400 12px/1.3 var(--font-sans)', color: 'var(--gp-outline)', marginTop: 3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{meta}</div> : null}
      </div>
      {trailing}
      {onClick && !trailing ? <Icon name="chevron_right" size={19} color="#BFC9BE" /> : null}
    </div>
  );
}
