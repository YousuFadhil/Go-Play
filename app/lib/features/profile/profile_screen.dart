import 'package:flutter/material.dart';

import '../../core/app_header.dart' show logOut;
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
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../settings/settings_screen.dart';
import '../sharing/public_link.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import '../statistics/player_statistics_screen.dart';
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
/// The Package 5 direction gives it the approved composition: the identity
/// centred in the hero, the career as one grid of figures, then Recent Form,
/// then the one Recent Highlight, then what the reader can do — share it, see
/// it as the public sees it, or, with no account, sign in.
///
/// **No [AppHeader] anywhere on it, and that is load-bearing rather than
/// stylistic.** That bar always carries [CurrentUserMenu], which reads the
/// signed-in player's own profile the moment it is built — so a visitor with no
/// session opening a public link would have asked an authenticated contract a
/// question it must refuse. The hero's own bar carries no identity, which is
/// what makes a guest's page a guest's page.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.userId,
    this.asVisitor = false,
    this.profileRepository,
    this.resultRepository,
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
  ///
  /// It is also what the player's own "View as public" opens, with their own
  /// id: the preview is the public page itself, read through the public
  /// contracts, rather than a guess at what it would contain.
  final bool asVisitor;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ProfileRepository? profileRepository;
  final ResultRepository? resultRepository;
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
    this.secondaryPosition,
    this.avatarUrl,
    this.highlight,
  });

  /// Whose record this is. Held because a share needs a public link, and a
  /// public link needs an id — the screen's own `widget.userId` is null on the
  /// player's own profile, which is exactly the case that still has to produce
  /// a shareable address.
  final String userId;

  final String fullName;
  final PlayerPosition primaryPosition;

  /// Where else they play. Null for a player who has named one position, which
  /// is the ordinary case and draws one chip instead of two.
  final PlayerPosition? secondaryPosition;

  final PlayerStatistics statistics;

  /// Whether this is the player looking at themselves. It decides which
  /// controls are on the screen and nothing about what may be read — the server
  /// has already decided that.
  final bool isSelf;

  final String? avatarUrl;

  /// The last five completed matches, newest first. Empty is ordinary — a
  /// player who has played none — and never an error.
  final RecentForm form;

  /// The one achievement worth showing, or null when there is none. Null draws
  /// no section at all rather than an empty one.
  final RecentHighlight? highlight;
}

