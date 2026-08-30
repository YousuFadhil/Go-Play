import React from 'react';

/** The product's surface. White, 20px, and a shadow so light it registers as a
 *  contact edge rather than as lift — two nearly invisible stops instead of one
 *  visible one. A list of cards must still read as one page, which is why the
 *  shadow is this quiet and why there is no border under it. */
export function Card({ padded = true, interactive, outlined, onClick, children, style, ...rest }) {
  return (
    <div
      onClick={onClick}
      style={{
        background: 'var(--surface-card)', borderRadius: 'var(--radius-card)',
        boxShadow: 'var(--elevation-card)', overflow: 'hidden',
        border: outlined ? '1.5px solid #CBE3CF' : 'none',
        padding: padded ? 'var(--gap-lg)' : 0,
        cursor: interactive || onClick ? 'pointer' : undefined,
        transition: 'background var(--duration-fast) var(--easing-standard)', ...style,
      }}
      onMouseEnter={(e) => { if (interactive || onClick) e.currentTarget.style.background = '#F7FAF6'; }}
      onMouseLeave={(e) => { if (interactive || onClick) e.currentTarget.style.background = 'var(--surface-card)'; }}
      {...rest}
    >{children}</div>
  );
}
