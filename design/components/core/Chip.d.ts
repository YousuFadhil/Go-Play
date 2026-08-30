export interface ChipProps {
  /** open / full / completed are the three match states. reserve is the teal one. role is the neutral square marker for Owner / Admin / Player. onHero sits on the green crest hero. */
  tone?: 'open' | 'full' | 'completed' | 'reserve' | 'neutral' | 'accent' | 'danger' | 'onHero' | 'role';
  icon?: string;
  /** Square, small-caps variant — roles and position tags only. */
  square?: boolean;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function Chip(props: ChipProps): JSX.Element;
