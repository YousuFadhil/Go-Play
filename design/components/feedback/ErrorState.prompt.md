A failed read, with the one recovery worth offering.

```jsx
<ErrorState onRetry={reload} />
<ErrorState message="Could not reach the server. Check your internet connection." onRetry={reload} />
```

A refusal is not a broken connection: "You are not a member of this community" is an `EmptyState`, not this.
