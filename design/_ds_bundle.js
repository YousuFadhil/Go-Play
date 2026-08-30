/* @ds-bundle: {"format":4,"namespace":"GoPlayDesignSystem_984b89","components":[{"name":"Avatar","sourcePath":"design/components/core/Avatar.jsx"},{"name":"Button","sourcePath":"design/components/core/Button.jsx"},{"name":"Chip","sourcePath":"design/components/core/Chip.jsx"},{"name":"CountPill","sourcePath":"design/components/core/CountPill.jsx"},{"name":"Divider","sourcePath":"design/components/core/Divider.jsx"},{"name":"Icon","sourcePath":"design/components/core/Icon.jsx"},{"name":"IconButton","sourcePath":"design/components/core/IconButton.jsx"},{"name":"BottomSheet","sourcePath":"design/components/feedback/BottomSheet.jsx"},{"name":"Dialog","sourcePath":"design/components/feedback/Dialog.jsx"},{"name":"EmptyState","sourcePath":"design/components/feedback/EmptyState.jsx"},{"name":"ErrorState","sourcePath":"design/components/feedback/ErrorState.jsx"},{"name":"LoadingState","sourcePath":"design/components/feedback/LoadingState.jsx"},{"name":"Skeleton","sourcePath":"design/components/feedback/Skeleton.jsx"},{"name":"Snackbar","sourcePath":"design/components/feedback/Snackbar.jsx"},{"name":"CapacityBar","sourcePath":"design/components/football/CapacityBar.jsx"},{"name":"CommunityCard","sourcePath":"design/components/football/CommunityCard.jsx"},{"name":"CommunityLogo","sourcePath":"design/components/football/CommunityLogo.jsx"},{"name":"DateTile","sourcePath":"design/components/football/DateTile.jsx"},{"name":"MatchCard","sourcePath":"design/components/football/MatchCard.jsx"},{"name":"MemberRow","sourcePath":"design/components/football/MemberRow.jsx"},{"name":"ParticipantRow","sourcePath":"design/components/football/ParticipantRow.jsx"},{"name":"RatingHero","sourcePath":"design/components/football/RatingHero.jsx"},{"name":"StatTile","sourcePath":"design/components/football/StatTile.jsx"},{"name":"SegmentedControl","sourcePath":"design/components/forms/SegmentedControl.jsx"},{"name":"SelectField","sourcePath":"design/components/forms/SelectField.jsx"},{"name":"SwitchRow","sourcePath":"design/components/forms/SwitchRow.jsx"},{"name":"TextField","sourcePath":"design/components/forms/TextField.jsx"},{"name":"AppHeader","sourcePath":"design/components/layout/AppHeader.jsx"},{"name":"BottomNav","sourcePath":"design/components/layout/BottomNav.jsx"},{"name":"Card","sourcePath":"design/components/layout/Card.jsx"},{"name":"FootNote","sourcePath":"design/components/layout/FootNote.jsx"},{"name":"Hero","sourcePath":"design/components/layout/Hero.jsx"},{"name":"HeroBar","sourcePath":"design/components/layout/Hero.jsx"},{"name":"Sheet","sourcePath":"design/components/layout/Hero.jsx"},{"name":"ListRow","sourcePath":"design/components/layout/ListRow.jsx"},{"name":"SectionHeading","sourcePath":"design/components/layout/SectionHeading.jsx"}],"sourceHashes":{"design/components/core/Avatar.jsx":"466b1e873f27","design/components/core/Button.jsx":"52cc87a7ba8f","design/components/core/Chip.jsx":"c1092ebd973e","design/components/core/CountPill.jsx":"c0b05f06bca7","design/components/core/Divider.jsx":"18fa4339db01","design/components/core/Icon.jsx":"091f69c93ebd","design/components/core/IconButton.jsx":"47b0347a32a6","design/components/feedback/BottomSheet.jsx":"de16747f1c48","design/components/feedback/Dialog.jsx":"7d3f41b76087","design/components/feedback/EmptyState.jsx":"252443947fd7","design/components/feedback/ErrorState.jsx":"6c2fa2bf33cf","design/components/feedback/LoadingState.jsx":"0dbcc862a557","design/components/feedback/Skeleton.jsx":"345548ab6aac","design/components/feedback/Snackbar.jsx":"8b90759a1ce6","design/components/football/CapacityBar.jsx":"b2f6a71834fd","design/components/football/CommunityCard.jsx":"05d9100e76e5","design/components/football/CommunityLogo.jsx":"96aa40a2941f","design/components/football/DateTile.jsx":"191e13cecdb8","design/components/football/MatchCard.jsx":"da7e4c672dbf","design/components/football/MemberRow.jsx":"37c928d7d592","design/components/football/ParticipantRow.jsx":"1f500f6fd617","design/components/football/RatingHero.jsx":"231128815178","design/components/football/StatTile.jsx":"c4e822b61d01","design/components/forms/SegmentedControl.jsx":"c4bf9c63dc49","design/components/forms/SelectField.jsx":"27a29e59d16e","design/components/forms/SwitchRow.jsx":"d6ea4742453d","design/components/forms/TextField.jsx":"84427bfe4267","design/components/layout/AppHeader.jsx":"a1ab3802b42e","design/components/layout/BottomNav.jsx":"4899a6bc2392","design/components/layout/Card.jsx":"0be2db889bab","design/components/layout/FootNote.jsx":"8825b70f1baa","design/components/layout/Hero.jsx":"a6bfca0c116a","design/components/layout/ListRow.jsx":"f894c4e3a9c1","design/components/layout/SectionHeading.jsx":"4e167bad1d96","design/screens/App.jsx":"4d72daac35c9","design/screens/CommunityDetails.jsx":"55ca267e63b9","design/screens/CreateMatch.jsx":"dc81ad3eebd3","design/screens/Home.jsx":"309e63aa1444","design/screens/Invite.jsx":"d571617ec648","design/screens/MatchDetails.jsx":"716d00c3d3d4","design/screens/Members.jsx":"480dc1e3ccec","design/screens/Profile.jsx":"2976f73cb2bd","design/screens/Result.jsx":"85705654ad2c","design/screens/Shell.jsx":"51cd9307851f","design/screens/Teams.jsx":"a385c03e2522","design/screens/data.js":"3e07e1a15b2c"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.GoPlayDesignSystem_984b89 = window.GoPlayDesignSystem_984b89 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// design/components/core/CountPill.jsx
try { (() => {
/** The size of the group beside its heading. A separate, quieter figure rather
 *  than part of the title: "Members (12)" makes the number look like part of
 *  the word; a pill beside it reads as a measurement of what follows. */
function CountPill({
  count,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 28,
      padding: '2px var(--gap-sm)',
      borderRadius: 'var(--radius-pill)',
      background: 'var(--gp-surface-container-highest)',
      color: 'var(--gp-on-surface-variant)',
      font: 'var(--type-label-medium)',
      fontWeight: 700,
      textAlign: 'center',
      ...style
    }
  }, count);
}
Object.assign(__ds_scope, { CountPill });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/CountPill.jsx", error: String((e && e.message) || e) }); }

// design/components/core/Divider.jsx
try { (() => {
/** A hairline between rows inside a card. 24px of air around it by default,
 *  which is what the app's DividerTheme sets. */
function Divider({
  inset = 0,
  tight = false,
  style
}) {
  return /*#__PURE__*/React.createElement("hr", {
    style: {
      border: 0,
      height: 1,
      background: 'var(--border-hairline)',
      margin: tight ? '0' : 'calc(var(--gap-xl) / 2) 0',
      marginInlineStart: inset,
      ...style
    }
  });
}
Object.assign(__ds_scope, { Divider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/Divider.jsx", error: String((e && e.message) || e) }); }

// design/components/core/Icon.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Material Symbols glyph. The Flutter app draws every icon from the Material
 *  icon font (Icons.*); this is the same set, loaded as a webfont. */
function Icon({
  name,
  size = 24,
  fill = false,
  color = 'currentColor',
  weight = 400,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("span", _extends({
    className: "gp-icon",
    "aria-hidden": "true",
    style: {
      fontFamily: 'var(--font-icon)',
      fontSize: size,
      lineHeight: 1,
      color,
      fontVariationSettings: `"FILL" ${fill ? 1 : 0}, "wght" ${weight}, "GRAD" 0, "opsz" ${size}`,
      display: 'inline-block',
      userSelect: 'none',
      ...style
    }
  }, rest), name);
}
Object.assign(__ds_scope, { Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/Icon.jsx", error: String((e && e.message) || e) }); }

// design/components/core/Avatar.jsx
try { (() => {
function initialsOf(name = '') {
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '';
  return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

/** A player's picture, or their initials when they have not set one. The
 *  initials are not a placeholder — they are what an account without a picture
 *  looks like, and a picture that fails to load falls back to the same thing. */
function Avatar({
  src,
  name,
  size = 40,
  tone = 'accent',
  style
}) {
  const initials = initialsOf(name);
  const tonal = tone === 'accent' ? {
    background: 'var(--gp-primary-container)',
    color: 'var(--gp-on-primary-container)'
  } : {
    background: 'var(--gp-surface-container-highest)',
    color: 'var(--gp-on-surface-variant)'
  };
  return /*#__PURE__*/React.createElement("span", {
    style: {
      width: size,
      height: size,
      borderRadius: '50%',
      overflow: 'hidden',
      flex: '0 0 auto',
      display: 'inline-grid',
      placeItems: 'center',
      ...tonal,
      font: 'var(--type-title-medium)',
      fontSize: size * 0.4,
      fontWeight: 600,
      ...style
    }
  }, src ? /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: "",
    style: {
      width: '100%',
      height: '100%',
      objectFit: 'cover'
    }
  }) : initials || /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "person",
    size: size * 0.55,
    fill: true
  }));
}
Object.assign(__ds_scope, { Avatar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/Avatar.jsx", error: String((e && e.message) || e) }); }

// design/components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const FILLS = {
  filled: {
    background: 'var(--gp-primary-deep)',
    color: '#fff',
    border: '1.5px solid transparent'
  },
  tonal: {
    background: 'var(--status-open-bg)',
    color: 'var(--status-open-fg)',
    border: '1.5px solid transparent'
  },
  outlined: {
    background: 'transparent',
    color: 'var(--gp-primary-deep)',
    border: '1.5px solid #CBD8C9'
  },
  text: {
    background: 'transparent',
    color: 'var(--gp-primary)',
    border: '1.5px solid transparent'
  },
  onHero: {
    background: '#fff',
    color: 'var(--gp-primary-deep)',
    border: '1.5px solid transparent'
  },
  ghost: {
    background: 'rgba(255,255,255,.16)',
    color: '#fff',
    border: '1.5px solid rgba(255,255,255,.3)'
  },
  danger: {
    background: 'var(--gp-error)',
    color: 'var(--gp-on-error)',
    border: '1.5px solid transparent'
  }
};

/** Every button is one of three heights and the same 16px corner. Only the fill
 *  changes, which is what lets a filled button read as the primary action
 *  without needing to be bigger than the one beside it. */
function Button({
  variant = 'filled',
  size = 'default',
  icon,
  trailingIcon,
  fullWidth,
  disabled,
  loading,
  onClick,
  children,
  style,
  ...rest
}) {
  const fill = FILLS[variant] || FILLS.filled;
  const height = size === 'small' ? 38 : size === 'compact' ? 44 : 52;
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled || loading,
    onClick: onClick,
    style: {
      ...fill,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 'var(--gap-sm)',
      minHeight: height,
      width: fullWidth ? '100%' : undefined,
      padding: variant === 'text' ? '0 var(--gap-md)' : size === 'small' ? '0 14px' : '0 20px',
      borderRadius: 'var(--radius-control)',
      font: '700 14.5px/1 var(--font-sans)',
      cursor: disabled || loading ? 'default' : 'pointer',
      opacity: disabled ? 0.38 : 1,
      whiteSpace: 'nowrap',
      transition: 'filter var(--duration-fast) var(--easing-standard), opacity var(--duration-fast)',
      ...style
    },
    onMouseEnter: e => {
      if (!disabled && !loading) e.currentTarget.style.filter = 'brightness(0.94)';
    },
    onMouseLeave: e => {
      e.currentTarget.style.filter = 'none';
    }
  }, rest), loading ? /*#__PURE__*/React.createElement(Spinner, null) : icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18
  }) : null, loading ? null : children, !loading && trailingIcon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: trailingIcon,
    size: 18
  }) : null);
}
function Spinner() {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      width: 18,
      height: 18,
      borderRadius: '50%',
      border: '2px solid currentColor',
      borderTopColor: 'transparent',
      animation: 'gp-spin 900ms linear infinite',
      display: 'inline-block'
    }
  });
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/Button.jsx", error: String((e && e.message) || e) }); }

// design/components/core/Chip.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const TONES = {
  open: {
    background: 'var(--status-open-bg)',
    color: 'var(--status-open-fg)'
  },
  full: {
    background: 'var(--status-full-bg)',
    color: 'var(--status-full-fg)'
  },
  completed: {
    background: '#E4E9E2',
    color: 'var(--gp-on-surface-variant)'
  },
  reserve: {
    background: 'var(--gp-tertiary-container)',
    color: 'var(--gp-on-tertiary-container)'
  },
  neutral: {
    background: '#EDF1EB',
    color: 'var(--gp-on-surface-variant)'
  },
  accent: {
    background: 'var(--status-open-bg)',
    color: 'var(--status-open-fg)'
  },
  danger: {
    background: 'var(--gp-error-container)',
    color: 'var(--gp-on-error-container)'
  },
  onHero: {
    background: 'rgba(255,255,255,.16)',
    color: '#fff'
  },
  role: {
    background: '#EDF1EB',
    color: 'var(--gp-on-surface-variant)'
  }
};

/** A pill that reports state. Never interactive — a chip in this product is a
 *  reading, not a control. `square` is the role marker: a role is a property of
 *  a person, not a status of a thing, and the shape says so. */
function Chip({
  tone = 'neutral',
  icon,
  square,
  children,
  style,
  ...rest
}) {
  const t = TONES[tone] || TONES.neutral;
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      ...t,
      display: 'inline-flex',
      alignItems: 'center',
      gap: 5,
      padding: square ? '3px 8px' : '5px 11px',
      borderRadius: square ? 6 : 'var(--radius-pill)',
      font: square ? '700 10.5px/1.6 var(--font-sans)' : '700 11.5px/1.35 var(--font-sans)',
      letterSpacing: square ? '.06em' : 0,
      textTransform: square ? 'uppercase' : 'none',
      whiteSpace: 'nowrap',
      ...style
    }
  }, rest), icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 14
  }) : null, children);
}
Object.assign(__ds_scope, { Chip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/Chip.jsx", error: String((e && e.message) || e) }); }

// design/components/core/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** A bar action: a glyph in a 44px tap target, optionally carrying a count. */
function IconButton({
  icon,
  label,
  badge,
  active,
  onHero,
  onClick,
  size = 22,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    "aria-label": label,
    title: label,
    onClick: onClick,
    style: {
      position: 'relative',
      width: 44,
      height: 44,
      flex: '0 0 auto',
      borderRadius: 'var(--radius-pill)',
      border: 'none',
      background: 'transparent',
      cursor: 'pointer',
      color: onHero ? '#fff' : active ? 'var(--gp-primary)' : 'var(--gp-on-surface)',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'background var(--duration-fast) var(--easing-standard)',
      ...style
    },
    onMouseEnter: e => {
      e.currentTarget.style.background = onHero ? 'rgba(255,255,255,.14)' : 'rgba(17,26,19,.06)';
    },
    onMouseLeave: e => {
      e.currentTarget.style.background = 'transparent';
    }
  }, rest), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: size
  }), badge ? /*#__PURE__*/React.createElement("span", {
    dir: "ltr",
    style: {
      position: 'absolute',
      top: 5,
      insetInlineEnd: 3,
      minWidth: 16,
      height: 16,
      padding: '0 4px',
      borderRadius: 'var(--radius-pill)',
      background: '#E4572E',
      color: '#fff',
      font: '700 10px/16px var(--font-sans)',
      textAlign: 'center'
    }
  }, badge) : null);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/BottomSheet.jsx
