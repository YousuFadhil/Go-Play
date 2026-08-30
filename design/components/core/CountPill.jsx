import React from 'react';

/** The size of the group beside its heading. A separate, quieter figure rather
 *  than part of the title: "Members (12)" makes the number look like part of
 *  the word; a pill beside it reads as a measurement of what follows. */
export function CountPill({ count, style }) {
  return (
    <span style={{
      minWidth: 28, padding: '2px var(--gap-sm)', borderRadius: 'var(--radius-pill)',
      background: 'var(--gp-surface-container-highest)', color: 'var(--gp-on-surface-variant)',
      font: 'var(--type-label-medium)', fontWeight: 700, textAlign: 'center', ...style,
    }}>{count}</span>
  );
}
