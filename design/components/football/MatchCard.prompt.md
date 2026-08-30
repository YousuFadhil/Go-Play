The match row shared by Home, Discover and a community's match list.

```jsx
<MatchCard weekday="Thu" day={13} month="Aug" title="Thursday practice"
  communityName="Al Shamal" location="Al Shamal 6-a-side" time="17:25 – 18:35"
  registered={6} starting={12} reserve={6} />
```

No action button on the card — tapping it opens the match, and joining happens there where the reader can see the roster. Status and capacity are two independent signals: the chip says whether you *can* join, the bar says what you would be joining.
