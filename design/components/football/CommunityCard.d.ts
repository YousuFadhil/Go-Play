export interface CommunityCardProps {
  name: string;
  description?: string;
  memberCount?: number;
  /** Dropped when zero: an empty schedule is not a fact worth a line on a card that is trying to be inviting. */
  upcomingCount?: number;
  /** "Owner" | "Admin" — a square chip. A Player's role is not shown; it is the default. */
  role?: string;
  /** Draws the small key glyph — this community asks for its join code. */
  codeRequired?: boolean;
  /** A Button or IconButton on the end, where the list offers one action per row (e.g. "Open" on Discover). */
  trailing?: React.ReactNode;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function CommunityCard(props: CommunityCardProps): JSX.Element;
