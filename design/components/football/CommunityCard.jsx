import React from 'react';
import { Icon } from '../core/Icon.jsx';
import { Chip } from '../core/Chip.jsx';
import { CommunityLogo } from './CommunityLogo.jsx';

/** One community in a list. Crest, name, role, description, then the two
 *  counts that say whether it is worth opening. No action button: opening it is
 *  the action, and a card that repeats itself in a button reads as two things. */
export function CommunityCard({ name, description, memberCount, upcomingCount, role, codeRequired, trailing, onClick, style }) {
  return (
    <div
      onClick={onClick}
      style={{
        background: 'var(--surface-card)', borderRadius: 'var(--radius-card)',
        boxShadow: 'var(--elevation-card)', padding: 'var(--gap-md) var(--gap-lg)',
        display: 'flex', gap: 'var(--gap-md)', alignItems: 'center',
        cursor: onClick ? 'pointer' : undefined, ...style,
      }}
    >
      <CommunityLogo name={name} size={46} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, minWidth: 0 }}>
          <span style={{ flex: '0 1 auto', minWidth: 0, font: '700 15.5px/1.3 var(--font-sans)', letterSpacing: '-.2px', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
          {codeRequired ? <Icon name="key" size={14} color="var(--gp-outline)" /> : null}
          {role && role !== 'Player' ? <Chip tone="role" square>{role}</Chip> : null}
        </div>
        {description ? <div style={{ font: '400 12.5px/1.4 var(--font-sans)', color: 'var(--gp-on-surface-variant)', marginTop: 3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{description}</div> : null}
        <div style={{ display: 'flex', gap: 14, marginTop: 7, font: '400 12px/1 var(--font-sans)', color: 'var(--gp-outline)' }}>
          {memberCount != null ? <span style={{ display: 'inline-flex', gap: 5, alignItems: 'center', whiteSpace: 'nowrap' }}><Icon name="person" size={13} /><span style={{ unicodeBidi: 'plaintext' }}>{memberCount} members</span></span> : null}
          {upcomingCount ? <span style={{ display: 'inline-flex', gap: 5, alignItems: 'center', whiteSpace: 'nowrap' }}><Icon name="sports_soccer" size={13} /><span style={{ unicodeBidi: 'plaintext' }}>{upcomingCount} upcoming</span></span> : null}
        </div>
      </div>
      {trailing}
    </div>
  );
}