/// The account's own actions, which only its owner is offered.
enum _ProfileAction { statistics, settings, logout }

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _profiles =
      widget.profileRepository ?? ProfileRepository();
  late final ResultRepository _results =
      widget.resultRepository ?? ResultRepository();
  late final AuthService _auth = widget.authService ?? AuthService();
  late final PlayerRecordRepository _records =
      widget.playerRecordRepository ?? PlayerRecordRepository();

  late Future<_ProfileView> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Whether this build is the player's own record, with the account's controls
  /// on it.
  ///
  /// A visitor is never looking at their own record, however the ids fall: the
  /// player's own "View as public" passes their id *and* [ProfileScreen
  /// .asVisitor], and the whole point of that preview is that it does not offer
  /// what the public is not offered.
  bool get _isOwnProfile => widget.userId == null && !widget.asVisitor;

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
  /// Reached two ways: a `/player/{id}` link opened without a session, and a
  /// player previewing their own public page. A null id would be a request for
  /// "my profile" with nobody named, which is the one thing this reading cannot
  /// mean.
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
      secondaryPosition: record.profile.secondaryPosition,
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

    // Issued together: the record reads are independent of the profile reads
    // and of each other, so asking for all four costs the screen no extra wait.
    //
    // The communities read is gone with the cell that showed it: the approved
    // career grid is the seven football figures and nothing else, and how many
    // clubs a player is in is what the Communities tab is.
    final results = await Future.wait([
      _profiles.fetchMyProfile(),
      _results.fetchStatistics(userId),
      _records.recentForm(userId),
      _records.recentHighlight(userId),
    ]);

    final profile = results[0] as PlayerProfile;
    return _ProfileView(
      userId: userId,
      fullName: profile.fullName,
      primaryPosition: profile.primaryPosition,
      secondaryPosition: profile.secondaryPosition,
      avatarUrl: profile.avatarUrl,
      statistics: results[1] as PlayerStatistics,
      form: results[2] as RecentForm,
      highlight: results[3] as RecentHighlight?,
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
      secondaryPosition: player.secondaryPosition,
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
          wins: view.statistics.wins,
          draws: view.statistics.draws,
          losses: view.statistics.losses,
          form: view.form,
          highlight: view.highlight,
          publicUrl: PublicLink.format(PublicLinkKind.player, view.userId),
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

  /// The player's own record, read the way a stranger reads it.
  ///
  /// The same screen with [ProfileScreen.asVisitor] set, so the preview is the
  /// public page rather than a rehearsal of it: it calls the public contracts
  /// and shows exactly what they return.
  void _openPublicPreview(_ProfileView view) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: view.userId, asVisitor: true),
      ),
    );
  }

  void _openStatistics() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerStatisticsScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _isOwnProfile ? l10n.profileTitle : l10n.playerProfileTitle;

    return FutureBuilder<_ProfileView>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _Shell(title: title, child: const _ProfileSkeleton());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          // A profile the player keeps to their community is not a failed
          // read, and reporting it as one would offer a retry that is certain
          // to fail again. It is the one refusal this screen words for itself.
          final error = snapshot.error;
          if (error is Failure &&
              error.reason == FailureReason.profileNotVisible) {
            return _Shell(
              title: title,
              child: EmptyState(
                icon: Icons.lock_outline,
                title: l10n.profileNotVisibleTitle,
                message: l10n.errProfileNotVisible,
              ),
            );
          }
          return _Shell(title: title, child: ErrorState(onRetry: _refresh));
        }

        final view = snapshot.data!;
        return Scaffold(
          backgroundColor: GoColors.bgHero,
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: ClubHero(
                  // The approved Package 5 hero: the player against a ground
                  // rather than against a colour. Drawn, not photographed —
                  // see [StadiumBackdrop].
                  stadium: true,
                  bar: ClubHeroBar(
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
                      // On the player's own record the share is the button
                      // under the figures, where the approved design puts it;
                      // on anybody else's it is the bar, because that page has
                      // no action row of its own. Either way a profile the
                      // reader may see is a profile they may send.
                      if (!_isOwnProfile)
                        IconButton(
                          tooltip: l10n.sharePlayerProfileAction,
                          color: Colors.white,
                          iconSize: IconSize.bar,
                          icon: const Icon(Icons.ios_share),
                          onPressed: () => _share(view),
                        ),
                      if (_isOwnProfile)
                        _AccountMenu(
                          onSelected: (action) => switch (action) {
                            _ProfileAction.statistics => _openStatistics(),
                            _ProfileAction.settings => _openSettings(),
                            _ProfileAction.logout => logOut(context),
                          },
                        ),
                    ],
                  ),
                  identity: _HeroIdentity(
                    view: view,
                    onEdit: _isOwnProfile ? _openEdit : null,
                  ),
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
                        Gap.lg,
                        0,
                        Layout.listBottom,
                      ),
                      children: [
                        _CareerGrid(statistics: view.statistics),
                        if (view.statistics.matchesPlayed == 0)
                          FootNote(
                            l10n.statNoMatchesYet,
                            textAlign: TextAlign.center,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              kPageMargin,
                              Gap.md,
                              kPageMargin,
                              0,
                            ),
                          ),
                        // The approved order, and the reason it is this one:
                        // the career above is what a player has done in
                        // total, Recent Form is what they are doing now, and
                        // the highlight is the single best thing in it. Each
                        // section is narrower than the one above it.
                        RecentFormSection(
                          form: view.form,
                          // The way into the same record by period. Offered
                          // only where it leads somewhere: the statistics
                          // screen is the signed-in player's own.
                          onViewAll: _isOwnProfile ? _openStatistics : null,
                        ),
                        // No section at all when there is nothing eligible.
                        // An empty achievement card would be a placeholder
                        // for something most players will never have.
                        if (view.highlight != null)
                          RecentHighlightSection(highlight: view.highlight!),
                        if (_isOwnProfile)
                          _OwnerActions(
                            onShare: () => _share(view),
                            onViewAsPublic: () => _openPublicPreview(view),
                          ),
                        if (widget.asVisitor)
                          _VisitorActions(
                            onLogin: () => _push(const LoginScreen()),
                            onRegister: () => _push(const RegisterScreen()),
                          ),
                        FootNote(
                          l10n.statCareerNote,
                          textAlign: TextAlign.center,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            kPageMargin,
                            Layout.sectionAbove,
                            kPageMargin,
                            0,
                          ),
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

