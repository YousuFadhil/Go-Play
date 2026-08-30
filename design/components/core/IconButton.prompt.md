A glyph-only action in an app bar, with an optional unread badge.

```jsx
<IconButton icon="notifications" label="Notifications" badge={3} />
<IconButton icon="shield" label="Administration" />
```

Only for bar actions. Anything that needs a name gets a `Button` or a `ListRow` in a sheet — a bar is a poor place for an action that needs a label, and a very poor place for a destructive one.
