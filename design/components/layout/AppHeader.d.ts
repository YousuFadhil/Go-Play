export interface AppHeaderUser { name: string; avatarUrl?: string }
export interface AppHeaderProps {
  title: React.ReactNode;
  /** Shows the back arrow. Omit on the three bottom-nav roots. */
  onBack?: () => void;
  /** The screen's own IconButtons. The identity is appended after them. */
  actions?: React.ReactNode;
  /** The signed-in player. Never passed on login, register or the invitation landing screen — there is no player to name there. */
  user?: AppHeaderUser;
  /** Draws the hairline that appears only once content is behind the bar. */
  scrolled?: boolean;
  style?: React.CSSProperties;
}
export declare function AppHeader(props: AppHeaderProps): JSX.Element;
