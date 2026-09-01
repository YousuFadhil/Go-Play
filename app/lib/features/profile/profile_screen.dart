import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/states.dart';
import '../auth/auth_models.dart';
import '../auth/auth_service.dart';
import '../communities/community_repository.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../settings/settings_screen.dart';
import '../statistics/player_statistics_screen.dart';
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
    this.userId,
    this.profileRepository,
    this.resultRepository,
    this.communityRepository,
    this.authService,
  });

  /// Whose profile this is. Null is the signed-in player's own, which is what
  /// every existing caller means; a member tapped in a community roster passes
  /// their id and gets the same screen, read-only and without the account's own
  /// controls on it.
  final String? userId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ProfileRepository? profileRepository;
  final ResultRepository? resultRepository;
  final CommunityRepository? communityRepository;
  final AuthService? authService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// What one build of the screen needs, read in one pass.
///
/// One shape for both readings of the screen. The player's own profile fills in
/// [communities] and offers the account controls; somebody else's does neither,
/// and carries only what the server was willing to send.
class _ProfileView {
  const _ProfileView({
    required this.fullName,
    required this.primaryPosition,
    required this.statistics,
    required this.isSelf,
    this.avatarUrl,
    this.age,
    this.communities,
  });

  final String fullName;
  final PlayerPosition primaryPosition;
  final PlayerStatistics statistics;

  /// Whether this is the player looking at themselves. It decides which
  /// controls are on the screen and nothing about what may be read — the server
  /// has already decided that.
  final bool isSelf;

  final String? avatarUrl;

  /// Completed years, derived from the date of birth and never stored
  /// (`KB-C7`). Null when the player has none recorded, and null when they have
  /// hidden their age — the date does not leave the database in that case, so
  /// there is nothing here to hide.
  final int? age;