/// The screen while it is still a shape, and when it could not be read.
///
/// A bar with no identity on it, on the same green the loaded screen opens
/// with. **Not [AppHeader]:** that bar mounts [CurrentUserMenu], which reads
/// `my_profile` as soon as it is built — so a guest opening a public link would
/// have called an authenticated contract before the page had drawn anything.
class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ClubHeroBar(
              title: title,
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
          ),
          Expanded(child: ClubSheet(child: child)),
        ],
      ),
    );
  }
}

/// The account's own actions, behind one glyph.
///
/// The three the Product Owner asked this screen to carry — the statistics, the
/// settings and the way out — gathered under the approved design's overflow
/// rather than listed under the record. They are the account's, and the page
/// above them is the football.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.onSelected});

  final ValueChanged<_ProfileAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_ProfileAction>(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_horiz),
      iconSize: IconSize.bar,
      color: GoColors.surfaceCard,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ProfileAction.statistics,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insights_outlined),
            title: Text(l10n.playerStatisticsTitle),
          ),
        ),
        PopupMenuItem(
          value: _ProfileAction.settings,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.settingsTitle),
          ),
        ),
        PopupMenuItem(
          value: _ProfileAction.logout,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(
              l10n.logoutLabel,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
      ],
    );
  }
}

/// The player: their face, their name and where they play, centred on the hero.
///
/// The age is here for a reason that is not decoration: it is the thing the
/// age-visibility setting is about, and a setting whose effect is on a form
/// nobody else can open would not be a setting about other people at all. It is
/// shown when there is one to show — a hidden age arrives as no date and
/// therefore as no chip, rather than as a chip this widget declines to draw.
class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity({required this.view, this.onEdit});

  final _ProfileView view;

  /// Null on every reading but the owner's, which is what takes the pencil off
  /// a page nobody may edit.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: Gap.sm),
        Stack(
          clipBehavior: Clip.none,
          children: [
            // The ring is what lifts a face off the hero. White, because the
            // hero is the one green surface a picture is ever set on.
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF041A0D).withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: PlayerAvatar(
                avatarUrl: view.avatarUrl,
                fullName: view.fullName,
                radius: 48,
              ),
            ),
            if (onEdit != null)
              PositionedDirectional(
                bottom: -2,
                end: -2,
                child: Material(
                  color: GoColors.primaryDeep,
                  shape: const CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onEdit,
                    child: Tooltip(
                      message: l10n.editProfileAction,
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(
                          Icons.edit,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        // Two lines at most and then ellipsized: a long name shortens rather
        // than pushing the chips off the hero.
        Text(
          view.fullName,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: Gap.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Gap.sm,
          runSpacing: Gap.sm - 2,
          children: [
            _PositionChip(position: view.primaryPosition),
            if (view.secondaryPosition != null)
              _PositionChip(position: view.secondaryPosition!),
          ],
        ),
      ],
    );
  }
}

/// A position, as its short code and its name.
///
/// The code is the enum's own — GK, DEF, MID, FWD — and is not localized: it is
/// the same three letters on a team sheet in either language, which is why the
/// label beside it carries the translation.
class _PositionChip extends StatelessWidget {
  const _PositionChip({required this.position});

  final PlayerPosition position;

  @override
  Widget build(BuildContext context) => _HeroChip(
        code: position.name.toUpperCase(),
        label: positionLabel(context.l10n, position),
      );
}

/// A white pill on the hero: the chips sit on the green and read off it.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, this.code});

  final String label;

  /// The short marker that opens the pill, where the chip has one.
  final String? code;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsetsDirectional.fromSTEB(
          code == null ? Gap.md : 5,
          5,
          Gap.md,
          5,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (code != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: GoColors.rowTintLight,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  code!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: GoColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: GoColors.onSurface,
              ),
            ),
          ],
        ),
      );
}

