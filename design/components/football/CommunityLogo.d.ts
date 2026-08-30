export interface CommunityLogoProps {
  /** Community name. Initials are taken from its first two words. */
  name?: string;
  /** 17–22 inline beside a label, 38 in a list, 56–68 on a community hero. */
  size?: number;
  /** Translucent white treatment for a crest sitting on the green hero. */
  onHero?: boolean;
  style?: React.CSSProperties;
}
export declare function CommunityLogo(props: CommunityLogoProps): JSX.Element;
