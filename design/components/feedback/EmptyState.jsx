import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** Nothing to show, and that is normal. The glyph sits in a tinted disc rather
 *  than floating on the background: at this size a bare outline glyph reads as
 *  a missing image instead of as an illustration. */
export function EmptyState({ icon = 'sports_soccer', title, message, note, action, tone = 'neutral', style }) {
  const disc = tone === 'accent'
    ? { background: 'var(--gp-primary-container)', color: 'var(--gp-on-primary-container)' }
    : { background: 'var(--gp-surface-container-highest)', color: 'var(--gp-on-surface-variant)' };
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center',
      padding: 'var(--gap-xxl) var(--gap-xl)', ...style,
    }}>
      <span style={{ width: 64, height: 64, borderRadius: '50%', display: 'grid', placeItems: 'center', ...disc }}>
        <Icon name={icon} size={32} />
      </span>
      {title ? <h3 style={{ font: 'var(--type-title-medium)', color: 'var(--gp-on-surface)', marginTop: 'var(--gap-lg)' }}>{title}</h3> : null}
      <p style={{ margin: title ? 'var(--gap-sm) 0 0' : 'var(--gap-lg) 0 0', font: 'var(--type-body-medium)', color: 'var(--gp-on-surface-variant)', maxWidth: 380, whiteSpace: 'pre-line', unicodeBidi: 'plaintext' }}>{message}</p>
      {note ? <p style={{ margin: 'var(--gap-md) 0 0', font: 'var(--type-body-small)', color: 'var(--gp-outline)' }}>{note}</p> : null}
      {action ? <div style={{ marginTop: 'var(--gap-xl)' }}>{action}</div> : null}
    </div>
  );
}
