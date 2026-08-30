One statistic, three per row.

```jsx
<div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:9}}>
  <StatTile icon="sports_soccer" value={3} label="Played" />
  <StatTile icon="trophy" value={1} label="Wins" />
  <StatTile icon="scoreboard" value={2} label="Goals" />
</div>
```

Six tiles maximum. Labels are one word where the language allows it — Arabic gets two lines and the tile absorbs it.
