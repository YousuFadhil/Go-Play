import React from 'react';

/** How full a match is, as a bar rather than a ring: a ring is a decoration
 *  that happens to encode a number, and at 44px it cannot show which segment is
 *  reserve. The bar can — starting places, then reserve places, then what is
 *  left — which is the whole question a player is asking. */
export function CapacityBar({ registered, starting, reserve = 0, status = 'open', showLabel = true, compact, style }) {
  const total = starting + reserve;
  const filledStart = Math.min(registered, starting);
  const filledRes = Math.max(0, Math.min(registered - starting, reserve));
  const fill = status === 'full' ? 'var(--gp-warn)' : status === 'completed' ? '#A8B2A6' : 'var(--gp-primary-mid)';
  const seg = (n, bg, key) => Array.from({ length: n }).map((_, i) => (
    <span key={key + i} style={{ flex: 1, height: compact ? 5 : 7, borderRadius: 3, background: bg, minWidth: 2 }} />
  ));
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--gap-md)', ...style }}>
      <div style={{ flex: 1, display: 'flex', gap: 2.5, minWidth: 0 }}>
        {seg(filledStart, fill, 'a')}
        {seg(starting - filledStart, '#DCE4DA', 'b')}
        {reserve ? <span style={{ width: 6, flex: '0 0 auto' }} /> : null}
        {seg(filledRes, 'var(--gp-tertiary)', 'c')}
        {seg(reserve - filledRes, '#E3EAE1', 'd')}
      </div>
      {showLabel ? (
        <span dir="ltr" style={{ font: '600 12px/1 var(--font-sans)', color: 'var(--gp-on-surface-variant)', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>
          {registered}/{starting}
        </span>
      ) : null}
    </div>
  );
}
