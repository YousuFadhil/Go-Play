One row, one selection. This is Go Play's tab control — the app has no underlined tab bar.

```jsx
<SegmentedControl value="week" onChange={setPeriod}
  options={[{value:'week',label:'This week'},{value:'month',label:'This month'},{value:'all',label:'All time'}]} />
```

Order narrowest first, so the control reads as a zoom out. Labels shrink before they clip — Arabic labels are the longer set.