try { (() => {
/** The action sheet. Every action carries its label here, which is what an app
 *  bar full of glyphs could not do — and the destructive one sits last, behind
 *  a divider, in the error colour. */
function BottomSheet({
  title,
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--gp-surface-container-low)',
      borderRadius: 'var(--radius-lg) var(--radius-lg) 0 0',
      boxShadow: 'var(--elevation-sheet)',
      paddingBottom: 'var(--gap-sm)',
      overflow: 'hidden',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      placeItems: 'center',
      padding: 'var(--gap-md) 0'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 32,
      height: 4,
      borderRadius: 'var(--radius-pill)',
      background: 'var(--gp-outline-variant)'
    }
  })), title ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 var(--page-margin) var(--gap-md)',
      font: 'var(--type-title-medium)',
      color: 'var(--gp-on-surface)'
    }
  }, title) : null, children);
}
Object.assign(__ds_scope, { BottomSheet });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/BottomSheet.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/Dialog.jsx
try { (() => {
/** A confirmation. Two actions: a text button that backs out, and the real one
 *  — filled, and in the error colour when it destroys something. */
function Dialog({
  title,
  body,
  cancelLabel = 'Back',
  confirmLabel,
  destructive,
  onCancel,
  onConfirm,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 360,
      background: 'var(--gp-surface-container-high)',
      borderRadius: 'var(--radius-md)',
      padding: 'var(--gap-xl)',
      boxShadow: 'var(--elevation-menu)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("h3", {
    style: {
      font: 'var(--type-title-large)',
      letterSpacing: 'var(--tracking-title-large)',
      color: 'var(--gp-on-surface)'
    }
  }, title), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 'var(--gap-md) 0 var(--gap-xl)',
      font: 'var(--type-body-medium)',
      color: 'var(--gp-on-surface-variant)'
    }
  }, body), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'flex-end',
      gap: 'var(--gap-sm)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "text",
    size: "compact",
    onClick: onCancel
  }, cancelLabel), /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: destructive ? 'danger' : 'filled',
    size: "compact",
    onClick: onConfirm
  }, confirmLabel)));
}
Object.assign(__ds_scope, { Dialog });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/Dialog.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/EmptyState.jsx
try { (() => {
/** Nothing to show, and that is normal. The glyph sits in a tinted disc rather
 *  than floating on the background: at this size a bare outline glyph reads as
 *  a missing image instead of as an illustration. */
function EmptyState({
  icon = 'sports_soccer',
  title,
  message,
  note,
  action,
  tone = 'neutral',
  style
}) {
  const disc = tone === 'accent' ? {
    background: 'var(--gp-primary-container)',
    color: 'var(--gp-on-primary-container)'
  } : {
    background: 'var(--gp-surface-container-highest)',
    color: 'var(--gp-on-surface-variant)'
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      textAlign: 'center',
      padding: 'var(--gap-xxl) var(--gap-xl)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 64,
      height: 64,
      borderRadius: '50%',
      display: 'grid',
      placeItems: 'center',
      ...disc
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 32
  })), title ? /*#__PURE__*/React.createElement("h3", {
    style: {
      font: 'var(--type-title-medium)',
      color: 'var(--gp-on-surface)',
      marginTop: 'var(--gap-lg)'
    }
  }, title) : null, /*#__PURE__*/React.createElement("p", {
    style: {
      margin: title ? 'var(--gap-sm) 0 0' : 'var(--gap-lg) 0 0',
      font: 'var(--type-body-medium)',
      color: 'var(--gp-on-surface-variant)',
      maxWidth: 380,
      whiteSpace: 'pre-line',
      unicodeBidi: 'plaintext'
    }
  }, message), note ? /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 'var(--gap-md) 0 0',
      font: 'var(--type-body-small)',
      color: 'var(--gp-outline)'
    }
  }, note) : null, action ? /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--gap-xl)'
    }
  }, action) : null);
}
Object.assign(__ds_scope, { EmptyState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/EmptyState.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/ErrorState.jsx
try { (() => {
/** A read that failed, and the one thing worth offering about it. The retry is
 *  outlined rather than filled on purpose: filling the only control on the
 *  screen would make a recovery look like the screen's purpose. */
function ErrorState({
  message = 'Failed to load data.',
  retryLabel = 'Retry',
  onRetry,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      textAlign: 'center',
      padding: 'var(--gap-xxl) var(--gap-xl)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 64,
      height: 64,
      borderRadius: '50%',
      display: 'grid',
      placeItems: 'center',
      background: 'var(--gp-error-container)',
      color: 'var(--gp-on-error-container)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "cloud_off",
    size: 32
  })), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 'var(--gap-lg) 0 0',
      font: 'var(--type-body-medium)',
      color: 'var(--gp-on-surface)',
      maxWidth: 380,
      unicodeBidi: 'plaintext'
    }
  }, message), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--gap-xl)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "outlined",
    icon: "refresh",
    onClick: onRetry
  }, retryLabel)));
}
Object.assign(__ds_scope, { ErrorState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/ErrorState.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/LoadingState.jsx
try { (() => {
/** One spinner, the same size in the same place on every screen that has no
 *  shape to placeholder. */
function LoadingState({
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      placeItems: 'center',
      padding: 'var(--gap-xxl)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("style", null, '@keyframes gp-spin{to{transform:rotate(360deg)}}'), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 32,
      height: 32,
      borderRadius: '50%',
      border: '3px solid var(--gp-primary)',
      borderTopColor: 'transparent',
      animation: 'gp-spin 900ms linear infinite',
      display: 'block'
    }
  }));
}
Object.assign(__ds_scope, { LoadingState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/LoadingState.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/Skeleton.jsx
try { (() => {
/** A placeholder the shape of what is coming. Screens whose content has no
 *  fixed shape use LoadingState instead. */
function Skeleton({
  width = '100%',
  height = 16,
  radius = 'var(--radius-sm)',
  style
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("style", null, '@keyframes gp-skeleton{0%,100%{opacity:.45}50%{opacity:.9}}@keyframes gp-spin{to{transform:rotate(360deg)}}'), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      width,
      height,
      borderRadius: radius,
      background: 'var(--gp-surface-container-highest)',
      animation: 'gp-skeleton 1400ms var(--easing-standard) infinite',
      ...style
    }
  }));
}
Object.assign(__ds_scope, { Skeleton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/Skeleton.jsx", error: String((e && e.message) || e) }); }

// design/components/feedback/Snackbar.jsx
try { (() => {
/** The floating confirmation. Inverse surface, 12px corner, 16px inset — one
 *  sentence about something that has already happened. */
function Snackbar({
  children,
  action,
  onAction,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-lg)',
      background: 'var(--gp-inverse-surface)',
      color: 'var(--gp-inverse-on-surface)',
      borderRadius: 'var(--radius-sm)',
      padding: 'var(--gap-lg)',
      boxShadow: 'var(--elevation-snackbar)',
      margin: 'var(--gap-lg)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: 'var(--type-body-medium)',
      unicodeBidi: 'plaintext'
    }
  }, children), action ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    style: {
      border: 'none',
      background: 'transparent',
      color: 'var(--gp-inverse-primary)',
      font: 'var(--type-label-large)',
      cursor: 'pointer',
      padding: 0
    }
  }, action) : null);
}
Object.assign(__ds_scope, { Snackbar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/feedback/Snackbar.jsx", error: String((e && e.message) || e) }); }

// design/components/football/CapacityBar.jsx
try { (() => {
/** How full a match is, as a bar rather than a ring: a ring is a decoration
 *  that happens to encode a number, and at 44px it cannot show which segment is
 *  reserve. The bar can — starting places, then reserve places, then what is
 *  left — which is the whole question a player is asking. */
function CapacityBar({
  registered,
  starting,
  reserve = 0,
  status = 'open',
  showLabel = true,
  compact,
  style
}) {
  const total = starting + reserve;
  const filledStart = Math.min(registered, starting);
  const filledRes = Math.max(0, Math.min(registered - starting, reserve));
  const fill = status === 'full' ? 'var(--gp-warn)' : status === 'completed' ? '#A8B2A6' : 'var(--gp-primary-mid)';
  const seg = (n, bg, key) => Array.from({
    length: n
  }).map((_, i) => /*#__PURE__*/React.createElement("span", {
    key: key + i,
    style: {
      flex: 1,
      height: compact ? 5 : 7,
      borderRadius: 3,
      background: bg,
      minWidth: 2
    }
  }));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-md)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      gap: 2.5,
      minWidth: 0
    }
  }, seg(filledStart, fill, 'a'), seg(starting - filledStart, '#DCE4DA', 'b'), reserve ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: 6,
      flex: '0 0 auto'
    }
  }) : null, seg(filledRes, 'var(--gp-tertiary)', 'c'), seg(reserve - filledRes, '#E3EAE1', 'd')), showLabel ? /*#__PURE__*/React.createElement("span", {
    dir: "ltr",
    style: {
      font: '600 12px/1 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)',
      fontVariantNumeric: 'tabular-nums',
      whiteSpace: 'nowrap'
    }
  }, registered, "/", starting) : null);
}
Object.assign(__ds_scope, { CapacityBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/CapacityBar.jsx", error: String((e && e.message) || e) }); }

// design/components/football/CommunityLogo.jsx
try { (() => {
/** A community's crest: its initials in a rounded square. Not a circle — a
 *  circle is a person in this product, and the two appear side by side often
 *  enough that the shape has to carry the difference. The schema has no logo
 *  column, so this *is* a community's mark. */
function CommunityLogo({
  name = '',
  size = 56,
  onHero,
  style
}) {
  const initials = String(name).trim().split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase();
  const skin = onHero ? {
    background: 'rgba(255,255,255,.15)',
    border: '1.5px solid rgba(255,255,255,.3)',
    color: '#fff'
  } : {
    background: 'var(--status-open-bg)',
    border: 'none',
    color: 'var(--gp-primary-deep)'
  };
  return /*#__PURE__*/React.createElement("span", {
    style: {
      width: size,
      height: size,
      flex: '0 0 auto',
      borderRadius: 'var(--radius-crest)',
      display: 'grid',
      placeItems: 'center',
      boxSizing: 'border-box',
      ...skin,
      fontFamily: 'var(--font-sans)',
      fontSize: size * 0.34,
      fontWeight: 700,
      lineHeight: 1,
      letterSpacing: '-.5px',
      ...style
    }
  }, initials || /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "groups",
    size: size * 0.46,
    fill: true
  }));
}
Object.assign(__ds_scope, { CommunityLogo });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/CommunityLogo.jsx", error: String((e && e.message) || e) }); }

// design/components/football/CommunityCard.jsx
try { (() => {
/** One community in a list. Crest, name, role, description, then the two
 *  counts that say whether it is worth opening. No action button: opening it is
 *  the action, and a card that repeats itself in a button reads as two things. */
function CommunityCard({
  name,
  description,
  memberCount,
  upcomingCount,
  role,
  codeRequired,
  trailing,
  onClick,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      padding: 'var(--gap-md) var(--gap-lg)',
      display: 'flex',
      gap: 'var(--gap-md)',
      alignItems: 'center',
      cursor: onClick ? 'pointer' : undefined,
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.CommunityLogo, {
    name: name,
    size: 46
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 7,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 1 auto',
      minWidth: 0,
      font: '700 15.5px/1.3 var(--font-sans)',
      letterSpacing: '-.2px',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, name), codeRequired ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "key",
    size: 14,
    color: "var(--gp-outline)"
  }) : null, role && role !== 'Player' ? /*#__PURE__*/React.createElement(__ds_scope.Chip, {
    tone: "role",
    square: true
  }, role) : null), description ? /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12.5px/1.4 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)',
      marginTop: 3,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, description) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 14,
      marginTop: 7,
      font: '400 12px/1 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, memberCount != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      gap: 5,
      alignItems: 'center',
      whiteSpace: 'nowrap'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "person",
    size: 13
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      unicodeBidi: 'plaintext'
    }
  }, memberCount, " members")) : null, upcomingCount ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      gap: 5,
      alignItems: 'center',
      whiteSpace: 'nowrap'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "sports_soccer",
    size: 13
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      unicodeBidi: 'plaintext'
    }
  }, upcomingCount, " upcoming")) : null)), trailing);
}
Object.assign(__ds_scope, { CommunityCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/CommunityCard.jsx", error: String((e && e.message) || e) }); }

// design/components/football/DateTile.jsx
try { (() => {
/** The day a match falls on, stacked: weekday, date, month. A played match
 *  shows a tick — its date has stopped being the useful thing about it. */
function DateTile({
  weekday,
  day,
  month,
  status = 'open',
  size = 'default',
  style
}) {
  const done = status === 'completed';
  const w = size === 'compact' ? 46 : 50,
    h = size === 'compact' ? 52 : 56;
  const bg = done ? '#EDF1EB' : status === 'full' ? 'var(--gp-warn-container)' : 'var(--status-open-bg)';
  const fg = done ? 'var(--gp-outline)' : status === 'full' ? 'var(--gp-on-warn-container)' : 'var(--gp-primary-deep)';
  const soft = done ? 'var(--gp-outline)' : status === 'full' ? 'var(--gp-on-warn-container)' : 'var(--gp-primary-mid)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: w,
      height: h,
      flex: '0 0 auto',
      background: bg,
      borderRadius: 14,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      ...style
    }
  }, done ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "event_available",
    size: 22,
    fill: true,
    color: fg
  }) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 10px/1 var(--font-sans)',
      letterSpacing: '.08em',
      color: soft
    }
  }, String(weekday).toUpperCase()), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px/1.2 var(--font-sans)',
      letterSpacing: '-.8px',
      color: fg
    }
  }, day), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '500 10px/1 var(--font-sans)',
      color: soft
    }
  }, month)));
}
Object.assign(__ds_scope, { DateTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/DateTile.jsx", error: String((e && e.message) || e) }); }

// design/components/football/MemberRow.jsx
try { (() => {
/** A person in a community list. Name, then role and position on one quiet
 *  line, then whatever this screen lets you do about them. The role marker is
 *  a square chip so it never reads as a match status. */
function MemberRow({
  name,
  role,
  position,
  you,
  trailing,
  onClick,
  style
}) {
  const meta = [role, position].filter(Boolean).join(' · ');
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-md)',
      padding: '10px var(--gap-lg)',
      minHeight: 56,
      cursor: onClick ? 'pointer' : undefined,
      transition: 'background var(--duration-fast) var(--easing-standard)',
      ...style
    },
    onMouseEnter: e => {
      if (onClick) e.currentTarget.style.background = '#F7FAF6';
    },
    onMouseLeave: e => {
      if (onClick) e.currentTarget.style.background = 'transparent';
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Avatar, {
    name: name,
    size: 38,
    tone: role === 'Owner' ? 'accent' : 'neutral'
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 1 auto',
      minWidth: 0,
      font: '600 14.5px/1.3 var(--font-sans)',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, name), you ? /*#__PURE__*/React.createElement(__ds_scope.Chip, {
    tone: "open",
    square: true
  }, "You") : null), meta ? /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12px/1.3 var(--font-sans)',
      color: 'var(--gp-outline)',
      marginTop: 3,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, meta) : null), trailing, onClick && !trailing ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron_right",
    size: 19,
    color: "#BFC9BE"
  }) : null);
}
Object.assign(__ds_scope, { MemberRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/MemberRow.jsx", error: String((e && e.message) || e) }); }

// design/components/football/ParticipantRow.jsx
try { (() => {
const TAG = {
  Goalkeeper: 'GK',
  Defender: 'DEF',
  Midfielder: 'MID',
  Forward: 'FWD'
};

/** A participant on a roster. A professional guest has no profile and therefore
 *  no position: saying what they are is more use than leaving the line blank. */
function ParticipantRow({
  name,
  position,
  guest,
  index,
  reserve,
  you,
  handle,
  trailing,
  onClick,
  style
}) {
  const label = guest ? `Professional (${name})` : name;
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-md)',
      padding: '9px var(--gap-lg)',
      minHeight: 54,
      cursor: onClick ? 'pointer' : undefined,
      ...style
    }
  }, handle ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "drag_indicator",
    size: 20,
    color: "#BFC9BE"
  }) : null, index != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: 18,
      textAlign: 'center',
      font: '500 12px/1 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, index) : null, /*#__PURE__*/React.createElement(__ds_scope.Avatar, {
    name: guest ? '' : name,
    size: 34,
    tone: reserve ? 'neutral' : 'accent'
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 1 auto',
      minWidth: 0,
      font: '600 14px/1.3 var(--font-sans)',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, label), you ? /*#__PURE__*/React.createElement(__ds_scope.Chip, {
    tone: "open",
    square: true
  }, "You") : null), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12px/1.3 var(--font-sans)',
      color: reserve ? 'var(--gp-tertiary)' : 'var(--gp-outline)',
      marginTop: 3
    }
  }, guest ? 'Professional guest' : reserve ? 'Reserve · ' + position : position)), trailing || (position && !guest ? /*#__PURE__*/React.createElement(__ds_scope.Chip, {
    tone: "role",
    square: true
  }, TAG[position] || position) : null));
}
Object.assign(__ds_scope, { ParticipantRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/ParticipantRow.jsx", error: String((e && e.message) || e) }); }

// design/components/football/RatingHero.jsx
try { (() => {
/** The one figure a player's record is built around. Flat deep green, not a
 *  gradient: the rating is a number to read, and a gradient behind a number is
 *  decoration the number did not ask for. */
function RatingHero({
  value,
  label = 'Current rating',
  form,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--gp-primary-deep)',
      color: '#fff',
      borderRadius: 'var(--radius-card)',
      padding: 'var(--gap-lg) var(--gap-xl)',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-xl)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 36px/1 var(--font-sans)',
      letterSpacing: '-1.6px'
    }
  }, value), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '500 10.5px/1 var(--font-sans)',
      letterSpacing: '.08em',
      textTransform: 'uppercase',
      color: 'rgba(255,255,255,.7)',
      marginTop: 7
    }
  }, label)), form && form.length ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      alignItems: 'flex-end',
      gap: 5,
      height: 46
    }
  }, form.map((v, i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      flex: 1,
      height: Math.max(8, v / 5 * 46),
      borderRadius: 3,
      background: i === form.length - 1 ? '#fff' : 'rgba(255,255,255,.3)'
    }
  }))) : null);
}
Object.assign(__ds_scope, { RatingHero });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/RatingHero.jsx", error: String((e && e.message) || e) }); }

