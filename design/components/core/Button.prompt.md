The product's one button. 16px corner everywhere; only the fill and the height change.

```jsx
<Button fullWidth>Create match</Button>
<Button variant="tonal" size="compact">Join match</Button>
<Button variant="outlined" size="small">Withdraw</Button>
<Button variant="onHero" size="compact" icon="add">Create match</Button>   {/* on the hero */}
<Button variant="danger">Delete match</Button>
```

**One filled button per screen.** If two actions look equally important, one of them is `outlined`. On the green hero the pair is always `onHero` + `ghost`.
