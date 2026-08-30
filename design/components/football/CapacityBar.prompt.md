How full a match is. Segmented, one segment per place — so a reader counts rather than estimates.

```jsx
<CapacityBar registered={6} starting={12} reserve={6} />
<CapacityBar registered={10} starting={10} reserve={6} status="full" compact />
```

Use this instead of a progress ring anywhere the number matters. The teal run after the gap is the reserve allowance — never merge it into the main run.
