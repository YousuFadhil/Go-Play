import React from 'react';

/** Material Symbols glyph. The Flutter app draws every icon from the Material
 *  icon font (Icons.*); this is the same set, loaded as a webfont. */
export function Icon({ name, size = 24, fill = false, color = 'currentColor', weight = 400, style, ...rest }) {
  return (
    <span
      className="gp-icon"
      aria-hidden="true"
      style={{
        fontFamily: 'var(--font-icon)', fontSize: size, lineHeight: 1, color,
        fontVariationSettings: `"FILL" ${fill ? 1 : 0}, "wght" ${weight}, "GRAD" 0, "opsz" ${size}`,
        display: 'inline-block', userSelect: 'none', ...style,
      }}
      {...rest}
    >{name}</span>
  );
}
