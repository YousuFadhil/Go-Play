export interface ListRowProps {
  /** Material Symbols name for the leading glyph. */
  icon?: string;
  /** Anything else in the leading slot — an Avatar, a CommunityLogo. Wins over icon. */
  leading?: React.ReactNode;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  trailing?: React.ReactNode;
  /** Adds the trailing chevron for a row that navigates. */
  chevron?: boolean;
  /** Error colour for the title and glyph — destructive actions in a sheet. */
  danger?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function ListRow(props: ListRowProps): JSX.Element;
