import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** The same shell as TextField, holding a value the reader picks rather than
 *  types: a position, a role, a date. `onClick` opens a picker; `options`
 *  turns it into a native select. */
export function SelectField({ label, value, placeholder = '—', options, error, icon = 'expand_more', disabled, onChange, onClick, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, ...style }}>
      <div
        onClick={disabled ? undefined : onClick}
        style={{
          position: 'relative', background: 'var(--gp-surface-container-low)', borderRadius: 'var(--radius-sm)',
          border: `${error ? 2 : 1}px solid ${error ? 'var(--gp-error)' : 'var(--gp-outline-variant)'}`,
          padding: '22px 16px 10px', display: 'flex', alignItems: 'center', gap: 'var(--gap-sm)',
          cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.38 : 1,
        }}
      >
        <span style={{ position: 'absolute', top: 8, insetInlineStart: 16, font: 'var(--type-label-small)', color: error ? 'var(--gp-error)' : 'var(--gp-on-surface-variant)' }}>{label}</span>
        {options ? (
          <select value={value} onChange={onChange} disabled={disabled} style={{
            flex: 1, border: 'none', background: 'transparent', outline: 'none', appearance: 'none',
            font: 'var(--type-body-large)', color: 'var(--gp-on-surface)', padding: 0, cursor: 'pointer',
          }}>
            {options.map((o) => <option key={o.value ?? o} value={o.value ?? o}>{o.label ?? o}</option>)}
          </select>
        ) : (
          <span style={{ flex: 1, font: 'var(--type-body-large)', color: value ? 'var(--gp-on-surface)' : 'var(--gp-outline)' }}>
            {value || placeholder}
          </span>
        )}
        <Icon name={icon} size={20} color="var(--gp-on-surface-variant)" />
      </div>
      {error ? <span style={{ font: 'var(--type-body-small)', color: 'var(--gp-error)', padding: '0 var(--gap-lg)' }}>{error}</span> : null}
    </div>
  );
}
