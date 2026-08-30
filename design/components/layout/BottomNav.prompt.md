The app's root navigation: a floating 58px bar, always labelled.

```jsx
<BottomNav value="home" onChange={setTab} items={[
  { value: 'discover', label: 'Discover', icon: 'explore' },
  { value: 'home', label: 'Home', icon: 'home' },
  { value: 'communities', label: 'Communities', icon: 'groups' },
]} />
```

Because it floats, every scrolling list needs ~84px of bottom padding. Screens reached by pushing (Create match, Member management, Result entry) drop the nav entirely — they are a task, not a place. Do not add a fourth destination.
