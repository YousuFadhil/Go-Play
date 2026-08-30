export interface ParticipantRowProps {
  name: string;
  /** "Goalkeeper" | "Defender" | "Midfielder" | "Forward". Ignored for a guest. */
  position?: string;
  /** A professional guest: named through the approved sentence and labelled instead of positioned. */
  guest?: boolean;
  /** Position in the list, shown on the arrange-participants screen. */
  index?: number;
  /** Reserve-list styling: neutral avatar, teal subtitle. */
  reserve?: boolean;
  trailing?: React.ReactNode;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function ParticipantRow(props: ParticipantRowProps): JSX.Element;
