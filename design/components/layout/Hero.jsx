import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** The crest hero: a flat deep-green block that says whose community you are
 *  inside before you read anything. Deliberately short — it carries a bar row,
 *  an identity row and at most one action row, and then it stops. The ball is
 *  a single 190px glyph at 5.5% white, most of it outside the block, so it
 *  reads as texture rather than as an icon somebody forgot to position. */
export function Hero({ children, ball = true, style }) {
  return (
    <div style={{
      background: 'var(--bg-hero)', position: 'relative', overflow: 'hidden',
      flex: '0 0 auto', paddingBottom: 30, ...style,
    }}>
      {ball ? (
        <span style={{ position: 'absolute', right: -44, top: -50, opacity: 1, pointerEvents: 'none', lineHeight: 0 }}>
          <Icon name="sports_soccer" size={190} fill color="rgba(255,255,255,.055)" />
        </span>
      ) : null}
      <div style={{ position: 'relative' }}>{children}</div>
    </div>
  );
}

/** The bar inside a Hero: back, title, actions — all reversed out. */
export function HeroBar({ title, onBack, right }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', height: 50, padding: '0 6px', color: '#fff' }}>
      {onBack ? (
        <button type="button" aria-label="Back" onClick={onBack} style={{ width: 44, height: 44, border: 'none', background: 'transparent', color: '#fff', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
          <Icon name="arrow_back" size={22} />
        </button>
      ) : <span style={{ width: 14 }} />}
      <span style={{ flex: 1, minWidth: 0, font: '500 16px/1.2 var(--font-sans)', opacity: .9, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</span>
      {right}
    </div>
  );
}

/** The light page that slides over the bottom of a Hero. Everything below the
 *  identity lives in here. */
export function Sheet({ children, style }) {
  return (
    <div style={{
      flex: 1, minHeight: 0, overflowY: 'auto', background: 'var(--surface-sheet)',
      borderRadius: 'var(--radius-sheet) var(--radius-sheet) 0 0',
      marginTop: -22, position: 'relative', paddingTop: 6, ...style,
    }}>{children}</div>
  );
}
