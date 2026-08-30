import React from 'react';

/** A filled field with a hairline border and a floating label. Focus thickens
 *  the border to 2px in the primary colour; that is the whole focus treatment. */
export function TextField({
  label, value, defaultValue, placeholder, helper, error, counter, maxLength,
  type = 'text', multiline, rows = 3, disabled, onChange, id, style, ...rest
}) {
  const [focused, setFocused] = React.useState(false);
  const borderColor = error ? 'var(--gp-error)' : focused ? 'var(--gp-primary)' : 'var(--gp-outline-variant)';
  const Field = multiline ? 'textarea' : 'input';
  const fieldId = id || `gp-${label}`;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, ...style }}>
      <div style={{
        position: 'relative', background: 'var(--gp-surface-container-low)',
        borderRadius: 'var(--radius-sm)',
        border: `${focused || error ? 2 : 1}px solid ${borderColor}`,
        padding: `${focused || error ? 15 : 16}px`, paddingTop: 22, paddingBottom: 10,
        opacity: disabled ? 0.38 : 1, transition: 'border-color var(--duration-fast) var(--easing-standard)',
      }}>
        <label htmlFor={fieldId} style={{
          position: 'absolute', top: 8, insetInlineStart: 16,
          font: 'var(--type-label-small)', color: error ? 'var(--gp-error)' : focused ? 'var(--gp-primary)' : 'var(--gp-on-surface-variant)',
        }}>{label}</label>
        <Field
          id={fieldId} type={type} value={value} defaultValue={defaultValue} rows={multiline ? rows : undefined}
          placeholder={placeholder} disabled={disabled} maxLength={maxLength} onChange={onChange}
          onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
          style={{
            width: '100%', border: 'none', outline: 'none', background: 'transparent', resize: 'vertical',
            font: 'var(--type-body-large)', color: 'var(--gp-on-surface)', padding: 0,
          }}
          {...rest}
        />
      </div>
      {(error || helper || counter) ? (
        <div style={{ display: 'flex', gap: 'var(--gap-sm)', padding: '0 var(--gap-lg)' }}>
          <span style={{ font: 'var(--type-body-small)', color: error ? 'var(--gp-error)' : 'var(--gp-on-surface-variant)', flex: 1 }}>
            {error || helper}
          </span>
          {counter ? <span style={{ font: 'var(--type-body-small)', color: 'var(--gp-on-surface-variant)' }}>{counter}</span> : null}
        </div>
      ) : null}
    </div>
  );
}