// design/components/football/StatTile.jsx
try { (() => {
/** One figure from a record. Laid out three per row: at two per row the tiles
 *  are wider than the number needs and the grid starts to look like a
 *  dashboard. */
function StatTile({
  icon,
  value,
  label,
  tone = 'accent',
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-control)',
      boxShadow: 'var(--elevation-card)',
      padding: '12px 8px',
      textAlign: 'center',
      ...style
    }
  }, icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18,
    fill: true,
    color: tone === 'accent' ? 'var(--gp-primary-mid)' : 'var(--gp-on-surface-variant)'
  }) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 20px/1 var(--font-sans)',
      letterSpacing: '-.5px',
      color: 'var(--gp-on-surface)',
      marginTop: 8
    }
  }, value), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '500 11px/1.3 var(--font-sans)',
      color: 'var(--gp-outline)',
      marginTop: 6
    }
  }, label));
}
Object.assign(__ds_scope, { StatTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/StatTile.jsx", error: String((e && e.message) || e) }); }

// design/components/forms/SegmentedControl.jsx
try { (() => {
/** Material's segmented button: one row, one selection, an outline around the
 *  set and a tonal fill behind the chosen segment. Used for the statistics
 *  period and the language switch. */
function SegmentedControl({
  options,
  value,
  onChange,
  fullWidth = true,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "radiogroup",
    style: {
      display: fullWidth ? 'grid' : 'inline-grid',
      gridAutoFlow: 'column',
      gridAutoColumns: '1fr',
      border: '1px solid var(--gp-outline-variant)',
      borderRadius: 'var(--radius-pill)',
      overflow: 'hidden',
      width: fullWidth ? '100%' : undefined,
      ...style
    }
  }, options.map((o, i) => {
    const v = o.value ?? o;
    const label = o.label ?? o;
    const selected = v === value;
    return /*#__PURE__*/React.createElement("button", {
      key: v,
      type: "button",
      role: "radio",
      "aria-checked": selected,
      onClick: () => onChange && onChange(v),
      style: {
        minHeight: 40,
        padding: '0 var(--gap-sm)',
        border: 'none',
        borderInlineStart: i === 0 ? 'none' : '1px solid var(--gp-outline-variant)',
        background: selected ? 'var(--gp-secondary-container)' : 'transparent',
        color: selected ? 'var(--gp-on-secondary-container)' : 'var(--gp-on-surface)',
        font: 'var(--type-label-large)',
        cursor: 'pointer',
        transition: 'background var(--duration-fast) var(--easing-standard)'
      }
    }, label);
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/forms/SegmentedControl.jsx", error: String((e && e.message) || e) }); }

// design/components/forms/SelectField.jsx
try { (() => {
/** The same shell as TextField, holding a value the reader picks rather than
 *  types: a position, a role, a date. `onClick` opens a picker; `options`
 *  turns it into a native select. */
function SelectField({
  label,
  value,
  placeholder = '—',
  options,
  error,
  icon = 'expand_more',
  disabled,
  onChange,
  onClick,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: disabled ? undefined : onClick,
    style: {
      position: 'relative',
      background: 'var(--gp-surface-container-low)',
      borderRadius: 'var(--radius-sm)',
      border: `${error ? 2 : 1}px solid ${error ? 'var(--gp-error)' : 'var(--gp-outline-variant)'}`,
      padding: '22px 16px 10px',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-sm)',
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.38 : 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 8,
      insetInlineStart: 16,
      font: 'var(--type-label-small)',
      color: error ? 'var(--gp-error)' : 'var(--gp-on-surface-variant)'
    }
  }, label), options ? /*#__PURE__*/React.createElement("select", {
    value: value,
    onChange: onChange,
    disabled: disabled,
    style: {
      flex: 1,
      border: 'none',
      background: 'transparent',
      outline: 'none',
      appearance: 'none',
      font: 'var(--type-body-large)',
      color: 'var(--gp-on-surface)',
      padding: 0,
      cursor: 'pointer'
    }
  }, options.map(o => /*#__PURE__*/React.createElement("option", {
    key: o.value ?? o,
    value: o.value ?? o
  }, o.label ?? o))) : /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: 'var(--type-body-large)',
      color: value ? 'var(--gp-on-surface)' : 'var(--gp-outline)'
    }
  }, value || placeholder), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 20,
    color: "var(--gp-on-surface-variant)"
  })), error ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body-small)',
      color: 'var(--gp-error)',
      padding: '0 var(--gap-lg)'
    }
  }, error) : null);
}
Object.assign(__ds_scope, { SelectField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/forms/SelectField.jsx", error: String((e && e.message) || e) }); }

// design/components/forms/SwitchRow.jsx
try { (() => {
/** A setting: what it does, what it means, and the switch. The subtitle is not
 *  optional decoration — every push setting in the app explains its effect. */
function SwitchRow({
  label,
  subtitle,
  checked,
  onChange,
  disabled,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-lg)',
      padding: 'var(--gap-md) var(--gap-lg)',
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.38 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      font: 'var(--type-body-large)',
      color: 'var(--gp-on-surface)'
    }
  }, label), subtitle ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      font: 'var(--type-body-small)',
      color: 'var(--gp-on-surface-variant)',
      marginTop: 2
    }
  }, subtitle) : null), /*#__PURE__*/React.createElement("span", {
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      width: 52,
      height: 32,
      flex: '0 0 auto',
      borderRadius: 'var(--radius-pill)',
      background: checked ? 'var(--gp-primary)' : 'var(--gp-surface-container-highest)',
      border: checked ? '2px solid var(--gp-primary)' : '2px solid var(--gp-outline)',
      position: 'relative',
      transition: 'background var(--duration-fast) var(--easing-standard)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: '50%',
      transform: 'translateY(-50%)',
      insetInlineStart: checked ? 22 : 4,
      width: checked ? 24 : 16,
      height: checked ? 24 : 16,
      borderRadius: '50%',
      background: checked ? 'var(--gp-on-primary)' : 'var(--gp-outline)',
      transition: 'all var(--duration-fast) var(--easing-standard)'
    }
  })));
}
Object.assign(__ds_scope, { SwitchRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/forms/SwitchRow.jsx", error: String((e && e.message) || e) }); }

// design/components/forms/TextField.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** A filled field with a hairline border and a floating label. Focus thickens
 *  the border to 2px in the primary colour; that is the whole focus treatment. */
function TextField({
  label,
  value,
  defaultValue,
  placeholder,
  helper,
  error,
  counter,
  maxLength,
  type = 'text',
  multiline,
  rows = 3,
  disabled,
  onChange,
  id,
  style,
  ...rest
}) {
  const [focused, setFocused] = React.useState(false);
  const borderColor = error ? 'var(--gp-error)' : focused ? 'var(--gp-primary)' : 'var(--gp-outline-variant)';
  const Field = multiline ? 'textarea' : 'input';
  const fieldId = id || `gp-${label}`;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      background: 'var(--gp-surface-container-low)',
      borderRadius: 'var(--radius-sm)',
      border: `${focused || error ? 2 : 1}px solid ${borderColor}`,
      padding: `${focused || error ? 15 : 16}px`,
      paddingTop: 22,
      paddingBottom: 10,
      opacity: disabled ? 0.38 : 1,
      transition: 'border-color var(--duration-fast) var(--easing-standard)'
    }
  }, /*#__PURE__*/React.createElement("label", {
    htmlFor: fieldId,
    style: {
      position: 'absolute',
      top: 8,
      insetInlineStart: 16,
      font: 'var(--type-label-small)',
      color: error ? 'var(--gp-error)' : focused ? 'var(--gp-primary)' : 'var(--gp-on-surface-variant)'
    }
  }, label), /*#__PURE__*/React.createElement(Field, _extends({
    id: fieldId,
    type: type,
    value: value,
    defaultValue: defaultValue,
    rows: multiline ? rows : undefined,
    placeholder: placeholder,
    disabled: disabled,
    maxLength: maxLength,
    onChange: onChange,
    onFocus: () => setFocused(true),
    onBlur: () => setFocused(false),
    style: {
      width: '100%',
      border: 'none',
      outline: 'none',
      background: 'transparent',
      resize: 'vertical',
      font: 'var(--type-body-large)',
      color: 'var(--gp-on-surface)',
      padding: 0
    }
  }, rest))), error || helper || counter ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--gap-sm)',
      padding: '0 var(--gap-lg)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body-small)',
      color: error ? 'var(--gp-error)' : 'var(--gp-on-surface-variant)',
      flex: 1
    }
  }, error || helper), counter ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body-small)',
      color: 'var(--gp-on-surface-variant)'
    }
  }, counter) : null) : null);
}
Object.assign(__ds_scope, { TextField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/forms/TextField.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/AppHeader.jsx
try { (() => {
/** One bar for every signed-in screen. The screen's own actions come first;
 *  the signed-in player is appended after them, where it stays put as those
 *  actions differ from screen to screen. */
function AppHeader({
  title,
  onBack,
  actions,
  user,
  scrolled,
  style
}) {
  return /*#__PURE__*/React.createElement("header", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-xs)',
      minHeight: 'var(--appbar-height)',
      padding: '0 var(--gap-xs)',
      background: 'var(--gp-surface)',
      boxShadow: scrolled ? 'var(--elevation-scrolled)' : 'none',
      position: 'sticky',
      top: 0,
      zIndex: 10,
      ...style
    }
  }, onBack ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Back",
    onClick: onBack,
    style: {
      width: 48,
      height: 48,
      border: 'none',
      background: 'transparent',
      cursor: 'pointer',
      display: 'grid',
      placeItems: 'center',
      color: 'var(--gp-on-surface)',
      borderRadius: 'var(--radius-pill)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "arrow_back",
    size: 24
  })) : /*#__PURE__*/React.createElement("span", {
    style: {
      width: 'var(--gap-md)'
    }
  }), /*#__PURE__*/React.createElement("h1", {
    style: {
      flex: 1,
      minWidth: 0,
      font: 'var(--type-title-large)',
      letterSpacing: 'var(--tracking-title-large)',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 0
    }
  }, actions), user ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-sm)',
      padding: '0 var(--gap-md) 0 var(--gap-xs)',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Avatar, {
    name: user.name,
    src: user.avatarUrl,
    size: 32
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-label-large)',
      color: 'var(--gp-on-surface)',
      maxWidth: 96,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, String(user.name || '').trim().split(/\s+/)[0])) : null);
}
Object.assign(__ds_scope, { AppHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/AppHeader.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/BottomNav.jsx
try { (() => {
/** The floating navigation bar. It sits above the content rather than closing
 *  the page off, so a scrolling list runs under it and the screen keeps its
 *  full height. The selected destination is a filled pill behind the icon *and*
 *  a heavier label — either alone is easy to miss at a glance. */
function BottomNav({
  items,
  value,
  onChange,
  floating = true,
  style
}) {
  const base = {
    display: 'grid',
    gridAutoFlow: 'column',
    gridAutoColumns: '1fr',
    height: 58,
    background: 'var(--surface-card)'
  };
  const pos = floating ? {
    position: 'absolute',
    insetInline: 14,
    bottom: 14,
    borderRadius: 'var(--radius-control)',
    boxShadow: 'var(--elevation-nav)',
    zIndex: 5
  } : {
    borderTop: '1px solid var(--border-hairline)'
  };
  return /*#__PURE__*/React.createElement("nav", {
    style: {
      ...base,
      ...pos,
      ...style
    }
  }, items.map(it => {
    const on = it.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: it.value,
      type: "button",
      onClick: () => onChange && onChange(it.value),
      style: {
        border: 'none',
        background: 'transparent',
        cursor: 'pointer',
        padding: 0,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 3
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 46,
        height: 26,
        borderRadius: 13,
        display: 'grid',
        placeItems: 'center',
        background: on ? 'var(--status-open-bg)' : 'transparent',
        transition: 'background var(--duration-fast) var(--easing-standard)'
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: it.icon,
      size: 21,
      fill: on,
      color: on ? 'var(--gp-primary-deep)' : '#8C978D'
    })), /*#__PURE__*/React.createElement("span", {
      style: {
        font: (on ? 600 : 400) + ' 10.5px/1 var(--font-sans)',
        color: on ? 'var(--gp-primary-deep)' : '#8C978D'
      }
    }, it.label));
  }));
}
Object.assign(__ds_scope, { BottomNav });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/BottomNav.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** The product's surface. White, 20px, and a shadow so light it registers as a
 *  contact edge rather than as lift — two nearly invisible stops instead of one
 *  visible one. A list of cards must still read as one page, which is why the
 *  shadow is this quiet and why there is no border under it. */
function Card({
  padded = true,
  interactive,
  outlined,
  onClick,
  children,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("div", _extends({
    onClick: onClick,
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      overflow: 'hidden',
      border: outlined ? '1.5px solid #CBE3CF' : 'none',
      padding: padded ? 'var(--gap-lg)' : 0,
      cursor: interactive || onClick ? 'pointer' : undefined,
      transition: 'background var(--duration-fast) var(--easing-standard)',
      ...style
    },
    onMouseEnter: e => {
      if (interactive || onClick) e.currentTarget.style.background = '#F7FAF6';
    },
    onMouseLeave: e => {
      if (interactive || onClick) e.currentTarget.style.background = 'var(--surface-card)';
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/Card.jsx", error: String((e && e.message) || e) }); }

// design/components/football/MatchCard.jsx
try { (() => {
/** One match in a list. Date tile, name and status on one line, the community
 *  crest under it where the list spans several, then the facts and the capacity
 *  bar. Four rows, no action button: a list is for choosing which match to
 *  open, and a card with its own button competes with the card itself. */
function MatchCard({
  title,
  communityName,
  location,
  time,
  weekday,
  day,
  month,
  status = 'open',
  registered,
  starting,
  reserve = 0,
  statusLabel,
  outlined,
  onClick,
  style
}) {
  const label = statusLabel || {
    open: 'Open',
    full: 'Full',
    completed: 'Played'
  }[status];
  return /*#__PURE__*/React.createElement(__ds_scope.Card, {
    padded: false,
    outlined: outlined,
    onClick: onClick,
    style: style
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 'var(--gap-md) var(--gap-lg)',
      display: 'flex',
      gap: 'var(--gap-md)',
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.DateTile, {
    weekday: weekday,
    day: day,
    month: month,
    status: status
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-sm)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      font: '700 15.5px/1.3 var(--font-sans)',
      letterSpacing: '-.2px',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, title), /*#__PURE__*/React.createElement(__ds_scope.Chip, {
    tone: status
  }, label)), communityName ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      marginTop: 5
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.CommunityLogo, {
    name: communityName,
    size: 17
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 12px/1 var(--font-sans)',
      color: 'var(--gp-primary)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, communityName)) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5,
      marginTop: 5,
      font: '400 12.5px/1.4 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "schedule",
    size: 13,
    color: "var(--gp-outline)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      unicodeBidi: 'isolate',
      whiteSpace: 'nowrap',
      flex: '0 0 auto'
    }
  }, time), location ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .5,
      flex: '0 0 auto'
    }
  }, "\xB7"), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "place",
    size: 13,
    color: "var(--gp-outline)",
    style: {
      flex: '0 0 auto'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, location)) : null), registered != null ? /*#__PURE__*/React.createElement(__ds_scope.CapacityBar, {
    compact: true,
    registered: registered,
    starting: starting,
    reserve: reserve,
    status: status,
    style: {
      marginTop: 9
    }
  }) : null)));
}
Object.assign(__ds_scope, { MatchCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/football/MatchCard.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/FootNote.jsx
try { (() => {
/** A quiet closing sentence: what the figures above mean, or why something is
 *  not offered. Never an error, and styled so it cannot be mistaken for one. */
function FootNote({
  children,
  align = 'start',
  style
}) {
  return /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      padding: 'var(--gap-xl) var(--page-margin) var(--gap-lg)',
      font: 'var(--type-body-small)',
      color: 'var(--gp-outline)',
      textAlign: align,
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { FootNote });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/FootNote.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/Hero.jsx
try { (() => {
/** The crest hero: a flat deep-green block that says whose community you are
 *  inside before you read anything. Deliberately short — it carries a bar row,
 *  an identity row and at most one action row, and then it stops. The ball is
 *  a single 190px glyph at 5.5% white, most of it outside the block, so it
 *  reads as texture rather than as an icon somebody forgot to position. */
function Hero({
  children,
  ball = true,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--bg-hero)',
      position: 'relative',
      overflow: 'hidden',
      flex: '0 0 auto',
      paddingBottom: 30,
      ...style
    }
  }, ball ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      right: -44,
      top: -50,
      opacity: 1,
      pointerEvents: 'none',
      lineHeight: 0
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "sports_soccer",
    size: 190,
    fill: true,
    color: "rgba(255,255,255,.055)"
  })) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, children));
}

/** The bar inside a Hero: back, title, actions — all reversed out. */
function HeroBar({
  title,
  onBack,
  right
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      height: 50,
      padding: '0 6px',
      color: '#fff'
    }
  }, onBack ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Back",
    onClick: onBack,
    style: {
      width: 44,
      height: 44,
      border: 'none',
      background: 'transparent',
      color: '#fff',
      display: 'grid',
      placeItems: 'center',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "arrow_back",
    size: 22
  })) : /*#__PURE__*/React.createElement("span", {
    style: {
      width: 14
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      font: '500 16px/1.2 var(--font-sans)',
      opacity: .9,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, title), right);
}

