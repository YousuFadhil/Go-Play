export interface ErrorStateProps {
  /** Defaults to the generic load failure. Pass something specific only when you know more, e.g. "Could not reach the server. Check your internet connection." */
  message?: string;
  retryLabel?: string;
  onRetry?: () => void;
  style?: React.CSSProperties;
}
export declare function ErrorState(props: ErrorStateProps): JSX.Element;
