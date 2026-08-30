export interface IconButtonProps {
  icon: string;
  /** Accessible name and tooltip — required. */
  label: string;
  /** Unread count. Drawn in the alert orange, which is used for this and nothing else. */
  badge?: number | string;
  active?: boolean;
  /** White treatment for a bar action sitting on the green hero. */
  onHero?: boolean;
  size?: number;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function IconButton(props: IconButtonProps): JSX.Element;
