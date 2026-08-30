The green crest block at the top of an identity-owning screen, and the light sheet that slides over it.

```jsx
<Hero>
  <HeroBar onBack={back} right={<IconButton icon="more_vert" label="Actions" onHero />} />
  <div style={{padding:'0 18px',color:'#fff'}}>…crest, name, role…</div>
</Hero>
<Sheet>…the rest of the screen…</Sheet>
```

**Keep it short.** A hero is a bar row plus one identity row plus at most one action row — roughly 150–185px. It exists to say *whose* screen this is, not to be a header image. Screens with no community of their own (Create match, Result entry) use a plain `AppHeader` instead.
