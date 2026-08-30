import React from 'react';
import { Card } from '../layout/Card.jsx';
import { Icon } from '../core/Icon.jsx';
import { Chip } from '../core/Chip.jsx';
import { CommunityLogo } from './CommunityLogo.jsx';
import { CapacityBar } from './CapacityBar.jsx';
import { DateTile } from './DateTile.jsx';

/** One match in a list. Date tile, name and status on one line, the community
 *  crest under it where the list spans several, then the facts and the capacity
 *  bar. Four rows, no action button: a list is for choosing which match to
 *  open, and a card with its own button competes with the card itself. */
export function MatchCard({
  title, communityName, location, time, weekday, day, month,
  status = 'open', registered, starting, reserve = 0, statusLabel,
  outlined, onClick, style,
}) {
  const label = statusLabel || { open: 'Open', full: 'Full', completed: 'Played' }[status];
  return (
    <Card padded={false} outlined={outlined} onClick={onClick} style={style}>
      <div style={{ padding: 'var(--gap-md) var(--gap-lg)', display: 'flex', gap: 'var(--gap-md)', alignItems: 'flex-start' }}>
        <DateTile weekday={weekday} day={day} month={month} status={status} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--gap-sm)' }}>
            <span style={{ flex: 1, minWidth: 0, font: '700 15.5px/1.3 var(--font-sans)', letterSpacing: '-.2px', color: 'var(--gp-on-surface)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</span>
            <Chip tone={status}>{label}</Chip>
          </div>
          {communityName ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 5 }}>
              <CommunityLogo name={communityName} size={17} />
              <span style={{ font: '600 12px/1 var(--font-sans)', color: 'var(--gp-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{communityName}</span>
            </div>
          ) : null}
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 5, font: '400 12.5px/1.4 var(--font-sans)', color: 'var(--gp-on-surface-variant)', minWidth: 0 }}>
            <Icon name="schedule" size={13} color="var(--gp-outline)" />
            <span style={{ unicodeBidi: 'isolate', whiteSpace: 'nowrap', flex: '0 0 auto' }}>{time}</span>
            {location ? <>
              <span style={{ opacity: .5, flex: '0 0 auto' }}>·</span>
              <Icon name="place" size={13} color="var(--gp-outline)" style={{ flex: '0 0 auto' }} />
              <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{location}</span></> : null}
          </div>
          {registered != null ? (
            <CapacityBar compact registered={registered} starting={starting} reserve={reserve} status={status} style={{ marginTop: 9 }} />
          ) : null}
        </div>
      </div>
    </Card>
  );
}
