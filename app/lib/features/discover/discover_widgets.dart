import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../matches/compact_match_card.dart';
import '../profile/current_user.dart';
import '../profile/profile_models.dart';
import 'discover_models.dart';
import 'discover_repository.dart';

/// The pieces the public pages are built from.
///
/// They live together because they are one visual language — a landing page, a
/// community page, and whatever the next public surface turns out to be, all
/// reading as the same product. Each takes its data and its callbacks and knows
/// nothing about sessions, repositories or navigation; what a tap *means* is the
/// screen's business, which is what lets the same card sit on Discover for a
/// guest and for a member and do the right thing on each.
///
/// Sprint 2 changed how these look and nothing about what they do. Sizes,
/// spacings and radii now come from `core/design.dart`, so a card's padding is
/// the same measurement as the page's margin rather than a number that happened
/// to look right in one place.

/// The banner at the top of Discover: what this app is, what is happening on it
/// right now, and the one thing to do about that.
///
/// It says something different to the two people who see it. To a visitor it is
/// the pitch and the way in. To a member it is a welcome and an invitation to
/// start something — a signed-in player being asked to create an account would
/// be the banner not knowing who it was talking to.
///
/// Sprint 2 took roughly a third of its height out. Nothing was removed: the
/// logo, the greeting, the identity and the live counts are all still here. The
/// height came from the type ramp coming down one step, the gaps moving onto the
/// shared scale, and the two buttons sitting side by side instead of stacked —
/// which is also what puts them on the page's own left edge, level with the
/// cards below.
class DiscoverHero extends StatelessWidget {
  const DiscoverHero({
    super.key,
    required this.signedIn,
    required this.overview,
    required this.onPrimaryAction,
    required this.onLogIn,
  });

  final bool signedIn;
  final DiscoverOverview? overview;

  /// Create account for a visitor, create community for a member.
  final VoidCallback onPrimaryAction;

  /// Offered to a visitor only.
  final VoidCallback onLogIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ClubHero(
      // No title: the logo lockup in the identity row below already names the
      // product, and `ClubHeroBar.title` documents itself as the thing not to
      // repeat there. The bar is here for the account menu.
      // Through the bar's own contract now, rather than passed as one of this
      // screen's actions. It was never a Discover action: it is the identity
      // every shell screen carries, and saying so here is what let Home and
      // Communities be given the same thing.
      //
      // Still conditional on a session: a visitor has no identity to show, and
      // asking for one would be a read that cannot succeed.
      bar: ClubHeroBar(showCurrentUserMenu: signedIn),
      identity: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AppLogo(),
          const SizedBox(height: Gap.md),
          _Headline(signedIn: signedIn),
          const SizedBox(height: Gap.xs),
          Text(
            signedIn ? l10n.discoverHeroBodySignedIn : l10n.discoverHeroBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
          ),
        ],
      ),
      counts: overview == null ? null : _LivePulse(overview: overview!),
      action: _HeroActions(
        signedIn: signedIn,
        onPrimaryAction: onPrimaryAction,
        onLogIn: onLogIn,
      ),
    );
  }
}

