import React from 'react';
import { Button } from '../core/Button.jsx';

/** A confirmation. Two actions: a text button that backs out, and the real one
 *  — filled, and in the error colour when it destroys something. */
export function Dialog({ title, body, cancelLabel = 'Back', confirmLabel, destructive, onCancel, onConfirm, style }) {
  return (
    <div style={{
      maxWidth: 360, background: 'var(--gp-surface-container-high)', borderRadius: 'var(--radius-md)',
      padding: 'var(--gap-xl)', boxShadow: 'var(--elevation-menu)', ...style,
    }}>
      <h3 style={{ font: 'var(--type-title-large)', letterSpacing: 'var(--tracking-title-large)', color: 'var(--gp-on-surface)' }}>{title}</h3>
      <p style={{ margin: 'var(--gap-md) 0 var(--gap-xl)', font: 'var(--type-body-medium)', color: 'var(--gp-on-surface-variant)' }}>{body}</p>
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 'var(--gap-sm)' }}>
        <Button variant="text" size="compact" onClick={onCancel}>{cancelLabel}</Button>
        <Button variant={destructive ? 'danger' : 'filled'} size="compact" onClick={onConfirm}>{confirmLabel}</Button>
      </div>
    </div>
  );
}
