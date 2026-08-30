Renders one Material Symbols glyph — the same icon set the Flutter app draws from.

```jsx
<Icon name="sports_soccer" size={18} />
<Icon name="home" size={24} fill />
```

Sizes in use: 24 in app bars and bottom nav, 18 on buttons, 15 on match-card detail lines, 14 in chips. Never colour an icon outside the palette — it inherits `currentColor` by default.
