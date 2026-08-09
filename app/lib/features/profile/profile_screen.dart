import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../auth/auth_models.dart';
import '../auth/auth_service.dart';
import '../communities/community_repository.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../statistics/stat_card.dart';
import 'edit_profile_screen.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Who a player is, as a footballer.
///
/// Sprint 2.5 turned this from a form into a record. Opening "me" used to land
/// on a page of text fields — a settings screen wearing the word Profile — and
/// what a player has actually *done* was a chart icon in the corner. The two
/// have swapped: this is the career, and the fields are behind Edit profile.
///
/// **Everything on it is read-only, and that is the design rather than an
/// omission.** `OP-1` makes the rating system-managed and every counter is a
/// consequence of a recorded result, so there is no client write path for any
/// figure here and no control that could offer one. The only editable things a
/// player has are on the other screen.
///
/// No new data layer. The three reads behind it already existed for other
/// screens — the profile, the career counters, and the player's communities —
/// and this is a third reader rather than a third path to them.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.profileRepository,
    this.resultRepository,
    this.communityRepository,
    this.authService,
  });

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ProfileRepository? profileRepository;
  final ResultRepository? resultRepository;
  final CommunityRepository? communityRepository;
  final AuthService? authService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// What one build of the screen needs, read in one pass.
typedef _ProfileView = ({
  PlayerProfile profile,
  PlayerStatistics statistics,
  int communities,
});

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _profiles =
      widget.profileRepository ?? ProfileRepository();
  late final ResultRepository _results =
      widget.resultRepository ?? ResultRepository();
  late final CommunityRepository _communities =
      widget.communityRepository ?? CommunityRepository();
  late final AuthService _auth = widget.authService ?? AuthService();

  late Future<_ProfileView> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileView> _load() async {
    final userId = _auth.currentUserId;
    // A record is somebody's, so without a session there is no row to name.
    if (userId == null) throw const AuthenticationFailure();

    final results = await Future.wait([
      _profiles.fetchMyProfile(),
      _results.fetchStatistics(userId),
      _communities.fetchMyCommunities(),
    ]);

    return (
      profile: results[0] as PlayerProfile,
      statistics: results[1] as PlayerStatistics,
      communities: (results[2] as List).length,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  /// The edit form, and a reload when it closes: a saved name or a new picture
  /// is on this screen too, and the header caches the profile for the session.
  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.profileTitle)),
      body: FutureBuilder<_ProfileView>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _ProfileSkeleton();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 32,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: Gap.md),
                    Text(l10n.loadFailed, textAlign: TextAlign.center),
                    const SizedBox(height: Gap.lg),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l10n.retryButton),
                    ),
                  ],
                ),
              ),
            );
          }

          final view = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                _Identity(profile: view.profile, onEdit: _openEdit),
                _RatingPanel(rating: view.statistics.currentRating),
                _Counters(
                  statistics: view.statistics,
                  communities: view.communities,
                ),
                if (view.statistics.matchesPlayed == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kPageMargin,
                      Gap.lg,
                      kPageMargin,
                      0,
                    ),
                    child: Text(
                      l10n.statNoMatchesYet,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPageMargin,
                    Gap.xl,
                    kPageMargin,
                    0,
                  ),
                  child: Text(
                    l10n.statCareerNote,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPageMargin,
                    Gap.xl,
                    kPageMargin,
                    0,
                  ),
                  // The second place logout lives, the header menu being the
                  // first. It stays on the record rather than moving to the
                  // form: signing out is something a person does, not something
                  // they edit.
                  child: OutlinedButton.icon(
                    onPressed: () => logOut(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(l10n.logoutLabel),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(kButtonHeight),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The player: their face, their name, and the way to change either.
///
/// The age used to sit here and no longer does. A header is the footballing
/// identity — who this is, and what they are rated — and a date arithmetic
/// result was the least interesting thing on it. It is on the edit form now,
/// beside the date of birth it is derived from.
class _Identity extends StatelessWidget {
  const _Identity({required this.profile, required this.onEdit});

  final PlayerProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.lg,
        kPageMargin,
        Gap.sm,
      ),
      child: Column(
        children: [
          UserAvatar(profile: profile, radius: 44),
          const SizedBox(height: Gap.md),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            _positionLabel(l10n, profile.primaryPosition),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: Gap.lg),
          FilledButton.tonalIcon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l10n.editProfileAction),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(kButtonHeight),
            ),
          ),
        ],
      ),
    );
  }

  String _positionLabel(AppLocalizations l10n, PlayerPosition position) =>
      switch (position) {
        PlayerPosition.gk => l10n.positionGk,
        PlayerPosition.def => l10n.positionDef,
        PlayerPosition.mid => l10n.positionMid,
        PlayerPosition.fwd => l10n.positionFwd,
      };
}

