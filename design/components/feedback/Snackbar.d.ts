export interface SnackbarProps {
  children?: React.ReactNode;
  /** A single optional action label. Go Play uses at most one, and never for undo. */
  action?: string;
  onAction?: () => void;
  style?: React.CSSProperties;
}
export declare function Snackbar(props: SnackbarProps): JSX.Element;
