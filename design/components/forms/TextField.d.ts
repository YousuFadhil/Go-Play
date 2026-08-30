export interface TextFieldProps {
  /** Always set. The app has no placeholder-only fields — the label stays visible above the value. */
  label: string;
  value?: string;
  defaultValue?: string;
  placeholder?: string;
  /** A quiet line under the field. Use for format hints, e.g. "8 digits, e.g. 9012 3456". */
  helper?: string;
  /** Replaces the helper and turns the border and label red. Validation messages are full sentences. */
  error?: string;
  /** Character counter, e.g. "12/60". The app sets maxLength 60 on a match title, 100 on a location. */
  counter?: string;
  maxLength?: number;
  type?: string;
  multiline?: boolean;
  rows?: number;
  disabled?: boolean;
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void;
  id?: string;
  style?: React.CSSProperties;
}
export declare function TextField(props: TextFieldProps): JSX.Element;
