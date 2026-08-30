Where a screen's named actions live — always with a drag handle and a 26px top radius.

```jsx
<BottomSheet title="Al Shamal">
  <ListRow icon="ios_share" title="Share invitation" subtitle="Invitation" />
  <ListRow icon="group" title="Manage members" />
  <Divider />
  <ListRow icon="delete" title="Delete community" danger />
</BottomSheet>
```

Show only what the caller's role permits — an action a player can never take is simply not in the sheet.
