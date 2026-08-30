import React from 'react';
import { Icon } from '../core/Icon.jsx';
import { Button } from '../core/Button.jsx';

/** A read that failed, and the one thing worth offering about it. The retry is
 *  outlined rather than filled on purpose: filling the only control on the
 *  screen would make a recovery look like the screen's purpose. */
export function ErrorState({ message = 'Failed to load data.', retryLabel = 'Retry', onRetry, style }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center',
      padding: 'var(--gap-xxl) var(--gap-xl)', ...style,
    }}>
      <span style={{
        width: 64, height: 64, borderRadius: '50%', display: 'grid', placeItems: 'center',
        background: 'var(--gp-error-container)', color: 'var(--gp-on-error-container)',
      }}><Icon name="cloud_off" size={32} /></span>
      <p style={{ margin: 'var(--gap-lg) 0 0', font: 'var(--type-body-medium)', color: 'var(--gp-on-surface)', maxWidth: 380, unicodeBidi: 'plaintext' }}>{message}</p>
      <div style={{ marginTop: 'var(--gap-xl)' }}>
        <Button variant="outlined" icon="refresh" onClick={onRetry}>{retryLabel}</Button>
      </div>
    </div>
  );
}
