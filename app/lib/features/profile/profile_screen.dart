import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../analytics/analytics_models.dart';
import '../auth/auth_models.dart';
import '../auth/auth_service.dart';
import '../communities/community_repository.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../settings/settings_screen.dart';
import '../sharing/public_link.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import '../statistics/player_statistics_screen.dart';
import '../statistics/stat_card.dart';
import 'edit_profile_screen.dart';
import 'player_identity.dart';
import 'player_profile_share_card.dart';
import 'player_record_models.dart';
import 'player_record_repository.dart';
import 'profile_models.dart';
import 'profile_record_sections.dart';
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
    this.asVisitor = false,
    this.profileRepository,
    this.resultRepository,
    this.communityRepository,
    this.playerRecordRepository,
    this.authService,
    this.renderer,
    this.shareService,
  });

  /// Whose profile this is. Null is the signed-in player's own, which is what
  /// every existing caller means; a member tapped in a community roster passes
  /// their id and gets the same screen, read-only and without the account's own
  /// controls on it.
  final String? userId;

  /// Whether this build is for a reader with no account.
  ///
  /// **Stated by the caller, not inferred from the session, and deliberately.**
  /// There is exactly one way a signed-out reader reaches this screen — the
  /// auth gate rendering a `/player/{id}` link as what the app opens on — and
  /// that caller already knows there is no session, because deciding that is
  /// its whole job. Asking a second time here would put an identity read
  /// inside a widget that is pushed from a dozen places which have no doubt
  /// about it, and would make "which contracts may I call" a question the
  /// screen answers rather than one it is told.
  ///
  /// True reads the narrow public contracts; false reads the authenticated
  /// ones. Nothing falls back from one to the other.
  final bool asVisitor;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ProfileRepository? profileRepository;
  final ResultRepository? resultRepository;
  final CommunityRepository? communityRepository;
  final PlayerRecordRepository? playerRecordRepository;
  final AuthService? authService;

  /// How a share card is composed and handed over. Supplied only by tests;
  /// left null the screen uses the engine's own, exactly as the four screens
  /// that already compose a card do.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

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
    required this.userId,
    required this.fullName,
    required this.primaryPosition,
    required this.statistics,
    required this.isSelf,
    required this.form,
    this.avatarUrl,
    this.age,
    this.communities,
    this.highlight,
  });

  /// Whose record this is. Held because a share needs a public link, and a
  /// public link needs an id — the screen's own `widget.userId` is null on the
  /// player's own profile, which is exactly the case that still has to produce
  /// a shareable address.
  final String userId;

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

  /// The last five completed matches, newest first. Empty is ordinary — a
  /// player who has played none — and never an error.
  final RecentForm form;

  /// The one achievement worth showing, or null when there is none. Null draws
  /// no section at all rather than an empty one.
  final RecentHighlight? highlight;
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _profiles =
      widget.profileRepository ?? ProfileRepository();
  late final ResultRepository _results =
      widget.resultRepository ?? ResultRepository();
  late final CommunityRepository _communities =
      widget.communityRepository ?? CommunityRepository();
  late final AuthService _auth = widget.authService ?? AuthService();
  late final PlayerRecordRepository _records =
      widget.playerRecordRepository ?? PlayerRecordRepository();

  late Future<_ProfileView> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Whether this build is the player's own record or somebody else's.
  bool get _isOwnProfile => widget.userId == null;

  /// Which of the three readings of this screen is being built.
  ///
  /// **The session decides, and the caller states it** — see
  /// [ProfileScreen.asVisitor]. A visitor may call only the public contracts;
  /// a signed-in reader never calls those, because the richer read is theirs
  /// by right. There is no fallback between the two: a failed authenticated
  /// read is a failure, not a quietly narrower profile the reader could not
  /// tell apart from a real one.
  Future<_ProfileView> _load() {
    if (widget.asVisitor) return _loadPublicProfile();
    return _isOwnProfile
        ? _loadOwnProfile()
        : _loadPlayerProfile(widget.userId!);
  }

  /// A player's record as a visitor with no account sees it.
  ///
  /// Reached only through a public link: signed out, the app opens on Discover
  /// and there is no other way to a profile from there. A null id would be a
  /// request for "my profile" with nobody signed in, which is the one thing
  /// this reading cannot mean.
  Future<_ProfileView> _loadPublicProfile() async {
    final userId = widget.userId;
    if (userId == null) throw const AuthenticationFailure();

    final record = await _records.publicRecord(userId);
    // No public profile at that id: the player does not exist, or is not
    // active. The server answers both the same way on purpose, and so does
    // this — a guessed id learns nothing either way.
    if (record == null) throw const NotFoundFailure();

    return _ProfileView(
      userId: userId,
      fullName: record.profile.fullName,
      primaryPosition: record.profile.primaryPosition,
      avatarUrl: record.profile.avatarUrl,
      statistics: record.profile.statistics,
      form: record.form,
      highlight: record.highlight,
      isSelf: false,
    );
  }

  Future<_ProfileView> _loadOwnProfile() async {
    final userId = _auth.currentUserId;
    // A record is somebody's, so without a session there is no row to name.
    if (userId == null) throw const AuthenticationFailure();

    // Issued together, as the three already were: the record reads are
    // independent of the profile reads and of each other, so adding them costs
    // the screen no extra wait.
    final results = await Future.wait([
      _profiles.fetchMyProfile(),
      _results.fetchStatistics(userId),
      _communities.fetchMyCommunities(),
      _records.recentForm(userId),
      _records.recentHighlight(userId),
    ]);

    final profile = results[0] as PlayerProfile;
    return _ProfileView(
      userId: userId,
      fullName: profile.fullName,
      primaryPosition: profile.primaryPosition,
      avatarUrl: profile.avatarUrl,
      // The owner always sees their own age, whatever they have set for
      // everybody else. This is their own row, read through their own session.
      age: profile.age,
      statistics: results[1] as PlayerStatistics,
      communities: (results[2] as List).length,
      form: results[3] as RecentForm,
      highlight: results[4] as RecentHighlight?,
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
    final results = await Future.wait([
      _profiles.fetchPlayerProfile(userId),
      _records.recentForm(userId),
      _records.recentHighlight(userId),
    ]);
    final player = results[0] as PlayerProfileView;
    return _ProfileView(
      userId: userId,
      fullName: player.fullName,
      primaryPosition: player.primaryPosition,
      avatarUrl: player.avatarUrl,
      statistics: player.statistics,
      form: results[1] as RecentForm,
      highlight: results[2] as RecentHighlight?,
      isSelf: player.isSelf,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  /// The profile, as a card.
  ///
  /// **What the reader may see is what they may send.** The card is composed
  /// from `view` — the record already on screen, read through whatever contract
  /// the reader's session entitled them to — so a public reading produces a
  /// public card and nothing on it can exceed what the server was willing to
  /// show. Nothing is fetched here; a share cannot widen a disclosure because
  /// it never asks a second question.
  ///
  /// The date of birth is not on it for the same structural reason it is not on
  /// the screen: neither `PlayerProfileView` nor `PublicPlayerRecord` carries
  /// one, so there is nothing to leave out.
  Future<void> _share(_ProfileView view) async {
    final l10n = context.l10n;

    // The face is fetched before the card is composed, not while it is: the
    // engine gives a template two frames to settle, which is ample for layout
    // and nowhere near enough for a network image.
    final avatarUrl = view.avatarUrl;
    if (avatarUrl != null) {
      await precacheShareCardFaces(context, [avatarUrl]);
    }
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (_) => PlayerProfileShareCard(
        data: PlayerProfileCardData(
          fullName: view.fullName,
          avatarUrl: view.avatarUrl,
          primaryPosition: view.primaryPosition,
          rating: view.statistics.currentRating,
          matchesPlayed: view.statistics.matchesPlayed,
          goals: view.statistics.goals,
          mvpCount: view.statistics.mvpCount,
          form: view.form,
        ),
      ),
      message: ShareMessage(
        // Their own profile reads as theirs; somebody else's is named. Both
        // are localized here, where the screen knows which reading it is —
        // the engine is handed the finished sentence.
        text: view.isSelf
            ? l10n.shareTextMyProfile
            : l10n.shareTextPlayerProfile(view.fullName),
        // The public address of this player. It opens the same public profile
        // for whoever receives it, which is narrower than what a signed-in
        // reader sees and never wider.
        url: PublicLink.format(PublicLinkKind.player, view.userId),
      ),
      shareType: ShareType.playerProfile,
      source: ShareSource.playerProfile,
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
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

    return FutureBuilder<_ProfileView>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppHeader(
              title: Text(
                _isOwnProfile ? l10n.profileTitle : l10n.playerProfileTitle,
              ),
            ),
            body: const _ProfileSkeleton(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          // A profile the player keeps to their community is not a failed
          // read, and reporting it as one would offer a retry that is certain
          // to fail again. It is the one refusal this screen words for itself.
          final error = snapshot.error;
          if (error is Failure &&
              error.reason == FailureReason.profileNotVisible) {
            return Scaffold(
              appBar: AppHeader(
                title: Text(
                  _isOwnProfile ? l10n.profileTitle : l10n.playerProfileTitle,
                ),
              ),
              body: EmptyState(
                icon: Icons.lock_outline,
                title: l10n.profileNotVisibleTitle,
                message: l10n.errProfileNotVisible,
              ),
            );
          }
          return Scaffold(
            appBar: AppHeader(
              title: Text(
                _isOwnProfile ? l10n.profileTitle : l10n.playerProfileTitle,
              ),
            ),
            body: ErrorState(onRetry: _refresh),
          );
        }

        final view = snapshot.data!;
        return Scaffold(
          backgroundColor: GoColors.bgHero,
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: ClubHero(
                  bar: ClubHeroBar(
                    title: _isOwnProfile
                        ? l10n.profileTitle
                        : l10n.playerProfileTitle,
                    // A back button where there is somewhere to go back to,
                    // and none where there is not.
                    //
                    // This screen is reached two ways: pushed — from a name on
                    // a pitch, a roster, a leaderboard — and opened from the
                    // shell's own identity menu, where it is the root of its
                    // stack. `ClubHeroBar` draws the affordance only when it
                    // is given a callback, so asking the Navigator is the
                    // whole of the rule. An arrow that pops nothing is worse
                    // than no arrow: it looks like a way out and is not one.
                    onBack: Navigator.of(context).canPop()
                        ? () => Navigator.of(context).pop()
                        : null,
                    actions: [
                      // Offered on both readings of the screen, and that is
                      // the approved rule rather than a convenience: a
                      // profile the reader is allowed to see is a profile
                      // they are allowed to send. It is worded for the
                      // reading — their own record, or this player's.
                      IconButton(
                        tooltip: view.isSelf
                            ? l10n.shareMyProfileAction
                            : l10n.sharePlayerProfileAction,
                        color: Colors.white,
                        iconSize: IconSize.bar,
                        icon: const Icon(Icons.ios_share),
                        onPressed: () => _share(view),
                      ),
                      if (_isOwnProfile)
                        IconButton(
                          tooltip: l10n.editProfileAction,
                          color: Colors.white,
                          iconSize: IconSize.bar,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _openEdit,
                        ),
                    ],
                  ),
                  identity: _HeroIdentity(view: view),
                ),
              ),
              Expanded(
                child: ClubSheet(
                  child: RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        0,
                        Gap.sm,
                        0,
                        Gap.xxl,
                      ),
                      children: [
                        _Counters(
                          statistics: view.statistics,
                          communities: view.communities,
                        ),
                        if (view.statistics.matchesPlayed == 0)
                          FootNote(
                            l10n.statNoMatchesYet,
                            textAlign: TextAlign.center,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              kPageMargin,
                              Gap.lg,
                              kPageMargin,
                              0,
                            ),
                          ),
                        FootNote(
                          l10n.statCareerNote,
                          textAlign: TextAlign.center,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            kPageMargin,
                            Gap.xl,
                            kPageMargin,
                            Gap.sm,
                          ),
                        ),
                        // The approved order, and the reason it is this one:
                        // the career above is what a player has done in
                        // total, Recent Form is what they are doing now, and
                        // the highlight is the single best thing in it. Each
                        // section is narrower than the one above it.
                        RecentFormSection(form: view.form),
                        // No section at all when there is nothing eligible.
                        // An empty achievement card would be a placeholder
                        // for something most players will never have.
                        if (view.highlight != null)
                          RecentHighlightSection(
                            highlight: view.highlight!,
                          ),
                        // The way into the same record by period, and the only
                        // way there is. The counters above are the career; this
                        // is that career broken into weeks and months — and the
                        // screen it opens is where a card of it can be shared.
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
                                    builder: (_) =>
                                        const PlayerStatisticsScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        // Settings and logout belong to the account, not to a
                        // profile another player has opened.
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
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity({required this.view});

  final _ProfileView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        UserAvatar(
          avatarUrl: view.avatarUrl,
          fullName: view.fullName,
          radius: 31,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                view.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm - 2,
                runSpacing: Gap.xs,
                children: [
                  _HeroChip(label: positionLabel(l10n, view.primaryPosition)),
                  if (view.age != null)
                    _HeroChip(label: l10n.ageYears(view.age!)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: Gap.sm),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                view.statistics.currentRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: Gap.sm - 2),
              Text(
                l10n.statCurrentRating,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.8,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Gap.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
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
