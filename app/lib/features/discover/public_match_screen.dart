import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../profile/player_identity.dart';
import '../profile/profile_record_sections.dart';
import '../profile/profile_screen.dart';
import 'discover_models.dart';
import 'discover_repository.dart';
import 'discover_widgets.dart';

/// A match, as a visitor sees it before signing in.
///
/// **What a `/match/{id}` link opens for somebody with no account**, and the
/// counterpart of [PublicCommunityScreen]. It has two readings, because a match
/// does: one that has not been played is an invitation — when, where, whose,
/// and how many places are left — and one that has is a result: the score, who
/// played, who scored and who was named best player.
///
/// **What is on it is what migrations `0079`'s public contracts return, and
/// nothing is assembled here from anything else.** There are no reserves, no
/// registration queue, no administrative state and no identifier for anybody
/// the database did not publish one for: a Professional Guest is a guest by
/// name and never a link, because a guest has no public profile to link to.
///
/// Registering still requires an account. The buttons open the app's own auth
/// screens; nothing here registers anybody.
class PublicMatchScreen extends StatefulWidget {
  const PublicMatchScreen({
    super.key,
    required this.matchId,
    this.repository,
    this.authService,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final DiscoverRepository? repository;
  final AuthService? authService;

  @override
  State<PublicMatchScreen> createState() => _PublicMatchScreenState();
}

class _PublicMatchScreenState extends State<PublicMatchScreen> {
  late final DiscoverRepository _repository =
      widget.repository ?? DiscoverRepository();

  late Future<PublicMatchDetail?> _future =
      _repository.fetchMatchDetail(widget.matchId);

  void _refresh() {
    setState(() {
      _future = _repository.fetchMatchDetail(widget.matchId);
    });
  }

  Future<void> _promptSignIn(String reason) => requireSignIn(
        context,
        reason: reason,
        authService: widget.authService,
      );

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// A name on the team sheet, opened as the public profile it is.
  ///
  /// The visitor reading, always: this screen is only ever built for a reader
  /// with no session, so the profile it opens must be the one the public
  /// contracts answer.
  void _openPlayer(String userId) {
    _push(ProfileScreen(userId: userId, asVisitor: true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<PublicMatchDetail?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _Shell(
            title: l10n.matchDetailsTitle,
            child: const _MatchSkeleton(),
          );
        }
        if (snapshot.hasError) {
          return _Shell(
            title: l10n.matchDetailsTitle,
            child: ErrorState(onRetry: _refresh),
          );
        }

        final detail = snapshot.data;
        // **Not an error, and not offered a retry.** No match here means the
        // link points at something this reader may not open — withdrawn, in a
        // community that is no longer active, or never real. Retrying would
        // fail again for the same reason, so the reader is told plainly and
        // given the one thing that might actually help.
        if (detail == null) {
          return _Shell(
            title: l10n.matchDetailsTitle,
            child: ListView(
              padding: const EdgeInsets.all(Gap.xl),
              children: [
                EmptyState(
                  icon: Icons.link_off,
                  title: l10n.publicContentUnavailableTitle,
                  message: l10n.publicContentUnavailable,
                ),
                const SizedBox(height: Gap.lg),
                FilledButton(
                  onPressed: () =>
                      _promptSignIn(l10n.authRequiredRegisterMatch),
                  child: Text(l10n.loginTitle),
                ),
              ],
            ),
          );
        }

        return switch (detail) {
          PublicUpcomingMatch(:final match) => _Shell(
              title: l10n.matchDetailsTitle,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xxl),
                children: [
                  // The same card the Discover page and the public community
                  // page draw a match with. One match is not a different kind
                  // of thing because it arrived through a link.
                  PublicMatchCard(
                    match: match,
                    actionLabel: l10n.joinMatchButton,
                    onAction: () =>
                        _promptSignIn(l10n.authRequiredRegisterMatch),
                  ),
                  FootNote(l10n.discoverMatchesSubtitle),
                ],
              ),
            ),
          PublicCompletedMatch() => _CompletedMatchPage(
              match: detail,
              onRefresh: _refresh,
              onOpenPlayer: _openPlayer,
              onLogin: () => _push(const LoginScreen()),
              onRegister: () => _push(const RegisterScreen()),
            ),
        };
      },
    );
  }
}

