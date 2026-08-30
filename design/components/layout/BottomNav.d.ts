export interface BottomNavItem { value: string; label: string; icon: string }
export interface BottomNavProps {
  /** Go Play ships exactly three: Discover, Home, Communities — in that order. */
  items: BottomNavItem[];
  value: string;
  onChange?: (value: string) => void;
  /** Floats 14px off the bottom with a shadow (the default). Set false to dock it with a top hairline. */
  floating?: boolean;
  style?: React.CSSProperties;
}
export declare function BottomNav(props: BottomNavProps): JSX.Element;
