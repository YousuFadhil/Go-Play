export interface MemberRowProps {
  name: string;
  /** "Owner" | "Admin" | "Player". Owner gets the accent avatar. */
  role?: string;
  position?: string;
  /** Marks the signed-in player with a square "You" chip. */
  you?: boolean;
  /** A role chip, an overflow IconButton, or a Button — whatever this screen permits. Suppresses the chevron. */
  trailing?: React.ReactNode;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function MemberRow(props: MemberRowProps): JSX.Element;