/// The page a visitor gets for a match that has been played.
///
/// The approved information hierarchy, in this order and no other: whose
/// community it was, which match and when, the result, then who played — with
/// the goals and the best-player mark the result already carries.
class _CompletedMatchPage extends StatelessWidget {
  const _CompletedMatchPage({
    required this.match,
    required this.onRefresh,
    required this.onOpenPlayer,
    required this.onLogin,
    required this.onRegister,
  });

  final PublicCompletedMatch match;
  final VoidCallback onRefresh;
  final ValueChanged<String> onOpenPlayer;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teamA = [
      for (final e in match.lineup)
        if (e.team == 'A') e
    ];
    final teamB = [
      for (final e in match.lineup)
        if (e.team == 'B') e
    ];

    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ClubHero(
              // The same ground the Player Profile opens on, so a shared match
              // and a shared player are visibly one product.
              stadium: true,
              bar: ClubHeroBar(
                title: l10n.matchDetailsTitle,
                onBack: Navigator.of(context).canPop()
                    ? () => Navigator.of(context).pop()
                    : null,
              ),
              identity: Row(
                children: [
                  CommunityCrest(
                    name: match.communityName,
                    logoUrl: match.communityLogoUrl,
                    onHero: true,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          match.title ?? match.communityName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          match.communityName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClubSheet(
              child: RefreshIndicator(
                onRefresh: () async => onRefresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    0,
                    Gap.lg,
                    0,
                    Gap.xxl,
                  ),
                  children: [
                    _WhenAndWhere(match: match),
                    _Scoreline(match: match),
                    if (match.mvpDisplayName != null)
                      _BestPlayer(
                        name: match.mvpDisplayName!,
                        avatarUrl: match.mvpAvatarUrl,
                      ),
                    if (match.lineup.isNotEmpty) ...[
                      ProfileSectionHeading(l10n.publicMatchLineupTitle),
                      _TeamSheet(
                        title: l10n.teamAName,
                        players: teamA,
                        onOpenPlayer: onOpenPlayer,
                      ),
                      _TeamSheet(
                        title: l10n.teamBName,
                        players: teamB,
                        onOpenPlayer: onOpenPlayer,
                      ),
                    ],
                    _GuestActions(onLogin: onLogin, onRegister: onRegister),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When it was played, and where.
class _WhenAndWhere extends StatelessWidget {
  const _WhenAndWhere({required this.match});

  final PublicCompletedMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final location = match.location;

    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: kPageMargin),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _MetaLine(
          icon: Icons.event_outlined,
          text: formatDayAndTimeRange(context, match.startAt, match.endAt),
        ),
        if (location != null && location.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          _MetaLine(icon: Icons.place_outlined, text: location),
        ],
        const SizedBox(height: Gap.sm),
        _MetaLine(
          icon: Icons.check_circle_outline,
          text: l10n.matchStatusCompleted,
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: IconSize.meta, color: GoColors.onSurfaceVariant),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: GoColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
}

/// The result: two teams and what they scored.
///
/// A match that ended with nothing recorded says so, rather than showing a
/// nil-nil that nobody played.
class _Scoreline extends StatelessWidget {
  const _Scoreline({required this.match});

  final PublicCompletedMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (!match.hasResult ||
        match.teamAScore == null ||
        match.teamBScore == null) {
      return SectionCard(
        margin: const EdgeInsets.symmetric(horizontal: kPageMargin),
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          Text(
            l10n.matchResultNotRecorded,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: GoColors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final a = match.teamAScore!;
    final b = match.teamBScore!;
    final outcome = a == b
        ? l10n.matchResultDrawLabel
        : '${l10n.matchResultWinnerLabel}: '
            '${a > b ? l10n.teamAName : l10n.teamBName}';

    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: kPageMargin),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Row(
          children: [
            Expanded(child: _TeamName(l10n.teamAName)),
            // Each score sits beside its own team, so the pair mirrors with
            // the names in Arabic rather than staying put while they swap. A
            // single left-to-right string would put Team A's goals next to
            // Team B on an Arabic page.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Score('$a'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Gap.sm),
                    child: _Score('-'),
                  ),
                  _Score('$b'),
                ],
              ),
            ),
            Expanded(child: _TeamName(l10n.teamBName)),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          outcome,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: GoColors.primary,
          ),
        ),
      ],
    );
  }
}

/// One half of the result, at the size a score is read at.
class _Score extends StatelessWidget {
  const _Score(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          fontSize: 30,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      );
}

class _TeamName extends StatelessWidget {
  const _TeamName(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      );
}

/// Who was named best player, when the result names one.
class _BestPlayer extends StatelessWidget {
  const _BestPlayer({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SectionCard(
      margin: const EdgeInsetsDirectional.fromSTEB(
        kPageMargin,
        0,
        kPageMargin,
        Gap.sm,
      ),
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GoColors.warnContainer,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: const Icon(
                Icons.star,
                size: 24,
                color: GoColors.onWarnContainer,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.mvpLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: GoColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            PlayerAvatar(avatarUrl: avatarUrl, fullName: name, radius: 20),
          ],
        ),
      ],
    );
  }
}