/** The light page that slides over the bottom of a Hero. Everything below the
 *  identity lives in here. */
function Sheet({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--surface-sheet)',
      borderRadius: 'var(--radius-sheet) var(--radius-sheet) 0 0',
      marginTop: -22,
      position: 'relative',
      paddingTop: 6,
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { Hero, HeroBar, Sheet });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/Hero.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/ListRow.jsx
try { (() => {
/** One row in a grouped card: a leading glyph or avatar, a title, a quieter
 *  second line, and whatever the row is for on the end. */
function ListRow({
  icon,
  leading,
  title,
  subtitle,
  trailing,
  chevron,
  danger,
  onClick,
  style
}) {
  const color = danger ? 'var(--gp-error)' : 'var(--gp-on-surface)';
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-lg)',
      padding: 'var(--gap-md) var(--gap-lg)',
      minHeight: 'var(--tap-min)',
      cursor: onClick ? 'pointer' : undefined,
      transition: 'background var(--duration-fast) var(--easing-standard)',
      ...style
    },
    onMouseEnter: e => {
      if (onClick) e.currentTarget.style.background = 'color-mix(in srgb, var(--gp-on-surface) 5%, transparent)';
    },
    onMouseLeave: e => {
      if (onClick) e.currentTarget.style.background = 'transparent';
    }
  }, leading || (icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 24,
    color: danger ? 'var(--gp-error)' : 'var(--gp-on-surface-variant)'
  }) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--type-body-large)',
      color,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, title), subtitle ? /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--type-body-small)',
      color: 'var(--text-muted)',
      marginTop: 2
    }
  }, subtitle) : null), trailing, chevron ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron_right",
    size: 22,
    color: "var(--gp-on-surface-variant)"
  }) : null);
}
Object.assign(__ds_scope, { ListRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/ListRow.jsx", error: String((e && e.message) || e) }); }

// design/components/layout/SectionHeading.jsx
try { (() => {
/** A heading over a group of rows. Tight by Club standards — 18px above, 9px
 *  below — because the sheet already separates sections and a 32px gap on top
 *  of that is space the list wanted. */
function SectionHeading({
  title,
  count,
  action,
  onAction,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--gap-sm)',
      padding: '18px var(--gap-lg) 9px',
      ...style
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      flex: 1,
      minWidth: 0,
      font: '700 16.5px/1.25 var(--font-sans)',
      letterSpacing: '-.3px',
      color: 'var(--gp-on-surface)'
    }
  }, title, count != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--gp-outline)',
      fontWeight: 500,
      unicodeBidi: 'isolate'
    }
  }, " \xB7 ", count) : null), action ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    style: {
      border: 'none',
      background: 'transparent',
      font: '600 13px/1 var(--font-sans)',
      color: 'var(--gp-primary)',
      cursor: 'pointer',
      padding: 0
    }
  }, action) : null);
}
Object.assign(__ds_scope, { SectionHeading });
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/components/layout/SectionHeading.jsx", error: String((e && e.message) || e) }); }

// design/screens/App.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  BottomNav,
  Snackbar,
  Hero,
  HeroBar,
  Sheet,
  IconButton,
  SectionHeading,
  CommunityLogo,
  Chip,
  Button,
  ListRow,
  Icon,
  MatchCard,
  EmptyState,
  Avatar
} = window.GoPlayDesignSystem_984b89;
const {
  TaskBar,
  TaskBody,
  RowGroup
} = window;
function DiscoverScreen({
  go,
  review
}) {
  const d = window.T(review);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    right: /*#__PURE__*/React.createElement(IconButton, {
      icon: "search",
      label: "Search",
      onHero: true
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 9
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 28,
      height: 28,
      borderRadius: 14,
      background: '#fff',
      display: 'grid',
      placeItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sports_soccer",
    size: 17,
    fill: true,
    color: "var(--gp-primary-deep)"
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 16px/1 var(--font-sans)',
      letterSpacing: '.2px'
    }
  }, "Go Play")), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 23px/1.2 var(--font-sans)',
      letterSpacing: '-.8px',
      marginTop: 12
    }
  }, "Football, with your people."), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 13px/1.45 var(--font-sans)',
      color: 'rgba(255,255,255,.78)',
      marginTop: 5
    }
  }, "Find a community near you and take your place on the pitch."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    icon: "groups"
  }, d.communities.length, " communities"), /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    icon: "sports_soccer"
  }, "2 upcoming")))), /*#__PURE__*/React.createElement(Sheet, null, /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Open matches",
    count: 2
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 9,
      padding: '0 14px'
    }
  }, d.matches.filter(m => m.status !== 'completed').map(m => /*#__PURE__*/React.createElement(MatchCard, _extends({
    key: m.id
  }, m, {
    weekday: m.wd,
    day: m.d,
    month: m.mo,
    communityName: m.community,
    onClick: () => go('match', m)
  })))), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Communities",
    count: d.communities.length
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px 92px'
    }
  }, /*#__PURE__*/React.createElement(RowGroup, null, d.communities.map(c => /*#__PURE__*/React.createElement(ListRow, {
    key: c.id,
    leading: /*#__PURE__*/React.createElement(CommunityLogo, {
      name: c.name,
      size: 40
    }),
    title: c.name,
    subtitle: c.members + ' members · ' + c.upcoming + ' upcoming',
    trailing: /*#__PURE__*/React.createElement(Button, {
      variant: "tonal",
      size: "small",
      onClick: () => go('community', c)
    }, "Open"),
    onClick: () => go('community', c)
  }))))));
}
function CommunitiesScreen({
  go,
  review
}) {
  const d = window.T(review);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    right: /*#__PURE__*/React.createElement(IconButton, {
      icon: "add",
      label: "Create community",
      onHero: true
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 23px/1.2 var(--font-sans)',
      letterSpacing: '-.8px'
    }
  }, "Your communities"), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 13px/1.45 var(--font-sans)',
      color: 'rgba(255,255,255,.75)',
      marginTop: 5
    }
  }, "You organize one and play in another."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      marginTop: 14
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "onHero",
    size: "compact",
    icon: "add",
    style: {
      flex: 1
    }
  }, "Create"), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "compact",
    icon: "key"
  }, "Join by code")))), /*#__PURE__*/React.createElement(Sheet, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10,
      padding: '10px 14px 92px'
    }
  }, d.communities.map(c => /*#__PURE__*/React.createElement("div", {
    key: c.id,
    onClick: () => go('community', c),
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      padding: 14,
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 13,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(CommunityLogo, {
    name: c.name,
    size: 48
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 7
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      font: '700 16px/1.3 var(--font-sans)',
      letterSpacing: '-.2px',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, c.name), c.codeRequired ? /*#__PURE__*/React.createElement(Icon, {
    name: "key",
    size: 14,
    color: "var(--gp-outline)"
  }) : null, c.role !== 'Player' ? /*#__PURE__*/React.createElement(Chip, {
    tone: "role",
    square: true
  }, c.role) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12.5px/1.4 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)',
      marginTop: 3
    }
  }, c.description), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 14,
      marginTop: 7,
      font: '400 12px/1 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      gap: 5,
      alignItems: 'center',
      whiteSpace: 'nowrap'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "person",
    size: 13
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      unicodeBidi: 'plaintext'
    }
  }, c.members, " members")), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      gap: 5,
      alignItems: 'center',
      whiteSpace: 'nowrap'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sports_soccer",
    size: 13
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      unicodeBidi: 'plaintext'
    }
  }, c.upcoming, " upcoming"))))))))));
}
function NotificationsScreen({
  go,
  review
}) {
  const items = [{
    icon: 'group_add',
    title: 'You were promoted from the reserve list to the starting players.',
    when: 'Thursday practice · 2h ago',
    unread: true
  }, {
    icon: 'schedule',
    title: 'The match time has changed.',
    when: 'Friday five-a-side · yesterday',
    unread: true
  }, {
    icon: 'scoreboard',
    title: 'The match result was saved.',
    when: 'Sunday league · 2 days ago',
    unread: true
  }, {
    icon: 'groups',
    title: 'You have been invited to a community.',
    when: 'Al Bahar · 3 days ago'
  }];
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TaskBar, {
    title: "Notifications",
    onBack: () => go('home'),
    right: /*#__PURE__*/React.createElement(Button, {
      variant: "text",
      size: "small"
    }, "Mark all read")
  }), /*#__PURE__*/React.createElement(TaskBody, {
    style: {
      padding: '12px 14px 20px'
    }
  }, /*#__PURE__*/React.createElement(RowGroup, null, items.map((n, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      display: 'flex',
      gap: 13,
      padding: '13px 16px',
      background: n.unread ? 'rgba(220,238,223,.35)' : 'transparent'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 34,
      height: 34,
      borderRadius: 17,
      flex: '0 0 auto',
      background: 'var(--status-open-bg)',
      display: 'grid',
      placeItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: n.icon,
    size: 18,
    color: "var(--gp-primary-deep)"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: (n.unread ? 600 : 400) + ' 14px/1.4 var(--font-sans)',
      color: 'var(--gp-on-surface)'
    }
  }, n.title), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12px/1.3 var(--font-sans)',
      color: 'var(--gp-outline)',
      marginTop: 4
    }
  }, n.when)), n.unread ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: 8,
      height: 8,
      borderRadius: 4,
      background: 'var(--gp-primary-mid)',
      marginTop: 6,
      flex: '0 0 auto'
    }
  }) : null)))));
}
const TABS = [{
  value: 'discover',
  label: 'Discover',
  icon: 'explore'
}, {
  value: 'home',
  label: 'Home',
  icon: 'home'
}, {
  value: 'communities',
  label: 'Communities',
  icon: 'groups'
}];
/** Screens that are a task rather than a place drop the bottom nav. */
const TASKS = ['create', 'members', 'teams', 'arrange', 'result', 'notifications'];

/** The review harness. Not part of the product — it is how a reviewer or a
 *  Flutter engineer reaches the states and roles the design has to cover
 *  without needing a backend to produce them. */
function ReviewBar({
  review,
  set
}) {
  const Group = ({
    label,
    k,
    opts
  }) => /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 10px/1 var(--font-sans)',
      letterSpacing: '.08em',
      textTransform: 'uppercase',
      color: '#7C857B'
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      background: '#fff',
      borderRadius: 8,
      padding: 2,
      boxShadow: 'var(--elevation-card)'
    }
  }, opts.map(([v, l]) => /*#__PURE__*/React.createElement("button", {
    key: v,
    type: "button",
    onClick: () => set(k, v),
    style: {
      border: 'none',
      cursor: 'pointer',
      padding: '5px 9px',
      borderRadius: 6,
      background: review[k] === v ? 'var(--gp-primary-deep)' : 'transparent',
      color: review[k] === v ? '#fff' : '#5D6A5E',
      font: '600 11px/1 var(--font-sans)'
    }
  }, l))));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: 14,
      justifyContent: 'center',
      alignItems: 'center',
      padding: '10px 12px'
    }
  }, /*#__PURE__*/React.createElement(Group, {
    label: "Role",
    k: "role",
    opts: [['Owner', 'Owner'], ['Admin', 'Admin'], ['Player', 'Player']]
  }), /*#__PURE__*/React.createElement(Group, {
    label: "State",
    k: "state",
    opts: [['ready', 'Populated'], ['loading', 'Loading'], ['empty', 'Empty'], ['error', 'Error']]
  }), /*#__PURE__*/React.createElement(Group, {
    label: "You",
    k: "reg",
    opts: [['confirmed', 'Confirmed'], ['reserve', 'Reserve'], ['none', 'Not in']]
  }), /*#__PURE__*/React.createElement(Group, {
    label: "Dir",
    k: "dir",
    opts: [['ltr', 'EN'], ['rtl', 'العربية']]
  }), /*#__PURE__*/React.createElement(Group, {
    label: "Width",
    k: "w",
    opts: [[320, '320'], [412, '412'], [480, '480']]
  }));
}
function App() {
  const [screen, setScreen] = React.useState('home');
  const [review, setReview] = React.useState({
    role: 'Admin',
    state: 'ready',
    reg: 'confirmed',
    dir: 'ltr',
    w: 412
  });
  const setR = (k, v) => setReview(r => ({
    ...r,
    [k]: v
  }));
  const [community, setCommunity] = React.useState(null);
  const [match, setMatch] = React.useState(null);
  const [toast, setToast] = React.useState(null);
  const scroller = React.useRef(null);
  React.useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = 0;
  }, [screen]);
  React.useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3200);
    return () => clearTimeout(t);
  }, [toast]);
  const go = (next, payload) => {
    if (payload && payload.members != null) setCommunity(payload);
    if (payload && payload.starting != null) setMatch(payload);
    setScreen(next);
  };
  const tab = TABS.some(t => t.value === screen) ? screen : ['community', 'members', 'create', 'invite', 'landing'].includes(screen) ? 'communities' : 'home';
  const p = {
    go,
    review,
    setToast
  };
  const body = {
    discover: /*#__PURE__*/React.createElement(DiscoverScreen, p),
    home: /*#__PURE__*/React.createElement(window.HomeScreen, p),
    communities: /*#__PURE__*/React.createElement(CommunitiesScreen, p),
    community: /*#__PURE__*/React.createElement(window.CommunityDetailsScreen, _extends({}, p, {
      community: community
    })),
    match: /*#__PURE__*/React.createElement(window.MatchDetailsScreen, _extends({}, p, {
      match: match
    })),
    create: /*#__PURE__*/React.createElement(window.CreateMatchScreen, _extends({}, p, {
      community: community
    })),
    profile: /*#__PURE__*/React.createElement(window.ProfileScreen, p),
    members: /*#__PURE__*/React.createElement(window.MembersScreen, _extends({}, p, {
      community: community
    })),
    invite: /*#__PURE__*/React.createElement(window.InviteScreen, _extends({}, p, {
      community: community,
      mode: "share"
    })),
    landing: /*#__PURE__*/React.createElement(window.InviteScreen, _extends({}, p, {
      community: community,
      mode: "landing"
    })),
    teams: /*#__PURE__*/React.createElement(window.TeamsScreen, _extends({}, p, {
      match: match,
      initial: "teams"
    })),
    arrange: /*#__PURE__*/React.createElement(window.TeamsScreen, _extends({}, p, {
      match: match,
      initial: "arrange"
    })),
    result: /*#__PURE__*/React.createElement(window.ResultScreen, _extends({}, p, {
      match: match
    })),
    notifications: /*#__PURE__*/React.createElement(NotificationsScreen, p)
  }[screen];
  const isTask = TASKS.includes(screen);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement(ReviewBar, {
    review: review,
    set: setR
  }), /*#__PURE__*/React.createElement("div", {
    className: "gp-phone",
    ref: scroller,
    dir: review.dir,
    style: {
      width: review.w,
      fontFamily: review.dir === 'rtl' ? 'var(--font-arabic)' : 'var(--font-sans)'
    }
  }, body, toast ? /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      insetInline: 0,
      bottom: isTask ? 76 : 82,
      zIndex: 40
    }
  }, /*#__PURE__*/React.createElement(Snackbar, null, toast)) : null, !isTask ? /*#__PURE__*/React.createElement(BottomNav, {
    items: TABS,
    value: tab,
    onChange: v => setScreen(v)
  }) : null));
}
window.GoPlayApp = App;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/App.jsx", error: String((e && e.message) || e) }); }

