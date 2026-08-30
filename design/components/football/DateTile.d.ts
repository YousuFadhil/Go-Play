export interface DateTileProps {
  /** Short weekday, e.g. "Thu". Rendered upper-case. */
  weekday: string;
  /** Day of month, e.g. 13. */
  day: number | string;
  /** Short month, e.g. "Aug". */
  month: string;
  /** Played matches show a tick instead of a date. */
  completed?: boolean;
  style?: React.CSSProperties;
}
export declare function DateTile(props: DateTileProps): JSX.Element;
