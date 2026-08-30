export interface SegmentedControlProps {
  options: Array<{ value: string; label: string } | string>;
  value: string;
  onChange?: (value: string) => void;
  /** Stretches to the container. The statistics selector is full width; the language switch is not. */
  fullWidth?: boolean;
  style?: React.CSSProperties;
}
export declare function SegmentedControl(props: SegmentedControlProps): JSX.Element;
