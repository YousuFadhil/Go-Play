export interface DividerProps {
  /** Leading indent in px, for a divider that should start at the text rather than the card edge. */
  inset?: number;
  /** Removes the 12px of air above and below. */
  tight?: boolean;
  style?: React.CSSProperties;
}
export declare function Divider(props: DividerProps): JSX.Element;
