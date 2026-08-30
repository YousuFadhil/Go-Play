export interface MatchCardProps {
  /** The match's own name. Falls back to the location when a match has no name — and then the location is not repeated underneath. */
  title: string;
  /** Shown on Home and Discover, where matches come from several communities — always with the small crest before it. Omitted on a community's own page. */
  communityName?: string;
  location?: string;
  /** Formatted range, e.g. "17:25 – 18:35". */
  time?: string;
  weekday: string;
  day: number | string;
  month: string;
  status?: 'open' | 'full' | 'completed';
  registered?: number;
  /** Playing capacity — starting_players, never max_registration. */
  starting?: number;
  reserve?: number;
  /** Overrides the chip text. Defaults to Open / Full / Played. */
  statusLabel?: string;
  /** The green edge. Use on the single next-up match at the top of Home, nowhere else. */
  outlined?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function MatchCard(props: MatchCardProps): JSX.Element;
