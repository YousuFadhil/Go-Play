The product's only text input: filled, hairline border, label that stays above the value.

```jsx
<TextField label="Match title" maxLength={60} counter="0/60" />
<TextField label="Phone number" helper="8 digits, e.g. 9012 3456" />
<TextField label="Email" error="Enter a valid email address" />
```

Errors read as sentences ("Match title is required"), never as codes. Focus is a 2px primary border and nothing else — no glow, no shadow.
