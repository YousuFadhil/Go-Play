export interface ButtonProps {
  /** filled = the one primary action on the screen. tonal = a secondary action on a light surface. outlined = a quiet alternative beside a filled one. text = low stakes. onHero / ghost = the pair that sits on the green crest hero. danger = destructive confirmation only. */
  variant?: 'filled' | 'tonal' | 'outlined' | 'text' | 'onHero' | 'ghost' | 'danger';
  /** 52 / 44 / 38. default for a screen's primary action, compact inside a card, small inside a row. */
  size?: 'default' | 'compact' | 'small';
  icon?: string;
  trailingIcon?: string;
  fullWidth?: boolean;
  disabled?: boolean;
  loading?: boolean;
  onClick?: () => void;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function Button(props: ButtonProps): JSX.Element;
