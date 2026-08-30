export interface SelectOption { value: string; label: string }
export interface SelectFieldProps {
  label: string;
  value?: string;
  placeholder?: string;
  /** Provide to render a native select. Omit and pass onClick for a field that opens a picker (date, time). */
  options?: SelectOption[] | string[];
  error?: string;
  /** Trailing glyph. "expand_more" for a select, "calendar_today" for a date, "schedule" for a time. */
  icon?: string;
  disabled?: boolean;
  onChange?: (e: React.ChangeEvent<HTMLSelectElement>) => void;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function SelectField(props: SelectFieldProps): JSX.Element;
