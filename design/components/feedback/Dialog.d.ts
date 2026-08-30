export interface DialogProps {
  /** A question: "Delete this match?", "Withdraw from this match?" */
  title: string;
  /** What will actually happen, including the part the reader would not guess. */
  body: string;
  cancelLabel?: string;
  confirmLabel: string;
  /** Turns the confirm button error-coloured. Every irreversible action sets this. */
  destructive?: boolean;
  onCancel?: () => void;
  onConfirm?: () => void;
  style?: React.CSSProperties;
}
export declare function Dialog(props: DialogProps): JSX.Element;