// design/screens/CommunityDetails.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Hero,
  HeroBar,
  Sheet,
  IconButton,
  CommunityLogo,
  Chip,
  Button,
  SectionHeading,
  MatchCard,
  MemberRow,
  EmptyState,
  BottomSheet,
  ListRow,
  Divider,
  Icon
} = window.GoPlayDesignSystem_984b89;
function CommunityDetailsScreen({
  go,
  community,
  review
}) {
  const d = window.T(review);
  const base = community || d.communities[0];
  const c = {
    ...base,
    role: review && review.role || base.role
  };
  const [sheet, setSheet] = React.useState(false);
  const [tab, setTab] = React.useState('upcoming');
  const mine = d.matches.filter(m => m.community === c.name);
  const shown = mine.filter(m => tab === 'upcoming' ? m.status !== 'completed' : m.status === 'completed');
  const organizer = c.role === 'Admin' || c.role === 'Owner';
  const alt = window.screenState(review, {
    empty: /*#__PURE__*/React.createElement(EmptyState, {
      icon: "sports_soccer",
      message: "No matches in this community yet."
    })
  });
  const Tab = ({
    v,
    label,
    n
  }) => /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => setTab(v),
    style: {
      border: 'none',
      background: 'transparent',
      cursor: 'pointer',
      padding: '0 0 9px',
      font: (tab === v ? 700 : 500) + ' 14px/1 var(--font-sans)',
      whiteSpace: 'nowrap',
      color: tab === v ? 'var(--gp-on-surface)' : 'var(--gp-outline)',
      borderBottom: '2.5px solid ' + (tab === v ? 'var(--gp-primary-deep)' : 'transparent')
    }
  }, label, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--gp-outline)',
      fontWeight: 500,
      unicodeBidi: 'isolate'
    }
  }, " \xB7 ", n));
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    onBack: () => go('communities'),
    right: /*#__PURE__*/React.createElement(IconButton, {
      icon: "more_vert",
      label: "Community actions",
      onHero: true,
      onClick: () => setSheet(true)
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px',
      color: '#fff',
      display: 'flex',
      gap: 14,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(CommunityLogo, {
    name: c.name,
    size: 58,
    onHero: true
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 22px/1.2 var(--font-sans)',
      letterSpacing: '-.7px',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, c.name), c.role !== 'Player' ? /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    square: true
  }, c.role) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12.5px/1.4 var(--font-sans)',
      color: 'rgba(255,255,255,.75)',
      marginTop: 4
    }
  }, c.description))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 18,
      padding: '14px 18px 0',
      color: '#fff'
    }
  }, [[c.members, 'Members'], [c.upcoming, 'Upcoming'], [c.played, 'Played']].map(([v, l]) => /*#__PURE__*/React.createElement("div", {
    key: l,
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 5
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px/1 var(--font-sans)'
    }
  }, v), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 12px/1 var(--font-sans)',
      color: 'rgba(255,255,255,.7)',
      whiteSpace: 'nowrap'
    }
  }, l)))), organizer ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      padding: '14px 18px 0'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "onHero",
    size: "compact",
    icon: "add",
    style: {
      flex: 1
    },
    onClick: () => go('create', c)
  }, "Create match"), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "compact",
    icon: "person_add",
    onClick: () => go('invite', c)
  }, "Invite")) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 18px 0'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "onHero",
    size: "compact",
    fullWidth: true
  }, "Join community"))), /*#__PURE__*/React.createElement(Sheet, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 20,
      padding: '12px 18px 0',
      borderBottom: '1px solid var(--border-hairline)',
      margin: '0 0 4px'
    }
  }, /*#__PURE__*/React.createElement(Tab, {
    v: "upcoming",
    label: "Matches",
    n: mine.filter(m => m.status !== 'completed').length
  }), /*#__PURE__*/React.createElement(Tab, {
    v: "past",
    label: "Played",
    n: mine.filter(m => m.status === 'completed').length
  })), alt ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 12
    }
  }, alt) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 9,
      padding: '10px 14px 0'
    }
  }, shown.length ? shown.map(m => /*#__PURE__*/React.createElement(MatchCard, _extends({
    key: m.id
  }, m, {
    weekday: m.wd,
    day: m.d,
    month: m.mo,
    onClick: () => go('match', m)
  }))) : /*#__PURE__*/React.createElement(EmptyState, {
    icon: "sports_soccer",
    message: "No matches in this community yet."
  })), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Members",
    count: c.members,
    action: organizer ? 'Manage' : undefined,
    onAction: () => go('members', c)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px 92px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      overflow: 'hidden'
    }
  }, d.members.slice(0, 3).map((m, i) => /*#__PURE__*/React.createElement("div", {
    key: m.name,
    style: {
      borderTop: i ? '1px solid var(--border-hairline)' : 'none'
    }
  }, /*#__PURE__*/React.createElement(MemberRow, _extends({}, m, {
    trailing: m.role !== 'Player' ? /*#__PURE__*/React.createElement(Chip, {
      tone: "role",
      square: true
    }, m.role) : null
  })))), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--border-hairline)',
      padding: '11px 16px',
      textAlign: 'center',
      font: '600 13.5px/1 var(--font-sans)',
      color: 'var(--gp-primary)',
      cursor: 'pointer'
    },
    onClick: () => go('members', c)
  }, "See all ", c.members, " members"))))), sheet ? /*#__PURE__*/React.createElement("div", {
    onClick: () => setSheet(false),
    style: {
      position: 'absolute',
      inset: 0,
      background: 'rgba(0,0,0,.34)',
      display: 'flex',
      alignItems: 'flex-end',
      zIndex: 30
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '100%'
    },
    onClick: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement(BottomSheet, {
    title: c.name
  }, organizer ? /*#__PURE__*/React.createElement(ListRow, {
    icon: "ios_share",
    title: "Share invitation",
    subtitle: 'Join code ' + (c.code || '—'),
    onClick: () => {
      setSheet(false);
      go('invite', c);
    }
  }) : null, c.role === 'Owner' ? /*#__PURE__*/React.createElement(ListRow, {
    icon: "lock_open",
    title: "Joining",
    subtitle: c.joinPolicy,
    onClick: () => setSheet(false)
  }) : null, /*#__PURE__*/React.createElement(ListRow, {
    icon: "group",
    title: "Manage members",
    onClick: () => {
      setSheet(false);
      go('members', c);
    }
  }), /*#__PURE__*/React.createElement(ListRow, {
    icon: "logout",
    title: "Leave community",
    onClick: () => setSheet(false)
  }), c.role === 'Owner' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Divider, {
    tight: true
  }), /*#__PURE__*/React.createElement(ListRow, {
    icon: "delete",
    title: "Delete community",
    danger: true,
    onClick: () => setSheet(false)
  })) : null))) : null);
}
window.CommunityDetailsScreen = CommunityDetailsScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/CommunityDetails.jsx", error: String((e && e.message) || e) }); }

// design/screens/CreateMatch.jsx
try { (() => {
const {
  Button,
  Icon,
  CapacityBar,
  Chip,
  CommunityLogo
} = window.GoPlayDesignSystem_984b89;
const {
  TaskBar,
  TaskBody,
  RowGroup,
  FieldRow,
  ActionBar
} = window;
function CreateMatchScreen({
  go,
  community,
  setToast,
  review
}) {
  const d = window.T(review);
  const c = community || d.communities[0];
  const [n, setN] = React.useState(12);
  const [saving, setSaving] = React.useState(false);
  const step = v => setN(Math.max(4, Math.min(30, n + v)));
  // The harness's error state stands in for a failed submit — the one failure
  // this screen can actually show a reader.
  const invalid = review && review.state === 'error';
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TaskBar, {
    title: "Create match",
    onBack: () => go('community', c)
  }), /*#__PURE__*/React.createElement(TaskBody, {
    style: {
      padding: '12px 14px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '0 4px'
    }
  }, /*#__PURE__*/React.createElement(CommunityLogo, {
    name: c.name,
    size: 18
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/1.3 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)'
    }
  }, "In ", /*#__PURE__*/React.createElement("b", {
    style: {
      color: 'var(--gp-on-surface)'
    }
  }, c.name), " \xB7 ", c.members, " members will be notified")), /*#__PURE__*/React.createElement(RowGroup, null, /*#__PURE__*/React.createElement(FieldRow, {
    label: "Match title",
    value: invalid ? '—' : d.matches[0].title,
    onClick: () => {},
    error: invalid ? 'Match title is required.' : undefined
  }), /*#__PURE__*/React.createElement(FieldRow, {
    label: "Location",
    value: d.matches[0].location,
    onClick: () => {}
  })), /*#__PURE__*/React.createElement(RowGroup, null, /*#__PURE__*/React.createElement(FieldRow, {
    icon: "calendar_month",
    label: "Date",
    value: "Thursday, 13 August 2026",
    onClick: () => {}
  }), /*#__PURE__*/React.createElement(FieldRow, {
    icon: "schedule",
    label: "Start",
    value: "17:25",
    onClick: () => {}
  }), /*#__PURE__*/React.createElement(FieldRow, {
    icon: "schedule",
    label: "End",
    value: invalid ? '17:00' : '18:35',
    onClick: () => {},
    error: invalid ? 'The end time must be after the start time.' : undefined
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '600 11.5px/1 var(--font-sans)',
      letterSpacing: '.06em',
      textTransform: 'uppercase',
      color: 'var(--gp-outline)'
    }
  }, "Starting players"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 8,
      marginTop: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 30px/1 var(--font-sans)',
      letterSpacing: '-1.3px',
      color: 'var(--gp-primary-deep)'
    }
  }, n), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/1 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)'
    }
  }, n % 2 === 0 ? n / 2 + ' a side' : 'uneven sides'))), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => step(-2),
    style: {
      width: 40,
      height: 40,
      borderRadius: 20,
      border: '1.5px solid #CBD8C9',
      background: 'transparent',
      display: 'grid',
      placeItems: 'center',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "remove",
    size: 19,
    color: "var(--gp-primary-deep)"
  })), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => step(2),
    style: {
      width: 40,
      height: 40,
      borderRadius: 20,
      border: 'none',
      background: 'var(--gp-primary-deep)',
      display: 'grid',
      placeItems: 'center',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "add",
    size: 19,
    color: "#fff"
  }))), /*#__PURE__*/React.createElement(CapacityBar, {
    registered: 0,
    starting: n,
    reserve: 6,
    showLabel: false,
    style: {
      marginTop: 15
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      marginTop: 8,
      font: '400 12px/1 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", {
    style: {
      color: 'var(--gp-on-surface)'
    }
  }, n), " starting"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", {
    style: {
      color: 'var(--gp-on-surface)'
    }
  }, "6"), " reserve \xB7 ", n + 6, " maximum"))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 4px',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "Reserve places are added automatically and cannot be entered by hand. Between 4 and 30 starting players.")), /*#__PURE__*/React.createElement(ActionBar, null, /*#__PURE__*/React.createElement(Button, {
    fullWidth: true,
    loading: saving,
    disabled: invalid,
    onClick: () => {
      setSaving(true);
      setTimeout(() => {
        setSaving(false);
        setToast('Match created. Community members were notified.');
        go('community', c);
      }, 700);
    }
  }, "Create match")));
}
window.CreateMatchScreen = CreateMatchScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/CreateMatch.jsx", error: String((e && e.message) || e) }); }

// design/screens/Home.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Hero,
  HeroBar,
  Sheet,
  IconButton,
  Avatar,
  Chip,
  Icon,
  Button,
  SectionHeading,
  MatchCard,
  CapacityBar,
  Card,
  EmptyState
} = window.GoPlayDesignSystem_984b89;
function HomeScreen({
  go,
  review
}) {
  const d = window.T(review);
  const next = d.matches.find(m => m.next);
  const rest = d.matches.filter(m => !m.next);
  const alt = window.screenState(review);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    right: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(IconButton, {
      icon: "notifications",
      label: "Notifications",
      badge: d.notifications,
      onHero: true,
      onClick: () => go('notifications')
    }), /*#__PURE__*/React.createElement("span", {
      onClick: () => go('profile'),
      style: {
        marginInlineEnd: 12,
        cursor: 'pointer'
      }
    }, /*#__PURE__*/React.createElement(Avatar, {
      name: d.me.name,
      size: 30,
      tone: "neutral",
      style: {
        background: 'rgba(255,255,255,.18)',
        color: '#fff'
      }
    })))
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px 2px',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 13px/1 var(--font-sans)',
      color: 'rgba(255,255,255,.7)'
    }
  }, "Thursday 13 August"), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 24px/1.2 var(--font-sans)',
      letterSpacing: '-.8px',
      marginTop: 5
    }
  }, "Hello, Yousuf"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    icon: "groups"
  }, d.communities.length, " communities"), /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    icon: "sports_soccer"
  }, "2 upcoming")))), /*#__PURE__*/React.createElement(Sheet, null, alt ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 14
    }
  }, alt) : /*#__PURE__*/React.createElement(React.Fragment, null, next ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 14px 0'
    }
  }, /*#__PURE__*/React.createElement(Card, {
    outlined: true,
    padded: false,
    onClick: () => go('match', next)
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 16px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 7
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 7,
      height: 7,
      borderRadius: 4,
      background: 'var(--gp-primary-mid)'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 11.5px/1 var(--font-sans)',
      letterSpacing: '.08em',
      textTransform: 'uppercase',
      color: 'var(--gp-primary)',
      whiteSpace: 'nowrap'
    }
  }, "Next up \xB7 in ", next.inHours, "h"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Chip, {
    tone: "open"
  }, "You are in")), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 19px/1.25 var(--font-sans)',
      letterSpacing: '-.4px',
      color: 'var(--gp-on-surface)',
      marginTop: 9
    }
  }, next.title), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5,
      marginTop: 5,
      minWidth: 0,
      font: '400 13px/1.4 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "schedule",
    size: 14,
    color: "var(--gp-outline)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      unicodeBidi: 'isolate',
      whiteSpace: 'nowrap',
      flex: '0 0 auto'
    }
  }, next.time), /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .5,
      flex: '0 0 auto'
    }
  }, "\xB7"), /*#__PURE__*/React.createElement(Icon, {
    name: "place",
    size: 14,
    color: "var(--gp-outline)",
    style: {
      flex: '0 0 auto'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, next.location)), /*#__PURE__*/React.createElement(CapacityBar, {
    registered: next.registered,
    starting: next.starting,
    reserve: next.reserve,
    style: {
      marginTop: 12
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      marginTop: 13
    }
  }, /*#__PURE__*/React.createElement(Button, {
    size: "compact",
    style: {
      flex: 1
    },
    onClick: () => go('match', next)
  }, "Open match"), /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    size: "compact",
    icon: "ios_share",
    "aria-label": "Share"
  }))))) : null, /*#__PURE__*/React.createElement(SectionHeading, {
    title: "This week",
    count: rest.length,
    action: "See all"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 9,
      padding: '0 14px'
    }
  }, rest.length ? rest.map(m => /*#__PURE__*/React.createElement(MatchCard, _extends({
    key: m.id
  }, m, {
    weekday: m.wd,
    day: m.d,
    month: m.mo,
    communityName: m.community,
    onClick: () => go('match', m)
  }))) : /*#__PURE__*/React.createElement(EmptyState, {
    icon: "sports_soccer",
    tone: "accent",
    message: 'No upcoming matches.\nJoin a community to get started.'
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 92
    }
  })));
}
window.HomeScreen = HomeScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Home.jsx", error: String((e && e.message) || e) }); }

// design/screens/Invite.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Hero,
  HeroBar,
  Sheet,
  CommunityLogo,
  Chip,
  Button,
  Icon,
  SectionHeading,
  MatchCard,
  IconButton
} = window.GoPlayDesignSystem_984b89;
const {
  RowGroup
} = window;

