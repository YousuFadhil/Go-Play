A person in a community roster or a member-management list.

```jsx
<MemberRow name="Khalid Al Balushi" role="Owner" position="Goalkeeper" />
<MemberRow name="Yousuf Fadhil" role="Admin" position="Midfielder" you
  trailing={<IconButton icon="more_vert" label="Member actions" />} />
```

Only render the overflow action for a caller whose role permits it — a player sees the list without the trailing column at all, not with a disabled one.