/// The banner's buttons.
///
/// Side by side for a visitor, which is where the stacked "create account" and
/// "already have an account?" pair used to cost two rows and a paragraph of
/// text. Both are real buttons now and the primary one is wider, so which is
/// which is a matter of weight rather than of one being a link.
class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.signedIn,
    required this.onPrimaryAction,
    required this.onLogIn,
  });

  final bool signedIn;
  final VoidCallback onPrimaryAction;
  final VoidCallback onLogIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final primary = FilledButton(
      onPressed: onPrimaryAction,
      style: ClubHeroButtons.filled,
      child: Text(
        signedIn ? l10n.createCommunityTitle : l10n.registerButton,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (signedIn) return primary;

    return Row(
      children: [
        Expanded(flex: 3, child: primary),
        const SizedBox(width: Gap.sm),
        Expanded(
          flex: 2,
          child: OutlinedButton(
            onPressed: onLogIn,
            style: ClubHeroButtons.ghost,
            child: Text(
              l10n.loginButton,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// The banner's first line.
///
/// A member is greeted by name; a visitor gets the product's claim. The name is
/// read from the profile the session already holds, so this costs nothing — and
/// a profile that has not arrived yet falls back to the same claim rather than
/// to a greeting addressed to nobody.
class _Headline extends StatelessWidget {
  const _Headline({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    Widget line(String text) => Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // One step down from Sprint 1's headlineMedium. The theme made
          // headings heavier and tighter, so this reads as strongly at less
          // height — which is the whole of Priority 2 in one line.
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            height: 1.15,
          ),
        );

    if (!signedIn) return line(l10n.discoverHeroTitle);

    return ValueListenableBuilder<PlayerProfile?>(
      valueListenable: CurrentUser.instance.profile,
      builder: (context, profile, _) {
        final name = firstNameOf(profile?.fullName ?? '');
        return line(name.isEmpty
            ? l10n.discoverHeroTitle
            : l10n.discoverWelcomeBack(name));
      },
    );
  }
}

/// What is happening on the platform right now, in two numbers.
///
/// This is what makes the page feel alive on the first frame after it loads:
/// the banner stops being a slogan and starts reporting. Both figures are the
/// lists directly below it, so they cannot disagree with what the visitor is
/// about to scroll through.
class _LivePulse extends StatelessWidget {
  const _LivePulse({required this.overview});

  final DiscoverOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.xs,
      children: [
        _PulseChip(
          icon: Icons.groups,
          label: l10n.discoverCommunityCount(overview.communities.length),
          foreground: scheme.onPrimary,
        ),
        _PulseChip(
          icon: Icons.sports_soccer,
          label: l10n.discoverUpcomingCount(overview.matches.length),
          foreground: scheme.onPrimary,
        ),
      ],
    );
  }
}

class _PulseChip extends StatelessWidget {
  const _PulseChip({
    required this.icon,
    required this.label,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: Gap.xs + 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// The app's mark: the name, against the ball it is about.
class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: scheme.onPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.sports_soccer, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: Gap.sm),
        Text(
          context.l10n.appName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// A section's title, and one line saying what it is.
///
/// The accent rule and the subtitle are what turn a scrolling page into a feed:
/// each section announces itself, so "Upcoming matches" ends and "Communities"
/// begins rather than the two running together as one list of cards.
///
/// There is deliberately no count. Sprint 2 put one in a pill at the end of the
/// row, and on the device it read as an internal marker rather than as a
/// figure — a bare "1" beside a heading looks like something a developer left
/// behind. The number was never load-bearing: the cards below are the count,
/// and the banner already reports the totals.
class DiscoverSectionHeader extends StatelessWidget {
  const DiscoverSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;

  /// One line under the heading. What the section is for, in the reader's
  /// terms — not a description of the data.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.xxl,
        kPageMargin,
        Gap.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A short rule in the brand colour, aligned to the heading's cap
          // height. Cheap, and it is what makes the header look placed.
          Container(
            width: 3,
            height: 22,
            margin: const EdgeInsetsDirectional.only(end: Gap.md, top: 2),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One upcoming match, as a visitor sees it.
///
/// Built around a date tile, which is the thing that makes a match card read as
/// an event rather than as a community with different words in it. A match is a
/// moment; a community is a place. Priority 4 asked for the two to be visually
/// distinct, and the honest way to do that is to lead each with what it actually
/// is — a date here, a mark there — rather than to tint one of them.
class PublicMatchCard extends StatelessWidget {
  const PublicMatchCard({
    super.key,
    required this.match,
    required this.actionLabel,
    required this.onAction,
    this.showCommunityName = true,
  });

  final PublicMatch match;
  final String actionLabel;
  final VoidCallback onAction;

  /// False on a community's own page, where every match belongs to the
  /// community whose name is already at the top of the screen.
  final bool showCommunityName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageMargin,
        vertical: Gap.xs + 2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateTile(day: match.startAt),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          if (showCommunityName) ...[
                            const SizedBox(height: 2),
                            Text(
                              match.communityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: Gap.sm),
                          _DetailLine(
                            icon: Icons.schedule_outlined,
                            text: formatTimeRange(
                                context, match.startAt, match.endAt),
                          ),
                          const SizedBox(height: Gap.xs),
                          _DetailLine(
                            icon: Icons.place_outlined,
                            text: match.location,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    // Flexible, so that a narrow phone spends its width on the
                    // fixture rather than on the seat count. The badge is the
                    // secondary fact here; when the two cannot both have what
                    // they want, it is the one that gives.
                    Flexible(child: _SeatsBadge(match: match)),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                FilledButton.tonal(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same public match, drawn for a column.
///
/// Discover lays its upcoming matches out two across, so the card there cannot
/// be [PublicMatchCard]: that one is a row, and a row does not halve. This
/// borrows [CompactMatchShell] from the signed-in side rather than restating the
/// arrangement, which is what keeps a match looking like the same object to a
/// visitor and to a member reading the same page.
///
/// Both of the original's ways in survive. The card opens the match, as it did,
/// and the named button under it does the same thing — kept for the reason it
/// was put there: for a visitor it is the one place the word "join" appears
/// before they have an account.
class CompactPublicMatchCard extends StatelessWidget {
  const CompactPublicMatchCard({
    super.key,
    required this.match,
    required this.actionLabel,
    required this.onAction,
    this.showCommunityName = true,
  });

  final PublicMatch match;
  final String actionLabel;
  final VoidCallback onAction;
  final bool showCommunityName;

  @override
  Widget build(BuildContext context) {
    return CompactMatchShell(
      onTap: onAction,
      day: match.startAt,
      badge: _SeatsBadge(match: match),
      title: match.displayName,
      subtitle: showCommunityName ? match.communityName : null,
      time: formatTimeRange(context, match.startAt, match.endAt),
      location: match.location,
      action: FilledButton.tonal(
        onPressed: onAction,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Layout.buttonHeightSmall),
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        ),
        child: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// The day a match falls on, stacked: weekday, date, month.
///
/// Reads at a glance from across a scrolling list, which the full "Sat, 6 Mar
/// 2027" line it replaced never did — that line is still on the card for a
/// reader who wants it, in the match's own screen.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatWeekdayShort(context, day).toUpperCase(),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            formatDayNumber(context, day),
            maxLines: 1,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              height: 1.1,
            ),
          ),
          Text(
            formatMonthShort(context, day),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// How many places are left, or that there are none.
class _SeatsBadge extends StatelessWidget {
  const _SeatsBadge({required this.match});

  final PublicMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final full = match.isFull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(
        color:
            full ? scheme.surfaceContainerHighest : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        full ? l10n.matchStatusFull : l10n.discoverSeatsLeft(match.openSlots),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color:
                  full ? scheme.onSurfaceVariant : scheme.onSecondaryContainer,
            ),
      ),
    );
  }
}

/// An icon and the fact beside it.
///
/// The icon is optically centred on the text's first line rather than on the
/// whole block, which is what stops a wrapped location dragging its pin down
/// with it.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// One community, as a visitor sees it.
///
/// Opening it is the primary action and says so: a named button, filled, first
/// in the row and wider than the one beside it. The card is tappable as well,
/// but a tappable card is an affordance somebody has to guess at, and the
/// sprint's flow — browse, open, then decide — depends on this being the obvious
/// next step rather than the hidden one.
///
/// Join stays on the card because a member browsing for a new community should
/// not have to open one to join it. It is the quieter of the two.
class PublicCommunityCard extends StatelessWidget {
  const PublicCommunityCard({
    super.key,
    required this.community,
    required this.onOpen,
    required this.onJoin,
    this.clubStyle = false,
  });

  final PublicCommunity community;
  final VoidCallback onOpen;
  final VoidCallback onJoin;

  /// Discover uses the frozen Club card; the public community page retains its
  /// existing presentation while sharing the same callbacks and data.
  final bool clubStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = community.description?.trim() ?? '';

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: clubStyle ? Layout.sheetGutter : kPageMargin,
        vertical: Gap.xs + 2,
      ),
      child: Card(
        color: clubStyle ? GoColors.surfaceCard : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // One shape for a community, in both card styles. The
                    // public card used to draw a circle here, which is the
                    // player's shape — the two sit beside each other often
                    // enough that the difference has to be the shape. Only the
                    // size still differs, exactly as it did.
                    CommunityCrest(
                      name: community.name,
                      logoUrl: community.logoUrl,
                      size: clubStyle ? 46 : 52,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            community.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: clubStyle
                                ? GoType.cardTitle.copyWith(
                                    color: GoColors.onSurface,
                                  )
                                : theme.textTheme.titleMedium,
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: Gap.sm),
                          CommunityCounts(community: community),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.tonalIcon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding:
                              const EdgeInsets.symmetric(horizontal: Gap.md),
                        ),
                        label: Text(
                          l10n.viewCommunityAction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: onJoin,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding:
                              const EdgeInsets.symmetric(horizontal: Gap.sm),
                        ),
                        child: Text(
                          l10n.joinCommunityButton,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same community, drawn for a column.
///
/// Stacked rather than halved: the crest sits above the name instead of beside
/// it, because a 46px mark and a wrapping community name cannot share the width
/// of half a phone and both come out readable.
///
/// **The crest is the crest, not a slot.** A community's identity in this
/// product is its initials in a rounded square, exactly as [CommunityCrest]
/// draws them everywhere else — there is no logo column behind it, nothing here
/// is holding space for a picture, and this card must not be read as preparing
/// for one.
///
/// Both actions are kept and both are stacked. Opening stays the loud one, for
/// the reason [PublicCommunityCard] gives; joining stays on the card because a
/// member browsing should still not have to open a community to join it. Side by
/// side they would each get about seventy pixels, which is not enough for either
/// label in Arabic.
class CompactPublicCommunityCard extends StatelessWidget {
  const CompactPublicCommunityCard({
    super.key,
    required this.community,
    required this.onOpen,
    required this.onJoin,
  });

  final PublicCommunity community;
  final VoidCallback onOpen;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final description = community.description?.trim() ?? '';

    return Card(
      margin: EdgeInsets.zero,
      color: GoColors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommunityCrest(
                name: community.name,
                logoUrl: community.logoUrl,
                size: 42,
              ),
              const SizedBox(height: Gap.sm),
              // Two lines. A community name is the thing being chosen between,
              // so it wraps where the description below it merely shortens.
              Text(
                community.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoType.cardTitle.copyWith(color: GoColors.onSurface),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: GoColors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: Gap.sm),
              CommunityCounts(community: community),
              const SizedBox(height: Gap.md),
              FilledButton.tonal(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(Layout.buttonHeightSmall),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                ),
                child: Text(
                  l10n.viewCommunityAction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton(
                onPressed: onJoin,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(Layout.buttonHeightSmall),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                ),
                child: Text(
                  l10n.joinCommunityButton,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How big a community is and what it has coming up.
///
/// The upcoming count is dropped when it is zero rather than shown as "0
/// matches": an empty schedule is not a fact worth a line of its own on a card
/// that is trying to be inviting.
class CommunityCounts extends StatelessWidget {
  const CommunityCounts({super.key, required this.community});

  final PublicCommunity community;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.onSurfaceVariant);

    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.xs,
      children: [
        _Count(
          icon: Icons.person_outline,
          label: l10n.discoverMemberCount(community.memberCount),
          style: style,
        ),
        if (community.upcomingMatchCount > 0)
          _Count(
            icon: Icons.sports_soccer_outlined,
            label: l10n.discoverUpcomingCount(community.upcomingMatchCount),
            style: style,
          ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.label, this.style});

  final IconData icon;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: Gap.xs),
        // Flexible, because the `Wrap` above offers the line's full width and
        // nothing narrower: a count whose label does not fit on one line has
        // to give, and a shortened count still counts.
        Flexible(
          child: Text(
            label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The closing ask, at the bottom of the page.
///
/// Deliberately the second time the same button appears rather than the first:
/// somebody who has scrolled past the matches and the communities has seen what
/// the platform is for, which is a better moment to ask than the top of the
/// page. A member is asked for the other thing — nobody who is already signed in
/// needs an account, but plenty of them have a regular game with no community
/// behind it yet.
class DiscoverCta extends StatelessWidget {
  const DiscoverCta({
    super.key,
    required this.signedIn,
    required this.onCreateAccount,
    required this.onCreateCommunity,
  });

  final bool signedIn;
  final VoidCallback onCreateAccount;
  final VoidCallback onCreateCommunity;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.xxl,
        kPageMargin,
        Gap.xl,
      ),
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                signedIn ? Icons.groups : Icons.sports_soccer,
                size: 26,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          Text(
            signedIn ? l10n.discoverCtaTitleSignedIn : l10n.discoverCtaTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            signedIn ? l10n.discoverCtaBodySignedIn : l10n.discoverCtaBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.lg),
          if (!signedIn) ...[
            FilledButton(
              onPressed: onCreateAccount,
              child: Text(l10n.registerButton),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton(
              onPressed: onCreateCommunity,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kButtonHeight),
              ),
              child: Text(l10n.createCommunityTitle),
            ),
          ] else
            FilledButton(
              onPressed: onCreateCommunity,
              child: Text(l10n.createCommunityTitle),
            ),
        ],
      ),
    );
  }
}

/// What a section says when it has nothing in it.
///
/// Deliberately not styled like a failure. An empty section is the ordinary
/// state of a new community or a quiet week, and the old treatment — a grey
/// outline icon over grey text — was indistinguishable from the "failed to load"
/// panel three sections up. This one is a soft filled panel with the brand
/// colour in it, and it says what would fill the space rather than that the
/// space is empty.
class DiscoverEmpty extends StatelessWidget {
  const DiscoverEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;

  /// An optional way out of the empty state.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.xl,
          vertical: Gap.xl,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: Gap.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: Gap.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
