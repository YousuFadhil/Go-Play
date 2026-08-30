export interface SwitchRowProps {
  label: string;
  /** What the setting actually does. The app never ships a bare switch. */
  subtitle?: string;
  checked?: boolean;
  onChange?: (next: boolean) => void;
  disabled?: boolean;
  style?: React.CSSProperties;
}
export declare function SwitchRow(props: SwitchRowProps): JSX.Element;
