import React from 'react';

/** The floating confirmation. Inverse surface, 12px corner, 16px inset — one
 *  sentence about something that has already happened. */
export function Snackbar({ children, action, onAction, style }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 'var(--gap-lg)',
      background: 'var(--gp-inverse-surface)', color: 'var(--gp-inverse-on-surface)',
      borderRadius: 'var(--radius-sm)', padding: 'var(--gap-lg)',
      boxShadow: 'var(--elevation-snackbar)', margin: 'var(--gap-lg)', ...style,
    }}>
      <span style={{ flex: 1, font: 'var(--type-body-medium)', unicodeBidi: 'plaintext' }}>{children}</span>
      {action ? (
        <button type="button" onClick={onAction} style={{
          border: 'none', background: 'transparent', color: 'var(--gp-inverse-primary)',
          font: 'var(--type-label-large)', cursor: 'pointer', padding: 0,
        }}>{action}</button>
      ) : null}
    </div>
  );
}
