import React from 'react';

/** A setting: what it does, what it means, and the switch. The subtitle is not
 *  optional decoration — every push setting in the app explains its effect. */
export function SwitchRow({ label, subtitle, checked, onChange, disabled, style }) {
  return (
    <label style={{
      display: 'flex', alignItems: 'center', gap: 'var(--gap-lg)',
      padding: 'var(--gap-md) var(--gap-lg)', cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.38 : 1, ...style,
    }}>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', font: 'var(--type-body-large)', color: 'var(--gp-on-surface)' }}>{label}</span>
        {subtitle ? <span style={{ display: 'block', font: 'var(--type-body-small)', color: 'var(--gp-on-surface-variant)', marginTop: 2 }}>{subtitle}</span> : null}
      </span>
      <span
        onClick={() => !disabled && onChange && onChange(!checked)}
        style={{
          width: 52, height: 32, flex: '0 0 auto', borderRadius: 'var(--radius-pill)',
          background: checked ? 'var(--gp-primary)' : 'var(--gp-surface-container-highest)',
          border: checked ? '2px solid var(--gp-primary)' : '2px solid var(--gp-outline)',
          position: 'relative', transition: 'background var(--duration-fast) var(--easing-standard)',
        }}>
        <span style={{
          position: 'absolute', top: '50%', transform: 'translateY(-50%)',
          insetInlineStart: checked ? 22 : 4,
          width: checked ? 24 : 16, height: checked ? 24 : 16, borderRadius: '50%',
          background: checked ? 'var(--gp-on-primary)' : 'var(--gp-outline)',
          transition: 'all var(--duration-fast) var(--easing-standard)',
        }} />
      </span>
    </label>
  );
}
