import React from 'react';
import { Icon } from './Icon.jsx';

const FILLS = {
  filled:   { background: 'var(--gp-primary-deep)', color: '#fff', border: '1.5px solid transparent' },
  tonal:    { background: 'var(--status-open-bg)', color: 'var(--status-open-fg)', border: '1.5px solid transparent' },
  outlined: { background: 'transparent', color: 'var(--gp-primary-deep)', border: '1.5px solid #CBD8C9' },
  text:     { background: 'transparent', color: 'var(--gp-primary)', border: '1.5px solid transparent' },
  onHero:   { background: '#fff', color: 'var(--gp-primary-deep)', border: '1.5px solid transparent' },
  ghost:    { background: 'rgba(255,255,255,.16)', color: '#fff', border: '1.5px solid rgba(255,255,255,.3)' },
  danger:   { background: 'var(--gp-error)', color: 'var(--gp-on-error)', border: '1.5px solid transparent' },
};

/** Every button is one of three heights and the same 16px corner. Only the fill
 *  changes, which is what lets a filled button read as the primary action
 *  without needing to be bigger than the one beside it. */
export function Button({
  variant = 'filled', size = 'default', icon, trailingIcon, fullWidth,
  disabled, loading, onClick, children, style, ...rest
}) {
  const fill = FILLS[variant] || FILLS.filled;
  const height = size === 'small' ? 38 : size === 'compact' ? 44 : 52;
  return (
    <button
      type="button" disabled={disabled || loading} onClick={onClick}
      style={{
        ...fill,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 'var(--gap-sm)',
        minHeight: height, width: fullWidth ? '100%' : undefined,
        padding: variant === 'text' ? '0 var(--gap-md)' : size === 'small' ? '0 14px' : '0 20px',
        borderRadius: 'var(--radius-control)',
        font: '700 14.5px/1 var(--font-sans)',
        cursor: disabled || loading ? 'default' : 'pointer',
        opacity: disabled ? 0.38 : 1, whiteSpace: 'nowrap',
        transition: 'filter var(--duration-fast) var(--easing-standard), opacity var(--duration-fast)', ...style,
      }}
      onMouseEnter={(e) => { if (!disabled && !loading) e.currentTarget.style.filter = 'brightness(0.94)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.filter = 'none'; }}
      {...rest}
    >
      {loading ? <Spinner /> : icon ? <Icon name={icon} size={18} /> : null}
      {loading ? null : children}
      {!loading && trailingIcon ? <Icon name={trailingIcon} size={18} /> : null}
    </button>
  );
}

function Spinner() {
  return <span style={{
    width: 18, height: 18, borderRadius: '50%', border: '2px solid currentColor',
    borderTopColor: 'transparent', animation: 'gp-spin 900ms linear infinite', display: 'inline-block',
  }} />;
}
