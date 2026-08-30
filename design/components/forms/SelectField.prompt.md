A picked value in the same shell as a text field — position, role, date, time.

```jsx
<SelectField label="Primary position" options={['Goalkeeper','Defender','Midfielder','Forward']} />
<SelectField label="Date" value="Fri, 7 Aug 2026" icon="calendar_today" onClick={openDatePicker} />
```

Date and time fields never take typed input in this product; they open the platform picker.
