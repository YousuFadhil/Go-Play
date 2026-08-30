The one app bar. Title left, screen actions right, signed-in player last.

```jsx
<AppHeader title="Home" user={{ name: 'Yousuf Fadhil' }}
  actions={<IconButton icon="notifications" label="Notifications" badge={3} />} />
```

No shadow at rest; a hairline appears only once content scrolls under it. The identity menu holds Profile, Settings and Log out.
