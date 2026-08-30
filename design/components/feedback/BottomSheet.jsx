import React from 'react';

/** The action sheet. Every action carries its label here, which is what an app
 *  bar full of glyphs could not do — and the destructive one sits last, behind
 *  a divider, in the error colour. */
export function BottomSheet({ title, children, style }) {
  return (
    <div style={{
      background: 'var(--gp-surface-container-low)',
      borderRadius: 'var(--radius-lg) var(--radius-lg) 0 0',
      boxShadow: 'var(--elevation-sheet)', paddingBottom: 'var(--gap-sm)', overflow: 'hidden', ...style,
    }}>
      <div style={{ display: 'grid', placeItems: 'center', padding: 'var(--gap-md) 0' }}>
        <span style={{ width: 32, height: 4, borderRadius: 'var(--radius-pill)', background: 'var(--gp-outline-variant)' }} />
      </div>
      {title ? <div style={{ padding: '0 var(--page-margin) var(--gap-md)', font: 'var(--type-title-medium)', color: 'var(--gp-on-surface)' }}>{title}</div> : null}
      {children}
    </div>
  );
}
