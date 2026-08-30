import React from 'react';

/** One spinner, the same size in the same place on every screen that has no
 *  shape to placeholder. */
export function LoadingState({ style }) {
  return (
    <div style={{ display: 'grid', placeItems: 'center', padding: 'var(--gap-xxl)', ...style }}>
      <style>{'@keyframes gp-spin{to{transform:rotate(360deg)}}'}</style>
      <span style={{
        width: 32, height: 32, borderRadius: '50%',
        border: '3px solid var(--gp-primary)', borderTopColor: 'transparent',
        animation: 'gp-spin 900ms linear infinite', display: 'block',
      }} />
    </div>
  );
}