/** Two readings of one screen: the organizer sharing an invitation, and the
 *  person who has just opened the link. `mode` decides which. */
function InviteScreen({
  go,
  community,
  mode = 'share',
  setToast,
  review
}) {
  const d = window.T(review);
  const c = community || d.communities[0];
  const link = 'goplay.app/join/' + (c.code || '481902').replace(/\s/g, '');
  const visitor = mode === 'landing';
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    title: visitor ? 'Invitation' : 'Share invitation',
    onBack: () => go(visitor ? 'discover' : 'community', c)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px',
      color: '#fff',
      textAlign: visitor ? 'center' : 'start'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: visitor ? 'column' : 'row',
      alignItems: 'center',
      gap: visitor ? 12 : 14
    }
  }, /*#__PURE__*/React.createElement(CommunityLogo, {
    name: c.name,
    size: visitor ? 66 : 52,
    onHero: true
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: visitor ? undefined : 1,
      minWidth: 0,
      textAlign: visitor ? 'center' : 'start'
    }
  }, visitor ? /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 13px/1 var(--font-sans)',
      color: 'rgba(255,255,255,.72)'
    }
  }, "You have been invited to") : null, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 22px/1.2 var(--font-sans)',
      letterSpacing: '-.7px',
      marginTop: visitor ? 6 : 0
    }
  }, c.name), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12.5px/1.4 var(--font-sans)',
      color: 'rgba(255,255,255,.75)',
      marginTop: 4
    }
  }, c.description))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 7,
      marginTop: 13,
      justifyContent: visitor ? 'center' : 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    icon: "group"
  }, c.members, " members"), /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero",
    icon: "sports_soccer"
  }, c.upcoming, " upcoming")))), /*#__PURE__*/React.createElement(Sheet, null, visitor ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '10px 14px 0'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    fullWidth: true,
    onClick: () => {
      setToast('You joined the community.');
      go('community', c);
    }
  }, "Join community"), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'center',
      padding: '12px 0 0',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "Joining puts you in the community. Matches are browsed afterwards \u2014 you register for each one yourself.")), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "What is coming up",
    count: c.upcoming
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 9,
      padding: '0 14px 24px'
    }
  }, d.matches.filter(m => m.community === c.name && m.status !== 'completed').map(m => /*#__PURE__*/React.createElement(MatchCard, _extends({
    key: m.id
  }, m, {
    weekday: m.wd,
    day: m.d,
    month: m.mo
  }))))) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '10px 14px 0',
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      padding: '18px 16px',
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '600 11.5px/1 var(--font-sans)',
      letterSpacing: '.06em',
      textTransform: 'uppercase',
      color: 'var(--gp-outline)'
    }
  }, "Join code"), /*#__PURE__*/React.createElement("div", {
    dir: "ltr",
    style: {
      font: '700 34px/1 var(--font-sans)',
      letterSpacing: '6px',
      color: 'var(--gp-primary-deep)',
      marginTop: 12
    }
  }, c.code), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      marginTop: 16
    }
  }, /*#__PURE__*/React.createElement(Button, {
    size: "compact",
    icon: "ios_share",
    style: {
      flex: 1
    },
    onClick: () => setToast('Invitation copied. Paste it wherever you share it.')
  }, "Share link"), /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    size: "compact",
    icon: "content_copy",
    onClick: () => setToast('Join code copied')
  }, "Copy code"))), /*#__PURE__*/React.createElement(RowGroup, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '13px 16px'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: 19,
    color: "var(--gp-outline)"
  }), /*#__PURE__*/React.createElement("span", {
    dir: "ltr",
    style: {
      flex: 1,
      minWidth: 0,
      font: '400 14px/1.3 var(--font-sans)',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      textAlign: 'start'
    }
  }, link), /*#__PURE__*/React.createElement(Button, {
    variant: "text",
    size: "small",
    onClick: () => setToast('Invitation copied. Paste it wherever you share it.')
  }, "Copy")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '13px 16px'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lock_open",
    size: 19,
    color: "var(--gp-outline)"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 14px/1.3 var(--font-sans)',
      color: 'var(--gp-on-surface)'
    }
  }, "Joining"), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12px/1.3 var(--font-sans)',
      color: 'var(--gp-outline)',
      marginTop: 3
    }
  }, c.joinPolicy)), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron_right",
    size: 19,
    color: "#BFC9BE"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 4px',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "Anyone with this link or code can join the community. Both carry the same code."), /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    fullWidth: true,
    icon: "autorenew",
    onClick: () => setToast('New code issued. The old one no longer works.')
  }, "Regenerate code"), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 4px 24px',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "The current link and code stop working immediately, so anyone still holding them cannot join. People already in the community stay members.")))));
}
window.InviteScreen = InviteScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Invite.jsx", error: String((e && e.message) || e) }); }

// design/screens/MatchDetails.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Hero,
  HeroBar,
  Sheet,
  IconButton,
  Chip,
  Button,
  SectionHeading,
  ParticipantRow,
  CapacityBar,
  Card,
  Dialog,
  Icon,
  EmptyState
} = window.GoPlayDesignSystem_984b89;
const {
  OwnerLine,
  HeroFacts
} = window;
function MatchDetailsScreen({
  go,
  match,
  setToast,
  review
}) {
  const d = window.T(review);
  const m = match || d.matches[0];
  const reg = review && review.reg || 'confirmed';
  const [joined, setJoined] = React.useState(reg !== 'none');
  const [onReserve, setOnReserve] = React.useState(reg === 'reserve');
  React.useEffect(() => {
    setJoined(reg !== 'none');
    setOnReserve(reg === 'reserve');
  }, [reg]);
  const [confirm, setConfirm] = React.useState(false);
  const done = m.status === 'completed';
  const organizer = (review && review.role ? review.role : m.role) !== 'Player';
  const wouldReserve = !joined && m.registered >= m.starting;
  const alt = window.screenState(review, {
    skeleton: /*#__PURE__*/React.createElement(window.MatchListSkeleton, {
      rows: 3
    })
  });
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    title: "Match",
    onBack: () => go('home'),
    right: organizer ? /*#__PURE__*/React.createElement(IconButton, {
      icon: "settings",
      label: "Match management",
      onHero: true
    }) : null
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(OwnerLine, {
    community: m.community,
    role: m.role,
    onHero: true
  }), /*#__PURE__*/React.createElement(Chip, {
    tone: done ? 'completed' : m.status
  }, done ? 'Played' : m.status === 'full' ? 'Full' : 'Open')), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 23px/1.2 var(--font-sans)',
      letterSpacing: '-.8px',
      marginTop: 9
    }
  }, m.title), /*#__PURE__*/React.createElement(HeroFacts, {
    items: [['calendar_month', m.wd + ' ' + m.d + ' ' + m.mo], ['schedule', m.time], ['place', m.location]]
  }))), /*#__PURE__*/React.createElement(Sheet, null, alt ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 14
    }
  }, alt) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 14px 0',
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, done ? /*#__PURE__*/React.createElement(Card, {
    style: {
      background: 'var(--gp-primary-deep)',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '500 10.5px/1 var(--font-sans)',
      letterSpacing: '.08em',
      textTransform: 'uppercase',
      color: 'rgba(255,255,255,.7)'
    }
  }, "Final score"), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 30px/1 var(--font-sans)',
      letterSpacing: '-1.2px',
      marginTop: 8
    }
  }, m.score), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12.5px/1 var(--font-sans)',
      color: 'rgba(255,255,255,.75)',
      marginTop: 7
    }
  }, "Team A won \xB7 you played")), /*#__PURE__*/React.createElement(Button, {
    variant: "onHero",
    size: "small",
    onClick: () => go('result', m)
  }, "Result"))) : /*#__PURE__*/React.createElement(Card, {
    outlined: true,
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '13px 16px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: onReserve ? 'hourglass_top' : joined ? 'check_circle' : 'group',
    size: 20,
    fill: joined,
    color: onReserve ? 'var(--gp-tertiary)' : joined ? 'var(--gp-primary-deep)' : 'var(--gp-outline)'
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 14.5px/1.25 var(--font-sans)',
      color: 'var(--gp-on-surface)'
    }
  }, onReserve ? 'You are on the reserve list' : joined ? 'You have a confirmed place' : wouldReserve ? 'This match is full' : m.registered + ' of ' + m.starting + ' places filled'), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12.5px/1.35 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)',
      marginTop: 3
    }
  }, onReserve ? 'Position 1. You take the first place that opens up.' : joined ? m.registered + ' of ' + m.starting + ' places filled · ' + d.reserve.length + ' on the reserve list' : wouldReserve ? 'Joining now adds you to the reserve list.' : m.starting - m.registered + ' places left'))), /*#__PURE__*/React.createElement(CapacityBar, {
    registered: m.registered,
    starting: m.starting,
    reserve: m.reserve,
    status: m.status,
    showLabel: false,
    style: {
      marginTop: 12
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      marginTop: 7,
      font: '400 11.5px/1 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", {
    style: {
      color: 'var(--gp-on-surface)'
    }
  }, m.registered), " of ", m.starting, " starting"), /*#__PURE__*/React.createElement("span", null, d.reserve.length, " of ", m.reserve, " reserve")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 13
    }
  }, joined ? /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    size: "compact",
    fullWidth: true,
    onClick: () => setConfirm(true)
  }, onReserve ? 'Leave the reserve list' : 'Withdraw') : /*#__PURE__*/React.createElement(Button, {
    size: "compact",
    fullWidth: true,
    onClick: () => {
      setJoined(true);
      setToast(wouldReserve ? 'The match is full. You were added to the reserve list.' : 'You joined the match.');
    }
  }, wouldReserve ? 'Join the reserve list' : 'Join match')))), organizer ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "tonal",
    size: "compact",
    icon: "group",
    style: {
      flex: 1
    },
    onClick: () => go('teams', m)
  }, "Teams"), /*#__PURE__*/React.createElement(Button, {
    variant: "tonal",
    size: "compact",
    icon: "scoreboard",
    style: {
      flex: 1
    },
    onClick: () => go('result', m)
  }, done ? 'Edit result' : 'Enter result')) : null), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Starting",
    count: d.roster.length + ' / ' + m.starting,
    action: organizer ? 'Arrange' : undefined,
    onAction: () => go('arrange', m)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      overflow: 'hidden'
    }
  }, d.roster.map((p, i) => /*#__PURE__*/React.createElement("div", {
    key: p.name + i,
    style: {
      borderTop: i ? '1px solid var(--border-hairline)' : 'none'
    }
  }, /*#__PURE__*/React.createElement(ParticipantRow, p))))), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Reserve",
    count: d.reserve.length
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px 92px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      overflow: 'hidden'
    }
  }, d.reserve.length ? d.reserve.map((p, i) => /*#__PURE__*/React.createElement("div", {
    key: p.name,
    style: {
      borderTop: i ? '1px solid var(--border-hairline)' : 'none'
    }
  }, /*#__PURE__*/React.createElement(ParticipantRow, _extends({}, p, {
    reserve: true,
    index: i + 1,
    trailing: /*#__PURE__*/React.createElement(Chip, {
      tone: "reserve"
    }, "Next in")
  })))) : /*#__PURE__*/React.createElement(EmptyState, {
    icon: "hourglass_empty",
    message: "Nobody is on the reserve list."
  }))))), confirm ? /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'rgba(0,0,0,.34)',
      display: 'grid',
      placeItems: 'center',
      padding: 16,
      zIndex: 30
    }
  }, /*#__PURE__*/React.createElement(Dialog, {
    title: "Withdraw from this match?",
    body: "If you have a confirmed seat, the first reserve will take your place.",
    cancelLabel: "Back",
    confirmLabel: "Withdraw",
    destructive: true,
    onCancel: () => setConfirm(false),
    onConfirm: () => {
      setConfirm(false);
      setJoined(false);
      setToast('You withdrew from the match.');
    }
  })) : null);
}
window.MatchDetailsScreen = MatchDetailsScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/MatchDetails.jsx", error: String((e && e.message) || e) }); }

// design/screens/Members.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Button,
  IconButton,
  Chip,
  MemberRow,
  SectionHeading,
  TextField,
  BottomSheet,
  ListRow,
  Divider,
  Icon,
  EmptyState
} = window.GoPlayDesignSystem_984b89;
const {
  TaskBar,
  TaskBody,
  RowGroup
} = window;
function MembersScreen({
  go,
  community,
  setToast,
  review
}) {
  const d = window.T(review);
  const base = community || d.communities[0];
  const role = review && review.role || base.role;
  const c = {
    ...base,
    role
  };
  const [q, setQ] = React.useState('');
  const [acting, setActing] = React.useState(null);
  const owner = role === 'Owner';
  const organizer = role !== 'Player';
  const list = d.members.filter(m => m.name.toLowerCase().includes(q.toLowerCase()));
  // A player can read the roster but never act on it, so the trailing column
  // is absent rather than disabled — a control nobody can use is still a
  // control somebody will try.
  const canAct = m => organizer && !m.you && m.role !== 'Owner' && (owner || m.role === 'Player');
  const alt = window.screenState(review, {
    empty: /*#__PURE__*/React.createElement(EmptyState, {
      icon: "person_search",
      message: "This community has no members yet."
    })
  });
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TaskBar, {
    title: "Members",
    onBack: () => go('community', c),
    right: organizer ? /*#__PURE__*/React.createElement(IconButton, {
      icon: "person_add",
      label: "Invite",
      onClick: () => go('invite', c)
    }) : null
  }), /*#__PURE__*/React.createElement(TaskBody, {
    style: {
      padding: '12px 14px 20px'
    }
  }, alt ? alt : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-control)',
      boxShadow: 'var(--elevation-card)',
      padding: '0 14px',
      height: 46
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "search",
    size: 19,
    color: "var(--gp-outline)"
  }), /*#__PURE__*/React.createElement("input", {
    value: q,
    onChange: e => setQ(e.target.value),
    placeholder: "Search by name",
    style: {
      flex: 1,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      font: '400 15px/1 var(--font-sans)',
      color: 'var(--gp-on-surface)'
    }
  })), /*#__PURE__*/React.createElement(SectionHeading, {
    title: c.name,
    count: c.members + ' members',
    style: {
      padding: '18px 4px 9px'
    }
  }), list.length ? /*#__PURE__*/React.createElement(RowGroup, null, list.map(m => /*#__PURE__*/React.createElement(MemberRow, _extends({
    key: m.name
  }, m, {
    trailing: /*#__PURE__*/React.createElement("div", {
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 4,
        flex: '0 0 auto'
      }
    }, m.role !== 'Player' ? /*#__PURE__*/React.createElement(Chip, {
      tone: m.role === 'Owner' ? 'open' : 'role',
      square: true
    }, m.role) : null, canAct(m) ? /*#__PURE__*/React.createElement(IconButton, {
      icon: "more_vert",
      label: 'Actions for ' + m.name,
      size: 19,
      onClick: () => setActing(m)
    }) : /*#__PURE__*/React.createElement("span", {
      style: {
        width: 8
      }
    }))
  })))) : /*#__PURE__*/React.createElement(EmptyState, {
    icon: "person_search",
    message: "No players found."
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '18px 4px 0',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, owner ? 'Only the owner can transfer ownership or change an admin. Removing a member also withdraws them from every match in this community.' : organizer ? 'Admins can promote and remove players. Only the owner can change another admin.' : 'Only the owner and admins can change who is in this community.'))), acting ? /*#__PURE__*/React.createElement("div", {
    onClick: () => setActing(null),
    style: {
      position: 'absolute',
      inset: 0,
      background: 'rgba(0,0,0,.34)',
      display: 'flex',
      alignItems: 'flex-end',
      zIndex: 30
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '100%'
    },
    onClick: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement(BottomSheet, {
    title: acting.name
  }, /*#__PURE__*/React.createElement(ListRow, {
    icon: "person",
    title: "View profile",
    onClick: () => setActing(null)
  }), acting.role === 'Player' ? /*#__PURE__*/React.createElement(ListRow, {
    icon: "shield_person",
    title: "Make admin",
    subtitle: "Can create matches and manage the roster",
    onClick: () => {
      setActing(null);
      setToast('Member role updated.');
    }
  }) : /*#__PURE__*/React.createElement(ListRow, {
    icon: "person",
    title: "Make player",
    onClick: () => {
      setActing(null);
      setToast('Member role updated.');
    }
  }), owner ? /*#__PURE__*/React.createElement(ListRow, {
    icon: "swap_horiz",
    title: "Transfer ownership",
    subtitle: "You become an admin",
    onClick: () => {
      setActing(null);
      setToast('Ownership transferred. You are now an admin.');
    }
  }) : null, /*#__PURE__*/React.createElement(Divider, {
    tight: true
  }), /*#__PURE__*/React.createElement(ListRow, {
    icon: "person_remove",
    title: "Remove from community",
    danger: true,
    onClick: () => {
      setActing(null);
      setToast('Member removed from the community.');
    }
  })))) : null);
}
window.MembersScreen = MembersScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Members.jsx", error: String((e && e.message) || e) }); }

