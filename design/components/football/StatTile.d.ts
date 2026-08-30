export interface StatTileProps {
  icon?: string;
  value: number | string;
  label: string;
  tone?: 'accent' | 'neutral';
  style?: React.CSSProperties;
}
export declare function StatTile(props: StatTileProps): JSX.Element;
