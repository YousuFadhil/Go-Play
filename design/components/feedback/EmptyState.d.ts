export interface EmptyStateProps {
  /** Material Symbols name. Match-shaped emptiness uses "sports_soccer"; a community one uses "groups". */
  icon?: string;
  /** Optional. Skip it where the message is one sentence — a title above it would repeat that sentence in fewer words. */
  title?: string;
  message: string;
  /** A quieter second line: usually why something is unavailable rather than what to do about it. */
  note?: string;
  /** Offer a Button only where the reader can actually do something about it. */
  action?: React.ReactNode;
  /** "accent" tints the disc with the brand colour — used where the emptiness is inviting rather than merely empty. */
  tone?: 'neutral' | 'accent';
  style?: React.CSSProperties;
}
export declare function EmptyState(props: EmptyStateProps): JSX.Element;
