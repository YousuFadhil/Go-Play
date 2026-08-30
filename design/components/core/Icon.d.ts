export interface IconProps {
  /** Material Symbols ligature name, e.g. "sports_soccer", "place", "schedule". */
  name: string;
  /** Optical size in px. The app uses 24 in bars, 18 on buttons, 15 on card detail lines, 14 in chips. */
  size?: number;
  /** Filled variant. The app fills only a selected bottom-nav destination. */
  fill?: boolean;
  color?: string;
  weight?: 100|200|300|400|500|600|700;
  style?: React.CSSProperties;
}
export declare function Icon(props: IconProps): JSX.Element;
