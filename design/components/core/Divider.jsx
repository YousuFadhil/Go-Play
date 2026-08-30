import React from 'react';

/** A hairline between rows inside a card. 24px of air around it by default,
 *  which is what the app's DividerTheme sets. */
export function Divider({ inset = 0, tight = false, style }) {
  return <hr style={{
    border: 0, height: 1, background: 'var(--border-hairline)',
    margin: tight ? '0' : 'calc(var(--gap-xl) / 2) 0',
    marginInlineStart: inset, ...style,
  }} />;
}
