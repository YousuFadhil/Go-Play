export interface HeroProps {
  children?: React.ReactNode;
  /** The faint ball texture. On by default; turn off for a hero that already carries a photo or a dense stat row. */
  ball?: boolean;
  style?: React.CSSProperties;
}
export declare function Hero(props: HeroProps): JSX.Element;

export interface HeroBarProps {
  title?: React.ReactNode;
  onBack?: () => void;
  right?: React.ReactNode;
}
export declare function HeroBar(props: HeroBarProps): JSX.Element;

export interface SheetProps {
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function Sheet(props: SheetProps): JSX.Element;