/// The Global Rating, given the prominence it has in the product.
///
/// Shown to one decimal place because that is `OP-1`'s presentation rule. The
/// stored value carries two — the engine moves a rating by 0.05 for a goal, and
/// a scale that could not hold that would make corrections irreversible — so the
/// second decimal is real and deliberately not shown here.
class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.lg,
        kPageMargin,
        Gap.xs,
      ),
      padding: const EdgeInsets.symmetric(vertical: Gap.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.primaryContainer, 0.8)!,
          ],
        ),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        children: [
          Icon(Icons.military_tech, size: 26, color: scheme.onPrimary),
          const SizedBox(height: Gap.xs),
          Text(
            rating.toStringAsFixed(1),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onPrimary,
            ),
          ),
          Text(
            l10n.statCurrentRating,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// The career counters, in the order the Product Owner asked for them.
class _Counters extends StatelessWidget {
  const _Counters({required this.statistics, required this.communities});

  final PlayerStatistics statistics;
  final int communities;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPageMargin - 4),
      child: Column(
        children: [
          _Row(children: [
            StatCard(
              icon: Icons.sports_soccer,
              label: l10n.statMatchesPlayed,
              value: statistics.matchesPlayed,
            ),
            StatCard(
              icon: Icons.emoji_events,
              label: l10n.statWins,
              value: statistics.wins,
            ),
          ]),
          _Row(children: [
            StatCard(
              icon: Icons.remove,
              label: l10n.statDraws,
              value: statistics.draws,
            ),
            StatCard(
              icon: Icons.trending_down,
              label: l10n.statLosses,
              value: statistics.losses,
            ),
          ]),
          _Row(children: [
            StatCard(
              icon: Icons.scoreboard,
              label: l10n.statGoals,
              value: statistics.goals,
            ),
            StatCard(
              icon: Icons.star,
              label: l10n.statMvpCount,
              value: statistics.mvpCount,
            ),
          ]),
          _Row(children: [
            StatCard(
              icon: Icons.groups,
              label: l10n.communitiesTitle,
              value: communities,
            ),
          ]),
        ],
      ),
    );
  }
}

/// A row of equal-height cards.
///
/// `IntrinsicHeight` is what gives the stretch a height to work from — inside a
/// ListView the row's vertical extent is otherwise unbounded, and stretching
/// against that is an error rather than a layout.
///
/// A row of one is left half-width rather than stretched: a lone card spanning
/// the page would read as a heading rather than as the sixth of six figures.
class _Row extends StatelessWidget {
  const _Row({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) Expanded(child: child),
          if (children.length == 1) const Spacer(),
        ],
      ),
    );
  }
}

/// The shape of the record, before it arrives.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonFade(
      child: Padding(
        padding: EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
        child: Column(
          children: [
            Skeleton(width: 88, height: 88, radius: Radii.pill),
            SizedBox(height: Gap.md),
            Skeleton(width: 160, height: 20),
            SizedBox(height: Gap.sm),
            Skeleton(width: 90, height: 12),
            SizedBox(height: Gap.lg),
            Skeleton.expand(height: kButtonHeight),
            SizedBox(height: Gap.lg),
            Skeleton.expand(height: 108, radius: Radii.md),
            SizedBox(height: Gap.md),
            Skeleton.expand(height: 96, radius: Radii.md),
            SizedBox(height: Gap.sm),
            Skeleton.expand(height: 96, radius: Radii.md),
          ],
        ),
      ),
    );
  }
}
