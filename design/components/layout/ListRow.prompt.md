A row inside a grouped card: fact rows on Match Details, members, sheet actions.

```jsx
<ListRow icon="place" title="Location" subtitle="Al Shamal 6-a-side pitch" />
<ListRow leading={<Avatar name="Talib Abu Fahd" />} title="Talib Abu Fahd" subtitle="Defender" />
<ListRow icon="delete" title="Delete community" danger onClick={confirm} />
```

Rows live inside a `Card padded={false}`; a bare row running edge to edge makes a record read as a settings page.
