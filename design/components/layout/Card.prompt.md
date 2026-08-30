The one card: white, 20px radius, the whisper shadow, no border.

```jsx
<Card>…</Card>
<Card outlined>…</Card>              {/* the next action, once per screen */}
<Card padded={false}><MemberRow/><MemberRow/></Card>
```

A card that holds rows sets `padded={false}` and lets the rows carry their own padding — the rows divide with a hairline, not with gaps between separate cards. Never add a coloured left border or a gradient.
