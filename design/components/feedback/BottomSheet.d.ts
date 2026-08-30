export interface BottomSheetProps {
  /** Usually the name of the thing being acted on — the community, the match. */
  title?: string;
  /** ListRows, and a Divider before anything destructive. */
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function BottomSheet(props: BottomSheetProps): JSX.Element;
