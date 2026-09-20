import 'package:flutter/material.dart';

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
import '../profile/profile_screen.dart';
import '../teams/match_stage.dart';
import '../teams/match_stage_board.dart';
import 'discover_models.dart';
import 'public_match_stage.dart';
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

    // **The same surface a member gets.** A played match is a pitch, and the
    // Match Stage is where this product draws one -- so the public route uses
    // the stage's own ground, its own bar and its own board rather than a
    // white sheet with two name lists on it. What differs is capability: there
    // is no share action here, no management, and a name leads to a profile
    // only where the database published one.
    return Scaffold(
      backgroundColor: MatchStage.ground,
      appBar: matchStageAppBar(
        context,
        key: const ValueKey('public-match-app-bar'),
        title: l10n.matchDetailsTitle,
      ),
      body: MatchStageGround(
        child: RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 20),
            children: [
              if (match.lineup.isNotEmpty)
                PublicMatchStage(match: match, onOpenPlayer: onOpenPlayer)
              else ...[
                // **No pitch without a lineup.** An empty one would report
                // that nobody turned up, which is a different claim from "the
                // teams were not published". The header still carries the
                // match and its score.
                const SizedBox(height: Gap.md),
                MatchStageHeader(
                  community: match.communityName,
                  title: match.title ?? match.communityName,
                  playedAt: match.startAt,
                  teamAScore: match.teamAScore,
                  teamBScore: match.teamBScore,
                ),
              ],
              _WhenAndWhere(match: match),
              _GuestActions(onLogin: onLogin, onRegister: onRegister),
            ],
          ),
        ),
      ),
    );
  }
}

/// When it was played, and where.
///
/// Set in the stage's own muted ink so it belongs to the ground rather than to
/// a document pasted onto it -- the same treatment the member's route gives
/// the same two facts.
class _WhenAndWhere extends StatelessWidget {
  const _WhenAndWhere({required this.match});

  final PublicCompletedMatch match;

  @override
  Widget build(BuildContext context) {
    final location = match.location;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageNote(
          formatDayAndTimeRange(context, match.startAt, match.endAt),
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.md,
            kPageMargin,
            0,
          ),
        ),
        if (location != null && location.trim().isNotEmpty)
          _StageNote(
            location,
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.xs,
              kPageMargin,
              0,
            ),
          ),
      ],
    );
  }
}

/// One line of quiet type on the ground.
class _StageNote extends StatelessWidget {
  const _StageNote(this.text, {required this.padding});

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
      );
}

/// What a reader with no account is offered at the foot of the page.
class _GuestActions extends StatelessWidget {
  const _GuestActions({required this.onLogin, required this.onRegister});

  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // On a white panel, because the stage behind it is dark and an auth form
    // painted straight onto the ground would be both unreadable and a
    // degradation of the football it sits under.
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(
        kPageMargin,
        Layout.sectionAbove,
        kPageMargin,
        0,
      ),
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: GoColors.surfaceSheet,
        borderRadius: BorderRadius.circular(Radii.card),
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
