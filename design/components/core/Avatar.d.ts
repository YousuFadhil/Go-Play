export interface AvatarProps {
  /** Picture URL. Falls back to initials, then to a person glyph. */
  src?: string;
  /** Full name — initials are derived from the first and last word. */
  name?: string;
  /** Diameter in px. 32 in the app header, 40 in roster rows, 96 on a profile. */
  size?: number;
  tone?: 'accent' | 'neutral';
  style?: React.CSSProperties;
}
export declare function Avatar(props: AvatarProps): JSX.Element;
