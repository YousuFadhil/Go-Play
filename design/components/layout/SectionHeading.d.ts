export interface SectionHeadingProps {
  title: string;
  /** Appended after a middot in the outline colour — "Members · 24". Cheaper than a pill and it survives Arabic. */
  count?: number | string;
  /** One text action on the right, e.g. "Manage", "See all", "Arrange". */
  action?: string;
  onAction?: () => void;
  style?: React.CSSProperties;
}
export declare function SectionHeading(props: SectionHeadingProps): JSX.Element;
