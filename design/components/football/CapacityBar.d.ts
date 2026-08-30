export interface CapacityBarProps {
  registered: number;
  /** Playing capacity — starting_players. */
  starting: number;
  /** Reserve allowance. Drawn as a separate teal run after a gap, so a reader can see they would be taking a reserve place before they tap. */
  reserve?: number;
  /** Colours the filled run: green when open, amber when full, grey once played. */
  status?: 'open' | 'full' | 'completed';
  showLabel?: boolean;
  /** 5px segments instead of 7 — for a bar inside a list row. */
  compact?: boolean;
  style?: React.CSSProperties;
}
export declare function CapacityBar(props: CapacityBarProps): JSX.Element;