// design/screens/Profile.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Hero,
  HeroBar,
  Sheet,
  IconButton,
  Chip,
  SectionHeading,
  StatTile,
  CommunityLogo,
  SegmentedControl,
  ListRow,
  Icon,
  Avatar
} = window.GoPlayDesignSystem_984b89;
const {
  RowGroup
} = window;
function ProfileScreen({
  go,
  review
}) {
  const d = window.T(review);
  const [period, setPeriod] = React.useState('all');
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Hero, null, /*#__PURE__*/React.createElement(HeroBar, {
    title: "Profile",
    onBack: () => go('home'),
    right: /*#__PURE__*/React.createElement(IconButton, {
      icon: "edit",
      label: "Edit profile",
      onHero: true
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 18px',
      color: '#fff',
      display: 'flex',
      gap: 15,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(Avatar, {
    name: d.me.name,
    size: 62,
    style: {
      background: 'rgba(255,255,255,.16)',
      color: '#fff',
      boxShadow: 'inset 0 0 0 2px rgba(255,255,255,.3)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 21px/1.2 var(--font-sans)',
      letterSpacing: '-.7px',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, d.me.name), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6,
      marginTop: 8
    }
  }, /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero"
  }, d.me.position), /*#__PURE__*/React.createElement(Chip, {
    tone: "onHero"
  }, d.communities.length, " communities"))), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'center',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '700 30px/1 var(--font-sans)',
      letterSpacing: '-1.4px'
    }
  }, d.me.rating), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '500 10px/1 var(--font-sans)',
      letterSpacing: '.08em',
      textTransform: 'uppercase',
      color: 'rgba(255,255,255,.7)',
      marginTop: 6
    }
  }, "Rating")))), /*#__PURE__*/React.createElement(Sheet, null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 14px 0'
    }
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    value: period,
    onChange: setPeriod,
    options: [{
      value: 'week',
      label: 'This week'
    }, {
      value: 'month',
      label: 'This month'
    }, {
      value: 'all',
      label: 'All time'
    }]
  })), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Record"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(3,1fr)',
      gap: 9,
      padding: '0 14px'
    }
  }, d.stats.map(s => /*#__PURE__*/React.createElement(StatTile, _extends({
    key: s.label
  }, s)))), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Form",
    count: "last 6"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      padding: '14px 16px',
      display: 'flex',
      alignItems: 'flex-end',
      gap: 7,
      height: 76,
      boxSizing: 'border-box'
    }
  }, d.me.form.map((v, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: '100%',
      height: v / 5 * 40,
      borderRadius: 5,
      background: i === d.me.form.length - 1 ? 'var(--gp-primary-deep)' : '#CFE3D3'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '500 10px/1 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, v.toFixed(1)))))), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Communities",
    count: d.communities.length
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px'
    }
  }, /*#__PURE__*/React.createElement(RowGroup, null, d.communities.map(c => /*#__PURE__*/React.createElement(ListRow, {
    key: c.id,
    leading: /*#__PURE__*/React.createElement(CommunityLogo, {
      name: c.name,
      size: 38
    }),
    title: c.name,
    subtitle: c.role + ' · ' + c.members + ' members',
    chevron: true,
    onClick: () => go('community', c)
  })))), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Account"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 14px 92px'
    }
  }, /*#__PURE__*/React.createElement(RowGroup, null, /*#__PURE__*/React.createElement(ListRow, {
    icon: "settings",
    title: "Settings",
    chevron: true,
    onClick: () => {}
  }), /*#__PURE__*/React.createElement(ListRow, {
    icon: "notifications",
    title: "Notifications",
    chevron: true,
    onClick: () => go('notifications')
  }), /*#__PURE__*/React.createElement(ListRow, {
    icon: "logout",
    title: "Log out",
    onClick: () => {}
  })))));
}
window.ProfileScreen = ProfileScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Profile.jsx", error: String((e && e.message) || e) }); }

// design/screens/Result.jsx
try { (() => {
const {
  Button,
  Icon,
  Avatar,
  Chip,
  SectionHeading,
  EmptyState
} = window.GoPlayDesignSystem_984b89;
const {
  TaskBar,
  TaskBody,
  RowGroup,
  ActionBar
} = window;
function ResultScreen({
  go,
  match,
  setToast,
  review
}) {
  const d = window.T(review);
  const m = match || d.matches[2];
  const [a, setA] = React.useState(3);
  const [b, setB] = React.useState(2);
  const [goals, setGoals] = React.useState({
    'Yousuf Fadhil': 2,
    'Omar Al Harthy': 1
  });
  const [motm, setMotm] = React.useState('Yousuf Fadhil');
  const all = [...d.teams.a, ...d.teams.b];
  const scored = Object.values(goals).reduce((s, n) => s + n, 0);
  const mismatch = scored !== a + b;
  const Stepper = ({
    v,
    set,
    label,
    tone
  }) => /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 5,
      font: '700 12px/1 var(--font-sans)',
      color: '#fff',
      opacity: .85
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 18,
      height: 18,
      borderRadius: 5,
      background: tone,
      display: 'grid',
      placeItems: 'center',
      font: '700 10px/1 var(--font-sans)'
    }
  }, label.slice(-1)), label), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 12,
      marginTop: 10
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => set(Math.max(0, v - 1)),
    style: {
      width: 34,
      height: 34,
      borderRadius: 17,
      border: '1.5px solid rgba(255,255,255,.32)',
      background: 'transparent',
      color: '#fff',
      display: 'grid',
      placeItems: 'center',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "remove",
    size: 17
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 38px/1 var(--font-sans)',
      letterSpacing: '-1.6px',
      color: '#fff',
      minWidth: 40
    }
  }, v), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => set(v + 1),
    style: {
      width: 34,
      height: 34,
      borderRadius: 17,
      border: 'none',
      background: '#fff',
      color: 'var(--gp-primary-deep)',
      display: 'grid',
      placeItems: 'center',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "add",
    size: 17
  }))));
  const bump = (name, n) => setGoals(g => {
    const v = Math.max(0, (g[name] || 0) + n);
    const next = {
      ...g
    };
    if (v) next[name] = v;else delete next[name];
    return next;
  });
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TaskBar, {
    title: "Match result",
    onBack: () => go('match', m)
  }), /*#__PURE__*/React.createElement(TaskBody, {
    style: {
      padding: '12px 14px 20px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--gp-primary-deep)',
      borderRadius: 'var(--radius-card)',
      padding: '16px 14px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    dir: "ltr",
    style: {
      display: 'flex',
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(Stepper, {
    v: a,
    set: setA,
    label: "Team A",
    tone: "rgba(255,255,255,.25)"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      alignSelf: 'center',
      font: '700 20px/1 var(--font-sans)',
      color: 'rgba(255,255,255,.4)',
      padding: '0 4px',
      marginTop: 18
    }
  }, "\u2013"), /*#__PURE__*/React.createElement(Stepper, {
    v: b,
    set: setB,
    label: "Team B",
    tone: "var(--gp-tertiary)"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'center',
      marginTop: 14,
      font: '400 12.5px/1 var(--font-sans)',
      color: 'rgba(255,255,255,.72)'
    }
  }, a === b ? 'Draw' : (a > b ? 'Team A' : 'Team B') + ' wins')), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Goalscorers",
    count: scored + ' of ' + (a + b),
    style: {
      padding: '18px 4px 9px'
    }
  }), /*#__PURE__*/React.createElement(RowGroup, null, all.map(p => {
    const n = goals[p.name] || 0;
    return /*#__PURE__*/React.createElement("div", {
      key: p.name,
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '9px 16px',
        minHeight: 54
      }
    }, /*#__PURE__*/React.createElement(Avatar, {
      name: p.guest ? '' : p.name,
      size: 34,
      tone: n ? 'accent' : 'neutral'
    }), /*#__PURE__*/React.createElement("div", {
      style: {
        flex: 1,
        minWidth: 0
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        font: '600 14px/1.3 var(--font-sans)',
        color: 'var(--gp-on-surface)',
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap'
      }
    }, p.guest ? 'Professional (' + p.name + ')' : p.name), /*#__PURE__*/React.createElement("div", {
      style: {
        font: '400 12px/1.3 var(--font-sans)',
        color: 'var(--gp-outline)',
        marginTop: 3
      }
    }, p.guest ? 'Professional guest' : p.position)), /*#__PURE__*/React.createElement("div", {
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 9
      }
    }, /*#__PURE__*/React.createElement("button", {
      type: "button",
      onClick: () => bump(p.name, -1),
      disabled: !n,
      style: {
        width: 30,
        height: 30,
        borderRadius: 15,
        border: '1.5px solid #CBD8C9',
        background: 'transparent',
        display: 'grid',
        placeItems: 'center',
        opacity: n ? 1 : .35,
        cursor: n ? 'pointer' : 'default'
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "remove",
      size: 15,
      color: "var(--gp-primary-deep)"
    })), /*#__PURE__*/React.createElement("span", {
      style: {
        minWidth: 14,
        textAlign: 'center',
        font: '700 15px/1 var(--font-sans)',
        color: n ? 'var(--gp-on-surface)' : 'var(--gp-outline)'
      }
    }, n), /*#__PURE__*/React.createElement("button", {
      type: "button",
      onClick: () => bump(p.name, 1),
      style: {
        width: 30,
        height: 30,
        borderRadius: 15,
        border: 'none',
        background: 'var(--status-open-bg)',
        display: 'grid',
        placeItems: 'center',
        cursor: 'pointer'
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "add",
      size: 15,
      color: "var(--gp-primary-deep)"
    }))));
  })), mismatch ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 9,
      marginTop: 10,
      padding: '11px 14px',
      background: 'var(--gp-error-container)',
      borderRadius: 'var(--radius-control)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "error",
    size: 18,
    color: "var(--gp-on-error-container)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: '400 12.5px/1.45 var(--font-sans)',
      color: 'var(--gp-on-error-container)'
    }
  }, "Goalscorers add up to ", scored, ", but the score is ", a + b, ". Adjust one of them before saving.")) : null, /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Player of the match",
    count: "optional",
    style: {
      padding: '18px 4px 9px'
    }
  }), /*#__PURE__*/React.createElement(RowGroup, null, all.slice(0, 4).map(p => /*#__PURE__*/React.createElement("div", {
    key: p.name,
    onClick: () => setMotm(motm === p.name ? null : p.name),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '10px 16px',
      cursor: 'pointer',
      background: motm === p.name ? 'var(--status-open-bg)' : 'transparent'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: motm === p.name ? 'star' : 'star_outline',
    size: 20,
    fill: motm === p.name,
    color: motm === p.name ? 'var(--gp-primary-deep)' : 'var(--gp-outline)'
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: '500 14px/1.3 var(--font-sans)',
      color: 'var(--gp-on-surface)'
    }
  }, p.guest ? 'Professional (' + p.name + ')' : p.name), motm === p.name ? /*#__PURE__*/React.createElement(Chip, {
    tone: "open",
    square: true
  }, "MOTM") : null))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 4px 0',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "Saving the result closes the match and updates every participant's statistics and rating. Editing it later takes the old figures back first.")), /*#__PURE__*/React.createElement(ActionBar, null, /*#__PURE__*/React.createElement(Button, {
    fullWidth: true,
    disabled: mismatch,
    onClick: () => {
      setToast('Match result saved.');
      go('match', m);
    }
  }, "Save result")));
}
window.ResultScreen = ResultScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Result.jsx", error: String((e && e.message) || e) }); }

// design/screens/Shell.jsx
try { (() => {
const {
  Icon,
  CommunityLogo,
  Chip,
  Button,
  IconButton,
  Skeleton,
  ErrorState,
  EmptyState
} = window.GoPlayDesignSystem_984b89;

/** The placeholder a match list shows while it loads. Shaped like the cards it
 *  is standing in for, so the page does not jump when the data lands. */
function MatchListSkeleton({
  rows = 2
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 9,
      padding: '0 14px'
    }
  }, Array.from({
    length: rows
  }).map((_, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      padding: '12px 16px',
      display: 'flex',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(Skeleton, {
    width: 50,
    height: 56,
    radius: "14px"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      gap: 8,
      paddingTop: 2
    }
  }, /*#__PURE__*/React.createElement(Skeleton, {
    width: "70%",
    height: 15,
    radius: "6px"
  }), /*#__PURE__*/React.createElement(Skeleton, {
    width: "45%",
    height: 11,
    radius: "5px"
  }), /*#__PURE__*/React.createElement(Skeleton, {
    width: "90%",
    height: 11,
    radius: "5px"
  }), /*#__PURE__*/React.createElement(Skeleton, {
    height: 5,
    radius: "3px"
  })))));
}

/** Reads the review harness and returns the non-populated body a screen should
 *  render instead of its content, or null when the screen should render
 *  normally. One place, so loading and failure look the same everywhere. */
function screenState(review, {
  skeleton,
  empty,
  onRetry
} = {}) {
  const s = review && review.state;
  if (s === 'loading') return skeleton || /*#__PURE__*/React.createElement(MatchListSkeleton, null);
  if (s === 'error') return /*#__PURE__*/React.createElement(ErrorState, {
    onRetry: onRetry
  });
  if (s === 'empty') return empty || /*#__PURE__*/React.createElement(EmptyState, {
    icon: "sports_soccer",
    tone: "accent",
    message: 'No upcoming matches.\nJoin a community to get started.'
  });
  return null;
}

/** The light page a task screen sits on. A place screen gets this from Sheet;
 *  a task screen has no Sheet, so it paints its own — without it the phone's
 *  deep-green base shows through everything between the cards. */
function TaskBody({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--surface-sheet)',
      ...style
    }
  }, children);
}

/** A screen that is a task, not a place: plain white bar, no bottom nav. */
function TaskBar({
  title,
  onBack,
  right
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      minHeight: 54,
      padding: '0 6px',
      background: 'var(--surface-card)',
      borderBottom: '1px solid var(--border-hairline)',
      flex: '0 0 auto'
    }
  }, onBack ? /*#__PURE__*/React.createElement(IconButton, {
    icon: "arrow_back",
    label: "Back",
    onClick: onBack
  }) : /*#__PURE__*/React.createElement("span", {
    style: {
      width: 12
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      font: '700 17px/1.25 var(--font-sans)',
      letterSpacing: '-.2px',
      color: 'var(--gp-on-surface)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, title), right);
}

/** The community line every match-side screen carries: crest, name, role. */
function OwnerLine({
  community,
  role,
  onHero
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 7
    }
  }, /*#__PURE__*/React.createElement(CommunityLogo, {
    name: community,
    size: 18,
    onHero: onHero
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 12.5px/1 var(--font-sans)',
      color: onHero ? 'rgba(255,255,255,.85)' : 'var(--gp-primary)'
    }
  }, community), role && role !== 'Player' ? /*#__PURE__*/React.createElement(Chip, {
    tone: onHero ? 'onHero' : 'role',
    square: true
  }, role) : null);
}

/** A row of facts on the hero, under the title. */
function HeroFacts({
  items
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: '6px 16px',
      marginTop: 10
    }
  }, items.map(([ic, t]) => /*#__PURE__*/React.createElement("span", {
    key: t,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      font: '400 12.5px/1.3 var(--font-sans)',
      color: 'rgba(255,255,255,.8)',
      unicodeBidi: 'plaintext',
      whiteSpace: 'nowrap'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: ic,
    size: 14
  }), t)));
}

/** A grouped list card. Rows divide with a hairline; the card never nests. */
function RowGroup({
  children,
  style
}) {
  const rows = React.Children.toArray(children).filter(Boolean);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      overflow: 'hidden',
      ...style
    }
  }, rows.map((r, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      borderTop: i ? '1px solid var(--border-hairline)' : 'none'
    }
  }, r)));
}