  /// How many communities the player belongs to. Their own figure only: how many
  /// clubs somebody else is in is not part of the profile they publish.
  final int? communities;
}

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

  /// Whether this build is the player's own record or somebody else's.
  bool get _isOwnProfile => widget.userId == null;

  Future<_ProfileView> _load() =>
      _isOwnProfile ? _loadOwnProfile() : _loadPlayerProfile(widget.userId!);

  Future<_ProfileView> _loadOwnProfile() async {
    final userId = _auth.currentUserId;
    // A record is somebody's, so without a session there is no row to name.
    if (userId == null) throw const AuthenticationFailure();

    final results = await Future.wait([
      _profiles.fetchMyProfile(),
      _results.fetchStatistics(userId),
      _communities.fetchMyCommunities(),
    ]);

    final profile = results[0] as PlayerProfile;
    return _ProfileView(
      fullName: profile.fullName,
      primaryPosition: profile.primaryPosition,
      avatarUrl: profile.avatarUrl,
      // The owner always sees their own age, whatever they have set for
      // everybody else. This is their own row, read through their own session.
      age: profile.age,
      statistics: results[1] as PlayerStatistics,
      communities: (results[2] as List).length,
      isSelf: true,
    );
  }

  /// Another player's profile, in one read.
  ///
  /// One call and not three: the server sends the football profile and its
  /// counters together (`player_profile`, migrations `0043` and `0056`), so
  /// asking separately would be asking the same question twice.
  ///
  /// [_ProfileView.age] is left null, and there is nothing to put in it: since
  /// `0056` a date of birth does not leave the database for anybody but its
  /// owner, so another player's record has no age to show. The owner's own
  /// build still has one — see [_loadOwnProfile].
  Future<_ProfileView> _loadPlayerProfile(String userId) async {
    final player = await _profiles.fetchPlayerProfile(userId);
    return _ProfileView(
      fullName: player.fullName,
      primaryPosition: player.primaryPosition,
      avatarUrl: player.avatarUrl,
      statistics: player.statistics,
      isSelf: player.isSelf,
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
      appBar: AppHeader(
        title:
            Text(_isOwnProfile ? l10n.profileTitle : l10n.playerProfileTitle),
      ),
      body: FutureBuilder<_ProfileView>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _ProfileSkeleton();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            // A profile the player keeps to their community is not a failed
            // read, and reporting it as one would offer a retry that is certain
            // to fail again. It is the one refusal this screen words for itself.
            final error = snapshot.error;
            if (error is Failure &&
                error.reason == FailureReason.profileNotVisible) {
              return EmptyState(
                icon: Icons.lock_outline,
                title: l10n.profileNotVisibleTitle,
                message: l10n.errProfileNotVisible,
              );
            }
            return ErrorState(onRetry: _refresh);
          }

          final view = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                _Identity(
                  view: view,
                  // Editing is the account's own action, so it is offered on
                  // the player's own record and nowhere else.
                  onEdit: _isOwnProfile ? _openEdit : null,
                ),
                _RatingPanel(rating: view.statistics.currentRating),
                _Counters(
                  statistics: view.statistics,
                  communities: view.communities,
                ),
                if (view.statistics.matchesPlayed == 0)
                  FootNote(
                    l10n.statNoMatchesYet,
                    textAlign: TextAlign.center,
                    padding: const EdgeInsets.fromLTRB(
                      kPageMargin,
                      Gap.lg,
                      kPageMargin,
                      0,
                    ),
                  ),
                FootNote(
                  l10n.statCareerNote,
                  textAlign: TextAlign.center,
                  padding: const EdgeInsets.fromLTRB(
                    kPageMargin,
                    Gap.xl,
                    kPageMargin,
                    Gap.sm,
                  ),
                ),
                // The way into the same record by period, and the only way
                // there is. The counters above are the career; this is that
                // career broken into weeks and months — and the screen it opens
                // is where a card of it can be shared from.
                //
                // Its own card rather than the one below: settings and logout
                // are things done to the account, and this is more of the
                // record it sits under.
                //
                // Offered on the player's own profile only, because the screen
                // it opens is the signed-in player's — it resolves whose record
                // to read from the session, exactly as this screen does when
                // `userId` is null.
                if (_isOwnProfile)
                  SectionCard(
                    padding: EdgeInsets.zero,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.insights_outlined),
                        title: Text(l10n.playerStatisticsTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            // No `userId`: null is the signed-in player, which
                            // is what this branch already knows it is showing.
                            // Passing one read here would be a second answer to
                            // a question the session already settles.
                            builder: (_) => const PlayerStatisticsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                // The account's own actions, apart from the record above them.
                // The second place logout lives, the header menu being the
                // first. It stays on the record rather than moving to the
                // form: signing out is something a person does, not something
                // they edit.
                //
                // Somebody else's record carries none of it: settings and
                // logout belong to the account, not to the profile.
                if (_isOwnProfile)
                  SectionCard(
                    padding: EdgeInsets.zero,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: Text(l10n.settingsTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          l10n.logoutLabel,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onTap: () => logOut(context),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The player: their face, their name, their age, and — on their own record —
/// the way to change any of it.
///
/// The age is back on the header, and for a reason that is not decoration: it is
/// the thing the age-visibility setting is about, and a setting whose effect is
/// on a form nobody else can open would not be a setting about other people at
/// all. It is shown when there is one to show, which for another player means
/// the server sent a date of birth — a hidden age arrives as no date and
/// therefore as no line, rather than as a line this widget declines to draw.
class _Identity extends StatelessWidget {
  const _Identity({required this.view, this.onEdit});

  final _ProfileView view;

  /// Null on somebody else's record: there is nothing to edit there.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final age = view.age;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.lg,
        kPageMargin,
        Gap.sm,
      ),
      child: Column(
        children: [
          UserAvatar(
            avatarUrl: view.avatarUrl,
            fullName: view.fullName,
            radius: 44,
          ),
          const SizedBox(height: Gap.md),
          Text(
            view.fullName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            _positionLabel(l10n, view.primaryPosition),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          if (age != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              l10n.ageYears(age),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (onEdit != null) ...[
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

  /// Null on somebody else's record. How many clubs a player is in is not part
  /// of the profile they publish, so the card is absent rather than empty.
  final int? communities;

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
          if (communities != null)
            _Row(children: [
              StatCard(
                icon: Icons.groups,
                label: l10n.communitiesTitle,
                value: communities!,
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