/// One team's sheet: who played, what they scored, and who was best.
class _TeamSheet extends StatelessWidget {
  const _TeamSheet({
    required this.title,
    required this.players,
    required this.onOpenPlayer,
  });

  final String title;
  final List<PublicLineupEntry> players;
  final ValueChanged<String> onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      margin: const EdgeInsetsDirectional.fromSTEB(
        kPageMargin,
        0,
        kPageMargin,
        Gap.md,
      ),
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Gap.lg,
            Gap.sm,
            Gap.lg,
            Gap.sm,
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        for (final player in players)
          _PlayerRow(player: player, onOpenPlayer: onOpenPlayer),
      ],
    );
  }
}

/// One name on a team sheet.
///
/// **A name leads to a profile exactly when the database sent an id with it.**
/// A Professional Guest never has one — they are not an account — and neither
/// does a player whose public profile is unavailable, so the row is plain text
/// rather than a link that would open a page saying no.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.onOpenPlayer});

  final PublicLineupEntry player;
  final ValueChanged<String> onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final playerId = player.playerId;
    final position = player.assignedPosition;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.sm,
      ),
      child: Row(
        children: [
          PlayerAvatar(
            avatarUrl: player.avatarUrl,
            fullName: player.displayName,
            isProfessionalGuest: player.isProfessionalGuest,
            radius: 16,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.isProfessionalGuest
                      ? l10n.professionalGuestName(player.displayName)
                      : player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (position != null && position.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    position,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: GoColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (player.isMvp)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: Gap.sm),
              child: Icon(Icons.star, size: IconSize.row, color: GoColors.warn),
            ),
          if (player.goals > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Gap.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sports_soccer,
                    size: IconSize.meta,
                    color: GoColors.primaryMid,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${player.goals}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (playerId != null)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: Gap.xs),
              child: Icon(
                Icons.chevron_right,
                size: IconSize.row,
                color: GoColors.chevron,
              ),
            ),
        ],
      ),
    );

    if (playerId == null) return row;
    return InkWell(onTap: () => onOpenPlayer(playerId), child: row);
  }
}

/// What a reader with no account is offered at the foot of the page.
class _GuestActions extends StatelessWidget {
  const _GuestActions({required this.onLogin, required this.onRegister});

  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        kPageMargin,
        Layout.sectionAbove,
        kPageMargin,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: GoColors.surfaceContainer,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: IconSize.row,
                  color: GoColors.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    l10n.publicMatchGuestPrompt,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: GoColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: onLogin,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(kButtonHeight),
            ),
            child: Text(l10n.loginTitle),
          ),
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: onRegister,
            style: FilledButton.styleFrom(
              backgroundColor: GoColors.rowTintLight,
              foregroundColor: GoColors.onSurface,
              minimumSize: const Size.fromHeight(kButtonHeight),
            ),
            child: Text(l10n.registerTitle),
          ),
        ],
      ),
    );
  }
}

/// The page before it has a match on it, and when it could not read one.
///
/// A plain bar and not the app's own header: that bar carries the signed-in
/// player's face, and there is nobody here to name.
class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child, this.onRefresh});

  final String title;
  final Widget child;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final body = onRefresh == null
        ? child
        : RefreshIndicator(onRefresh: () async => onRefresh!(), child: child);

    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}

/// The shape of the page, before it arrives.
class _MatchSkeleton extends StatelessWidget {
  const _MatchSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonFade(
      child: Padding(
        padding: EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
        child: Column(
          children: [
            MatchCardSkeleton(),
          ],
        ),
      ),
    );
  }
}