/** A labelled value in a task form. Tapping opens the real control. */
function FieldRow({
  label,
  value,
  icon,
  chevron = true,
  onClick,
  error
}) {
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 14,
      padding: '11px 16px',
      cursor: onClick ? 'pointer' : undefined
    }
  }, icon ? /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 19,
    color: "var(--gp-outline)"
  }) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '600 11.5px/1 var(--font-sans)',
      letterSpacing: '.06em',
      textTransform: 'uppercase',
      color: error ? 'var(--gp-error)' : 'var(--gp-outline)'
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '500 15.5px/1.35 var(--font-sans)',
      color: 'var(--gp-on-surface)',
      marginTop: 5,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, value), error ? /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 12px/1.3 var(--font-sans)',
      color: 'var(--gp-error)',
      marginTop: 4
    }
  }, error) : null), chevron && onClick ? /*#__PURE__*/React.createElement(Icon, {
    name: "chevron_right",
    size: 19,
    color: "#BFC9BE"
  }) : null);
}

/** The bar that pins a task's one commit action to the bottom of the screen. */
function ActionBar({
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: '0 0 auto',
      padding: '12px 16px 16px',
      background: 'var(--surface-card)',
      borderTop: '1px solid var(--border-hairline)'
    }
  }, children);
}
Object.assign(window, {
  TaskBar,
  TaskBody,
  OwnerLine,
  HeroFacts,
  RowGroup,
  FieldRow,
  ActionBar,
  MatchListSkeleton,
  screenState
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Shell.jsx", error: String((e && e.message) || e) }); }

// design/screens/Teams.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const {
  Button,
  IconButton,
  Chip,
  ParticipantRow,
  SectionHeading,
  SegmentedControl,
  Icon,
  Avatar,
  EmptyState
} = window.GoPlayDesignSystem_984b89;
const {
  TaskBar,
  TaskBody,
  RowGroup
} = window;

/** Teams and Arrange participants are one screen with two modes: both are the
 *  organizer moving people between two lists, and splitting them into separate
 *  screens made a player look up two different rosters for the same match. */
function TeamsScreen({
  go,
  match,
  setToast,
  initial = 'teams',
  review
}) {
  const d = window.T(review);
  const m = match || d.matches[0];
  const [mode, setMode] = React.useState(initial);
  const [picked, setPicked] = React.useState(null);
  const TeamPanel = ({
    name,
    players,
    tone
  }) => /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-card)',
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 9,
      padding: '11px 16px',
      background: tone === 'a' ? 'var(--gp-primary-deep)' : 'var(--gp-tertiary)',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 24,
      height: 24,
      borderRadius: 7,
      background: 'rgba(255,255,255,.2)',
      display: 'grid',
      placeItems: 'center',
      font: '700 12px/1 var(--font-sans)'
    }
  }, name.slice(-1)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: '700 14.5px/1 var(--font-sans)'
    }
  }, name), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '500 12px/1 var(--font-sans)',
      opacity: .8
    }
  }, players.length, " players")), players.map((p, i) => /*#__PURE__*/React.createElement("div", {
    key: p.name,
    style: {
      borderTop: i ? '1px solid var(--border-hairline)' : 'none'
    }
  }, /*#__PURE__*/React.createElement(ParticipantRow, p))));
  const ArrangeRow = ({
    p,
    i,
    reserve
  }) => {
    const on = picked === p.name;
    return /*#__PURE__*/React.createElement("div", {
      onClick: () => setPicked(on ? null : on ? null : picked ? null : p.name),
      style: {
        background: on ? 'var(--status-open-bg)' : 'transparent',
        cursor: 'pointer'
      }
    }, /*#__PURE__*/React.createElement(ParticipantRow, _extends({}, p, {
      index: i + 1,
      reserve: reserve,
      handle: true,
      trailing: picked && !on ? /*#__PURE__*/React.createElement(Button, {
        variant: "tonal",
        size: "small",
        onClick: e => {
          setPicked(null);
          setToast('Order updated.');
        }
      }, "Swap") : /*#__PURE__*/React.createElement(Chip, {
        tone: "role",
        square: true
      }, reserve ? 'RES' : 'START')
    })));
  };
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TaskBar, {
    title: mode === 'teams' ? 'Teams' : 'Arrange participants',
    onBack: () => go('match', m),
    right: mode === 'teams' ? /*#__PURE__*/React.createElement(IconButton, {
      icon: "ios_share",
      label: "Share lineup",
      onClick: () => setToast('Lineup card ready to share.')
    }) : null
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 14px 0',
      flex: '0 0 auto',
      background: 'var(--surface-sheet)'
    }
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    value: mode,
    onChange: v => {
      setMode(v);
      setPicked(null);
    },
    options: [{
      value: 'teams',
      label: 'Teams'
    }, {
      value: 'arrange',
      label: 'Arrange'
    }]
  })), /*#__PURE__*/React.createElement(TaskBody, {
    style: {
      padding: '0 14px 20px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '14px 4px 0'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sports_soccer",
    size: 16,
    color: "var(--gp-outline)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 12.5px/1.4 var(--font-sans)',
      color: 'var(--gp-on-surface-variant)'
    }
  }, m.title, " \xB7 ", m.wd, " ", m.d, " ", m.mo)), mode === 'teams' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Generated lineup",
    count: "balanced",
    style: {
      padding: '16px 4px 9px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(TeamPanel, {
    name: "Team A",
    players: d.teams.a,
    tone: "a"
  }), /*#__PURE__*/React.createElement(TeamPanel, {
    name: "Team B",
    players: d.teams.b,
    tone: "b"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 4px 0',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "Teams are split from the confirmed players by rating and position. Regenerating replaces the current split."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      marginTop: 14
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    size: "compact",
    icon: "autorenew",
    style: {
      flex: 1
    },
    onClick: () => setToast('Teams generated.')
  }, "Regenerate"), /*#__PURE__*/React.createElement(Button, {
    size: "compact",
    icon: "ios_share",
    style: {
      flex: 1
    },
    onClick: () => setToast('Lineup card ready to share.')
  }, "Share"))) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 9,
      margin: '14px 0 0',
      padding: '11px 14px',
      background: picked ? 'var(--status-open-bg)' : 'var(--gp-surface-container)',
      borderRadius: 'var(--radius-control)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: picked ? 'swap_vert' : 'info',
    size: 18,
    color: picked ? 'var(--status-open-fg)' : 'var(--gp-outline)'
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: '400 12.5px/1.45 var(--font-sans)',
      color: picked ? 'var(--status-open-fg)' : 'var(--gp-on-surface-variant)'
    }
  }, picked ? picked + ' selected. Tap another participant to swap their places.' : 'Drag the handle to reorder a list. Tap a participant, then tap another to swap.'), picked ? /*#__PURE__*/React.createElement(Button, {
    variant: "text",
    size: "small",
    onClick: () => setPicked(null)
  }, "Cancel") : null), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Starting",
    count: d.roster.length + ' / ' + m.starting,
    style: {
      padding: '16px 4px 9px'
    }
  }), /*#__PURE__*/React.createElement(RowGroup, null, d.roster.map((p, i) => /*#__PURE__*/React.createElement(ArrangeRow, {
    key: p.name,
    p: p,
    i: i
  }))), /*#__PURE__*/React.createElement(SectionHeading, {
    title: "Reserve",
    count: d.reserve.length,
    style: {
      padding: '16px 4px 9px'
    }
  }), /*#__PURE__*/React.createElement(RowGroup, null, d.reserve.map((p, i) => /*#__PURE__*/React.createElement(ArrangeRow, {
    key: p.name,
    p: p,
    i: i,
    reserve: true
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 4px 0',
      font: '400 12.5px/1.5 var(--font-sans)',
      color: 'var(--gp-outline)'
    }
  }, "Players start in the order they joined, with professional guests after them. Your first change makes your own order the one that counts."))));
}
window.TeamsScreen = TeamsScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/Teams.jsx", error: String((e && e.message) || e) }); }

// design/screens/data.js
try { (() => {
// Fixture data for the Go Play UI kit. Shapes follow the Supabase read models
// (matches, communities, community_members, match_registrations, match_results).
window.GP_DATA = {
  me: {
    name: 'Yousuf Fadhil',
    position: 'Midfielder',
    rating: '5.0',
    form: [3.8, 4.1, 4.0, 4.6, 4.4, 5.0]
  },
  communities: [{
    id: 'c1',
    name: 'Al Shamal',
    description: 'Thursday and Sunday games in the north',
    members: 24,
    upcoming: 2,
    played: 18,
    role: 'Admin',
    code: '481 902',
    joinPolicy: 'Open join'
  }, {
    id: 'c2',
    name: 'Al Bahar',
    description: 'Small-sided group',
    members: 9,
    upcoming: 1,
    played: 6,
    role: 'Player',
    codeRequired: true,
    joinPolicy: 'Join by code'
  }],
  matches: [{
    id: 'm1',
    title: 'Thursday practice',
    community: 'Al Shamal',
    location: 'Al Shamal 6-a-side',
    wd: 'Thu',
    d: 13,
    mo: 'Aug',
    time: '17:25 – 18:35',
    starting: 12,
    reserve: 6,
    registered: 6,
    status: 'open',
    joined: true,
    role: 'Admin',
    next: true,
    inHours: 4
  }, {
    id: 'm2',
    title: 'Friday five-a-side',
    community: 'Al Bahar',
    location: 'Marina courts',
    wd: 'Fri',
    d: 14,
    mo: 'Aug',
    time: '19:00 – 20:30',
    starting: 10,
    reserve: 6,
    registered: 10,
    status: 'full',
    joined: false,
    role: 'Player'
  }, {
    id: 'm3',
    title: 'Sunday league',
    community: 'Al Shamal',
    location: 'Al Shamal 6-a-side',
    wd: 'Sun',
    d: 7,
    mo: 'Aug',
    time: '17:20 – 18:35',
    starting: 14,
    reserve: 6,
    registered: 14,
    status: 'completed',
    joined: true,
    role: 'Admin',
    score: '3 – 2'
  }],
  roster: [{
    name: 'Khalid Al Balushi',
    position: 'Goalkeeper'
  }, {
    name: 'Talib Abu Fahd',
    position: 'Defender'
  }, {
    name: 'Mohammed Al Sadrani',
    position: 'Defender'
  }, {
    name: 'Yousuf Fadhil',
    position: 'Midfielder',
    you: true
  }, {
    name: 'Omar Al Harthy',
    position: 'Forward'
  }, {
    name: 'Faisal',
    guest: true
  }],
  reserve: [{
    name: 'Nasser Al Kaabi',
    position: 'Forward'
  }],
  members: [{
    name: 'Khalid Al Balushi',
    role: 'Owner',
    position: 'Goalkeeper'
  }, {
    name: 'Yousuf Fadhil',
    role: 'Admin',
    position: 'Midfielder',
    you: true
  }, {
    name: 'Talib Abu Fahd',
    role: 'Player',
    position: 'Defender'
  }, {
    name: 'Mohammed Al Sadrani',
    role: 'Player',
    position: 'Defender'
  }, {
    name: 'Omar Al Harthy',
    role: 'Player',
    position: 'Forward'
  }],
  teams: {
    a: [{
      name: 'Khalid Al Balushi',
      position: 'Goalkeeper'
    }, {
      name: 'Talib Abu Fahd',
      position: 'Defender'
    }, {
      name: 'Yousuf Fadhil',
      position: 'Midfielder',
      you: true
    }],
    b: [{
      name: 'Mohammed Al Sadrani',
      position: 'Defender'
    }, {
      name: 'Omar Al Harthy',
      position: 'Forward'
    }, {
      name: 'Faisal',
      guest: true
    }]
  },
  stats: [{
    icon: 'sports_soccer',
    value: 3,
    label: 'Played'
  }, {
    icon: 'trophy',
    value: 1,
    label: 'Wins'
  }, {
    icon: 'trending_down',
    value: 2,
    label: 'Losses'
  }, {
    icon: 'remove',
    value: 0,
    label: 'Draws'
  }, {
    icon: 'scoreboard',
    value: 2,
    label: 'Goals'
  }, {
    icon: 'star',
    value: 0,
    label: 'MOTM'
  }],
  notifications: 3
};

/** Arabic fixtures — deliberately at the long end of what the product allows, so
 *  the RTL pass in the review harness is a truncation test and not a courtesy.
 *  Chrome strings stay English here: the app already ships app_ar.arb, and what
 *  this harness has to prove is that the LAYOUT survives Arabic content. */
window.GP_DATA_AR = (() => {
  const d = JSON.parse(JSON.stringify(window.GP_DATA));
  d.me.name = 'يوسف بن عبدالله الفاضل الحارثي';
  d.me.position = 'خط الوسط';
  d.communities[0].name = 'مجتمع الشمال لكرة القدم';
  d.communities[0].description = 'مباريات كل خميس وأحد في ملاعب الشمال الشمالية';
  d.communities[1].name = 'نادي البحر الرياضي';
  d.communities[1].description = 'مجموعة الملاعب الصغيرة';
  const titles = ['تمرين مساء الخميس الأسبوعي', 'مباراة الجمعة خماسي الأضلاع', 'دوري الأحد الودي'];
  const locs = ['ملعب الشمال السداسي المغطى', 'ملاعب المارينا الرياضية', 'ملعب الشمال السداسي المغطى'];
  d.matches.forEach((m, i) => {
    m.title = titles[i];
    m.location = locs[i];
    m.community = i === 1 ? d.communities[1].name : d.communities[0].name;
    m.wd = ['خميس', 'جمعة', 'أحد'][i];
    m.mo = 'أغسطس';
  });
  const names = ['خالد بن سالم البلوشي', 'طالب أبو فهد الكندي', 'محمد بن ناصر الصدراني', 'يوسف بن عبدالله الفاضل', 'عمر بن حمد الحارثي', 'فيصل'];
  const pos = ['حارس مرمى', 'مدافع', 'مدافع', 'خط الوسط', 'مهاجم', ''];
  d.roster.forEach((p, i) => {
    p.name = names[i];
    if (!p.guest) p.position = pos[i];
  });
  d.reserve[0].name = 'ناصر بن جمعة الكعبي';
  d.reserve[0].position = 'مهاجم';
  d.members.forEach((m, i) => {
    m.name = names[i];
    m.position = pos[i];
  });
  d.teams.a.forEach((p, i) => {
    p.name = [names[0], names[1], names[3]][i];
    if (!p.guest) p.position = [pos[0], pos[1], pos[3]][i];
  });
  d.teams.b.forEach((p, i) => {
    p.name = [names[2], names[4], names[5]][i];
    if (!p.guest) p.position = [pos[2], pos[4], ''][i];
  });
  d.stats = d.stats.map((s, i) => ({
    ...s,
    label: ['المباريات', 'الانتصارات', 'الخسائر', 'التعادلات', 'الأهداف', 'أفضل لاعب'][i]
  }));
  return d;
})();

/** The fixture set for the current review direction. */
window.T = review => review && review.dir === 'rtl' ? window.GP_DATA_AR : window.GP_DATA;
})(); } catch (e) { __ds_ns.__errors.push({ path: "design/screens/data.js", error: String((e && e.message) || e) }); }

__ds_ns.Avatar = __ds_scope.Avatar;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Chip = __ds_scope.Chip;

__ds_ns.CountPill = __ds_scope.CountPill;

__ds_ns.Divider = __ds_scope.Divider;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.BottomSheet = __ds_scope.BottomSheet;

__ds_ns.Dialog = __ds_scope.Dialog;

__ds_ns.EmptyState = __ds_scope.EmptyState;

__ds_ns.ErrorState = __ds_scope.ErrorState;

__ds_ns.LoadingState = __ds_scope.LoadingState;

__ds_ns.Skeleton = __ds_scope.Skeleton;

__ds_ns.Snackbar = __ds_scope.Snackbar;

__ds_ns.CapacityBar = __ds_scope.CapacityBar;

__ds_ns.CommunityCard = __ds_scope.CommunityCard;

__ds_ns.CommunityLogo = __ds_scope.CommunityLogo;

__ds_ns.DateTile = __ds_scope.DateTile;

__ds_ns.MatchCard = __ds_scope.MatchCard;

__ds_ns.MemberRow = __ds_scope.MemberRow;

__ds_ns.ParticipantRow = __ds_scope.ParticipantRow;

__ds_ns.RatingHero = __ds_scope.RatingHero;

__ds_ns.StatTile = __ds_scope.StatTile;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.SelectField = __ds_scope.SelectField;

__ds_ns.SwitchRow = __ds_scope.SwitchRow;

__ds_ns.TextField = __ds_scope.TextField;

__ds_ns.AppHeader = __ds_scope.AppHeader;

__ds_ns.BottomNav = __ds_scope.BottomNav;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.FootNote = __ds_scope.FootNote;

__ds_ns.Hero = __ds_scope.Hero;

__ds_ns.HeroBar = __ds_scope.HeroBar;

__ds_ns.Sheet = __ds_scope.Sheet;

__ds_ns.ListRow = __ds_scope.ListRow;

__ds_ns.SectionHeading = __ds_scope.SectionHeading;

})();
