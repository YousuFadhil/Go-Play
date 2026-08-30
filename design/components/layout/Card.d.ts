export interface CardProps {
  /** 16px of padding. Turn off for a card that holds full-bleed rows. */
  padded?: boolean;
  /** Adds the tap affordance (hover tint + pointer) without needing a handler. */
  interactive?: boolean;
  /** A 1.5px green edge. Reserved for the ONE card on a screen that is the next action — the next match, the registration state. Never more than one per screen. */
  outlined?: boolean;
  onClick?: () => void;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function Card(props: CardProps): JSX.Element;
