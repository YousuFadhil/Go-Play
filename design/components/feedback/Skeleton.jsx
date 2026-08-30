import React from 'react';

/** A placeholder the shape of what is coming. Screens whose content has no
 *  fixed shape use LoadingState instead. */
export function Skeleton({ width = '100%', height = 16, radius = 'var(--radius-sm)', style }) {
  return (
    <>
      <style>{'@keyframes gp-skeleton{0%,100%{opacity:.45}50%{opacity:.9}}@keyframes gp-spin{to{transform:rotate(360deg)}}'}</style>
      <span style={{
        display: 'block', width, height, borderRadius: radius,
        background: 'var(--gp-surface-container-highest)',
        animation: 'gp-skeleton 1400ms var(--easing-standard) infinite', ...style,
      }} />
    </>
  );
}
