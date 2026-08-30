import React from 'react';
import { Avatar } from '../core/Avatar.jsx';
import { Chip } from '../core/Chip.jsx';
import { Icon } from '../core/Icon.jsx';

const TAG = { Goalkeeper: 'GK', Defender: 'DEF', Midfielder: 'MID', Forward: 'FWD' };

/** A participant on a roster. A professional guest has no profile and therefore
 *  no position: saying what they are is more use than leaving the line blank. */
export function ParticipantRow({ name, position, guest, index, reserve, you, handle, trailing, onClick, style }) {
  const label = guest ? `Professional (${name})` : name;
  return (
    <div
      onClick={onClick}
      style={{ display: 'flex', alignItems: 'center', gap: 'var(--gap-md)',
        padding: '9px var(--gap-lg)', minHeight: 54, cursor: onClick ? 'pointer' : undefined, ...style }}
    >
      {handle ? <Icon name="drag_indicator" size={20} color="#BFC9BE" /> : null}
      {index != null ? <span style={{ width: 18, textAlign: 'center', font: '500 12px/1 var(--font-sans)', color: 'var(--gp-outline)' }}>{index}</span> : null}
      <Avatar name={guest ? '' : name} size={34} tone={reserve ? 'neutral' : 'accent'} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
          <span style={{ flex: '0 1 auto', minWidth: 0, font: '600 14px/1.3 var(--font-sans)', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
          {you ? <Chip tone="open" square>You</Chip> : null}
        </div>
        <div style={{ font: '400 12px/1.3 var(--font-sans)', color: reserve ? 'var(--gp-tertiary)' : 'var(--gp-outline)', marginTop: 3 }}>
          {guest ? 'Professional guest' : reserve ? 'Reserve · ' + position : position}
        </div>
      </div>
      {trailing || (position && !guest ? <Chip tone="role" square>{TAG[position] || position}</Chip> : null)}
    </div>
  );
}