/// The career, as one grid of figures.
///
/// **One card and not seven, which is the approved change.** The counters used
/// to be a column of paired cards, so a player's record took most of a screen
/// to say seven numbers. The grid says them in two rows: the result of every
/// match on the first, what the player did in them on the second, with the
/// rating given the emphasis it has everywhere else in the product.
class _CareerGrid extends StatelessWidget {
  const _CareerGrid({required this.statistics});

  final PlayerStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: GoColors.surfaceCard,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: Elevations.card,
        ),
        child: Column(
          children: [
            _GridRow(children: [
              _Cell(
                value: '${statistics.matchesPlayed}',
                label: l10n.shareCardStatMatches,
              ),
              _Cell(
                value: '${statistics.wins}',
                label: l10n.shareCardStatWins,
              ),
              _Cell(
                value: '${statistics.losses}',
                label: l10n.shareCardStatLosses,
              ),
              _Cell(
                value: '${statistics.draws}',
                label: l10n.shareCardStatDraws,
              ),
            ]),
            Container(height: 1, color: GoColors.hairline),
            _GridRow(children: [
              _Cell(
                value: '${statistics.goals}',
                label: l10n.shareCardStatGoals,
              ),
              _Cell(
                value: '${statistics.mvpCount}',
                label: l10n.shareCardStatMvp,
              ),
              _Cell(
                // One decimal place, which is `OP-1`'s presentation rule and
                // what every other surface shows.
                value: statistics.currentRating.toStringAsFixed(1),
                label: l10n.statCurrentRating,
                emphasised: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A row of cells, divided by hairlines.
///
/// `IntrinsicHeight` is what gives a divider a height to take: inside a Column
/// the row's vertical extent is otherwise unbounded, and a full-height line
/// against that is an error rather than a layout.
class _GridRow extends StatelessWidget {
  const _GridRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) ...[
            if (child != children.first)
              Container(width: 1, color: GoColors.hairline),
            Expanded(child: child),
          ],
        ],
      ),
    );
  }
}

/// One figure and what it counts.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.label,
    this.emphasised = false,
  });

  final String value;
  final String label;

  /// The rating, and only the rating. It is the one figure the product gives a
  /// mark of its own, on the leaderboard and on a share card alike.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: Gap.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emphasised)
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: GoColors.warn,
                shape: BoxShape.circle,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 34,
              child: Center(
                child: Text(
                  value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                color: GoColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the owner of a record can do with it.
class _OwnerActions extends StatelessWidget {
  const _OwnerActions({required this.onShare, required this.onViewAsPublic});

  final VoidCallback onShare;
  final VoidCallback onViewAsPublic;

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
          FilledButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share, size: IconSize.action),
            label: Text(l10n.shareMyProfileAction),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(kButtonHeight),
            ),
          ),
          const SizedBox(height: Gap.md),
          // Quieter than the share, because it is the rehearsal rather than
          // the act: the same tint a row carries, with the page's own ink.
          FilledButton.icon(
            onPressed: onViewAsPublic,
            icon: const Icon(Icons.open_in_new, size: IconSize.action),
            label: Text(l10n.viewAsPublicAction),
            style: FilledButton.styleFrom(
              backgroundColor: GoColors.rowTintLight,
              foregroundColor: GoColors.onSurface,
              minimumSize: const Size.fromHeight(kButtonHeight),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a reader with no account is offered, and the only thing this page ever
/// asks them for.
///
/// The two buttons open the app's own auth screens. Nothing here registers
/// anybody, joins anything or reads a contract a guest may not call — a public
/// profile is a page to read, and this is the way off it.
class _VisitorActions extends StatelessWidget {
  const _VisitorActions({required this.onLogin, required this.onRegister});

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
                    l10n.publicProfileGuestPrompt,
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
            Skeleton.expand(height: 108, radius: Radii.md),
            SizedBox(height: Gap.lg),
            Skeleton.expand(height: 62, radius: Radii.sm),
            SizedBox(height: Gap.md),
            Skeleton.expand(height: 78, radius: Radii.md),
          ],
        ),
      ),
    );
  }
}
