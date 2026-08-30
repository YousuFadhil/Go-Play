export interface RatingHeroProps {
  /** Formatted to one decimal, e.g. "5.0". */
  value: number | string;
  label?: string;
  /** Recent ratings, oldest first — drawn as a small bar sparkline with the latest highlighted. Six is the right number. */
  form?: number[];
  style?: React.CSSProperties;
}
export declare function RatingHero(props: RatingHeroProps): JSX.Element;
