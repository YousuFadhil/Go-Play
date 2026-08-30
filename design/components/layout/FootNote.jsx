import React from 'react';

/** A quiet closing sentence: what the figures above mean, or why something is
 *  not offered. Never an error, and styled so it cannot be mistaken for one. */
export function FootNote({ children, align = 'start', style }) {
  return (
    <p style={{
      margin: 0, padding: 'var(--gap-xl) var(--page-margin) var(--gap-lg)',
      font: 'var(--type-body-small)', color: 'var(--gp-outline)', textAlign: align, ...style,
    }}>{children}</p>
  );
}
