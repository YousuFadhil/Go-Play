A status pill. It reports; it is never a control.

```jsx
<Chip tone="open">Open</Chip>
<Chip tone="full">Full</Chip>          {/* amber — closed, but not an error */}
<Chip tone="reserve">Reserve</Chip>
<Chip tone="role" square>Admin</Chip>
<Chip tone="onHero" icon="groups">2 communities</Chip>
```

Full is amber, not grey: grey said "disabled" and a full match is a healthy match. Roles use `square` so a person's role never looks like a thing's status.
