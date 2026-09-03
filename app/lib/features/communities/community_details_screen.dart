import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/responsive_grid.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../matches/compact_match_card.dart';
import '../matches/create_match_screen.dart';
import 'member_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../invitations/community_invitation_screen.dart';
import '../members/member_management_screen.dart';
import '../statistics/community_dashboard_tab.dart';
import '../statistics/community_leaderboards_tab.dart';
import '../statistics/statistics_repository.dart';
import 'community_models.dart';
import '../members/member_repository.dart';
import 'community_repository.dart';

class CommunityDetailsScreen extends StatefulWidget {
  const CommunityDetailsScreen({
    super.key,
    required this.communityId,
    this.communityRepository,
    this.memberRepository,
    this.matchService,
    this.statisticsRepository,
  });

  final String communityId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  /// Left null the screen builds the production ones, so nothing here knows
  /// what a data provider is.
  final CommunityRepository? communityRepository;
  final MemberRepository? memberRepository;
  final MatchService? matchService;

  /// Handed to the two statistics tabs, which already take one of their own.
  final StatisticsRepository? statisticsRepository;

  @override
  State<CommunityDetailsScreen> createState() => _CommunityDetailsScreenState();
}

/// What one build of this screen holds.
///
/// The last element is the join code, and it is nullable for one reason: it is
/// only ever read for an owner or an admin. Migration `0056` made the code a
/// separate, role-checked read rather than a column of the community, so a
/// Player's build genuinely does not have one — and the screen that used to
/// hide the value now simply never receives it.
typedef _Data = (
  Community,
  List<CommunityMember>,
  List<Match>,
  CommunityRole?,
  String?,
);

/// One thing an organizer can do to a community, chosen from the actions sheet.
///
/// An enum rather than callbacks passed into the sheet: the sheet is a menu and
/// nothing more, so it closes with an answer and the screen — which owns the
/// busy flag, the reload and the messenger — is what acts on it.
enum _CommunityAction { invitation, joinPolicy, members, delete }

class _CommunityDetailsScreenState extends State<CommunityDetailsScreen> {
  late final CommunityRepository _communityRepository =
      widget.communityRepository ?? CommunityRepository();
  late final MemberRepository _memberRepository =
      widget.memberRepository ?? MemberRepository();
  late final MatchService _matchService = widget.matchService ?? MatchService();
  late Future<_Data> _dataFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_Data> _loadData() async {
    final results = await Future.wait([
      _communityRepository.fetchCommunity(widget.communityId),
      _memberRepository.fetchMembers(widget.communityId),
      _matchService.fetchCommunityMatches(widget.communityId),
      _memberRepository.fetchMyRole(widget.communityId),
    ]);
    final role = results[3] as CommunityRole?;

    // Asked second, and only when the answer would be given. A Player's request
    // would be refused server-side, so making it would be a round trip whose
    // only outcome is a refusal — and the screen has nowhere to put a code it
    // is not going to show.
    final joinCode = (role?.atLeast(CommunityRole.admin) ?? false)
        ? await _fetchJoinCode()
        : null;

    return (
      results[0] as Community,
      results[1] as List<CommunityMember>,
      results[2] as List<Match>,
      role,
      joinCode,
    );
  }

  /// The join code, or null when it could not be read.
  ///
  /// A failure here is not a failure of the screen. Everything else has already
  /// loaded, and a community page that reports "could not load" because one
  /// organizer-only card is missing would be reporting the wrong thing.
  Future<String?> _fetchJoinCode() async {
    try {
      return await _communityRepository.fetchJoinCode(widget.communityId);
    } catch (_) {
      return null;
    }
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCreateMatch() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMatchScreen(communityId: widget.communityId),
      ),
    );
    if (created == true) _refresh();
  }

  /// How people join is the community's only setting, so it lives in the
  /// actions sheet rather than behind a screen of its own.
  Future<void> _setJoinPolicy(JoinPolicy policy) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await _communityRepository.setJoinPolicy(widget.communityId,
          joinPolicy: policy);
      _say(l10n.joinPolicySaved);
      _refresh();
    } on AuthorizationFailure {
      _say(l10n.permissionOwnerOnly);
    } catch (_) {
      _say(l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The invitation screen, which is the join code and the link made from it.
  ///
  /// [joinCode] is passed in rather than read here: this screen already has it
  /// for an organizer, and asking a second time would be a second authorization
  /// decision about the same thing. A null code means the read was refused or
  /// failed, and there is no invitation to show without one.
  Future<void> _openInvitation(Community community, String? joinCode) async {
    if (joinCode == null) {
      _say(context.l10n.loadFailed);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityInvitationScreen(
          communityId: community.id,
          communityName: community.name,
          joinCode: joinCode,
        ),
      ),
    );
    // The code may have been regenerated behind that screen.
    _refresh();
  }

  Future<void> _openMembers(String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberManagementScreen(
          communityId: widget.communityId,
          communityName: name,
        ),
      ),
    );
    _refresh();
  }

  /// The community's actions, in a sheet.
  ///
  /// They used to be three icons crowded into the app bar beside a scrolling
  /// tab strip — a share menu, a group glyph and, for an owner, a bare bin. A
  /// bar is a poor place for an action that needs a name, and it was a very
  /// poor place for the destructive one: a mistap on `delete_outline` is
  /// exactly as easy as a mistap on anything else. Here each action carries its
  /// label, deletion sits last behind a divider in the error colour, and what a
  /// player never has permission for is simply not in the sheet.
  Future<void> _openActions({
    required Community community,
    required bool isOwner,
    required bool isOrganizer,
    required String? joinCode,
  }) async {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final codeRequired = community.joinPolicy == JoinPolicy.codeRequired;

    final action = await showModalBottomSheet<_CommunityAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                Gap.sm,
                kPageMargin,
                Gap.md,
              ),
              child: Text(
                community.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            // Sharing an invitation means showing the join code, so it is
            // offered to the owner and admins and to nobody else.
            if (isOrganizer)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: Text(l10n.shareInvitation),
                subtitle: Text(l10n.communityInvitationTitle),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CommunityAction.invitation),
              ),
            if (isOwner)
              ListTile(
                leading: Icon(codeRequired ? Icons.password : Icons.public),
                title: Text(l10n.joinPolicyLabel),
                subtitle: Text(codeRequired
                    ? l10n.joinPolicyCodeRequired
                    : l10n.joinPolicyOpen),
                trailing: Switch(
                  value: codeRequired,
                  // The switch does not write from inside the sheet. It reports
                  // the tap the same way the row does, so there is one path out
                  // of here and one place the write happens.
                  onChanged: (_) => Navigator.of(sheetContext)
                      .pop(_CommunityAction.joinPolicy),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CommunityAction.joinPolicy),
              ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(l10n.manageMembersTitle),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_CommunityAction.members),
            ),
            if (isOwner) ...[
              const Divider(),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.deleteCommunityButton,
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CommunityAction.delete),
              ),
            ],
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _CommunityAction.invitation:
        await _openInvitation(community, joinCode);
      case _CommunityAction.joinPolicy:
        await _setJoinPolicy(
          codeRequired ? JoinPolicy.open : JoinPolicy.codeRequired,
        );
      case _CommunityAction.members:
        await _openMembers(community.name);
      case _CommunityAction.delete:
        await _deleteCommunity();
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteCommunity() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    if (!await _confirm(
      l10n.deleteCommunityConfirmTitle,
      l10n.deleteCommunityConfirmBody,
      l10n.deleteCommunityButton,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _communityRepository.deleteCommunity(widget.communityId);
      _say(l10n.communityDeleted);
      navigator.pop();
    } on AuthorizationFailure {
      _say(l10n.permissionOwnerOnly);
    } catch (_) {
      _say(l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _positionLabel(BuildContext context, String position) {
    final l10n = context.l10n;
    return switch (position) {
      'GK' => l10n.positionGk,
      'DEF' => l10n.positionDef,
      'MID' => l10n.positionMid,
      'FWD' => l10n.positionFwd,
      _ => position,
    };
  }

  Future<void> _copyJoinCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _say(context.l10n.joinCodeCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<_Data>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            appBar: _PlaceLoadingBar(),
            body: LoadingState(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: const _PlaceLoadingBar(),
            body: ErrorState(onRetry: _refresh),
          );
        }

        final (community, members, matches, myRole, joinCode) = snapshot.data!;
        final isOwner = myRole == CommunityRole.owner;
        // Creating a match is an organizer action now (PD-06), and so is
        // everything to do with the join code (see `_MembersTab`).
        final isOrganizer = myRole?.atLeast(CommunityRole.admin) ?? false;

        // The counts on the hero. Every one of them is a list directly below
        // it, already loaded — the hero reports what the screen is holding
        // rather than asking anybody a second question about it.
        final upcoming = matches.where((m) => !m.isCompleted).length;
        final played = matches.length - upcoming;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            // The ground behind the sheet's rounded top corners, and what makes
            // the sheet read as riding up over the hero.
            backgroundColor: GoColors.bgHero,
            body: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: ClubHero(
                    bar: ClubHeroBar(
                      onBack: () => Navigator.of(context).maybePop(),
                      actions: [
                        IconButton(
                          tooltip: l10n.moreActionsLabel,
                          color: Colors.white,
                          iconSize: IconSize.bar,
                          icon: const Icon(Icons.more_vert),
                          onPressed: _busy
                              ? null
                              : () => _openActions(
                                    community: community,
                                    isOwner: isOwner,
                                    isOrganizer: isOrganizer,
                                    joinCode: joinCode,
                                  ),
                        ),
                      ],
                    ),
                    identity: _HeroIdentity(
                      community: community,
                      roleLabel:
                          myRole == null || myRole == CommunityRole.player
                              ? null
                              : _roleLabel(l10n, myRole),
                    ),
                    counts: Row(
                      children: [
                        Flexible(
                          child: ClubHeroCount(
                            value: members.length,
                            label: l10n.membersTitle,
                          ),
                        ),
                        const SizedBox(width: Gap.lg + 2),
                        Flexible(
                          child: ClubHeroCount(
                            value: upcoming,
                            label: l10n.upcomingMatchesTitle,
                          ),
                        ),
                        const SizedBox(width: Gap.lg + 2),
                        Flexible(
                          child: ClubHeroCount(
                            value: played,
                            label: l10n.completedMatchesTitle,
                          ),
                        ),
                      ],
                    ),
                    // The organizer's two actions, where the direction puts
                    // them. Creating a match was a floating button and sharing
                    // an invitation was inside the actions sheet; both still do
                    // exactly what they did, and the sheet still offers the
                    // invitation for anybody who looks there first.
                    action: isOrganizer
                        ? Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  key: const Key('heroCreateMatch'),
                                  style: ClubHeroButtons.filled,
                                  onPressed: _busy ? null : _openCreateMatch,
                                  icon:
                                      const Icon(Icons.add, size: IconSize.row),
                                  label: Text(
                                    l10n.createMatchButton,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              Flexible(
                                child: OutlinedButton.icon(
                                  key: const Key('heroInvite'),
                                  style: ClubHeroButtons.ghost,
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                          _openInvitation(community, joinCode),
                                  icon: const Icon(Icons.person_add_outlined,
                                      size: IconSize.row),
                                  label: Text(
                                    l10n.shareInvitation,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: ClubSheet(
                    child: Column(
                      children: [
                        TabBar(
                          // Four destinations still, and four labels do not fit
                          // side by side on a phone — so the strip scrolls
                          // rather than squeezing each into a quarter width.
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            Tab(text: l10n.matchesTitle),
                            Tab(text: l10n.membersTitle),
                            Tab(text: l10n.dashboardTab),
                            Tab(text: l10n.leaderboardsTab),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _MatchesTab(
                                matches: matches,
                                onChanged: _refresh,
                                // Players could create matches before; say why
                                // the button is gone rather than leaving them
                                // to guess.
                                permissionNote: isOrganizer
                                    ? null
                                    : l10n.matchCreateOrganizersOnly,
                              ),
                              _MembersTab(
                                community: community,
                                members: members,
                                joinCode: joinCode,
                                positionLabel: _positionLabel,
                                onCopyJoinCode: _copyJoinCode,
                              ),
                              CommunityDashboardTab(
                                communityId: widget.communityId,
                                // Already loaded and already on this screen's
                                // hero; the tab needs it for the card it can
                                // share and reads nothing of its own to get it.
                                communityName: community.name,
                                repository: widget.statisticsRepository,
                              ),
                              CommunityLeaderboardsTab(
                                communityId: widget.communityId,
                                // The same name the Dashboard tab is given, and
                                // for the same reason: it is already loaded and
                                // already on this screen's hero, so the tab
                                // reads nothing of its own to put a community
                                // on the card it can share.
                                communityName: community.name,
                                repository: widget.statisticsRepository,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The community's matches: what is still to be played, then what has been.
class _MatchesTab extends StatelessWidget {
  const _MatchesTab({
    required this.matches,
    required this.onChanged,
    this.permissionNote,
  });

  final List<Match> matches;
  final VoidCallback onChanged;
  final String? permissionNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.sports_soccer,
        message: l10n.communityMatchesEmpty,
        note: permissionNote,
      );
    }

    // Two lists, not one. A played match and one still to come are different
    // things to a member — one is a plan, the other is a record — and mixing
    // them by date buried this week's fixture under last season's. Completion is
    // read from `effectiveStatus`, so a match whose end time has passed sorts as
    // played whether or not its stored row has been touched since.
    final upcoming = [
      for (final match in matches)
        if (!match.isCompleted) match,
    ];
    final completed = [
      for (final match in matches)
        if (match.isCompleted) match,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xxl * 2),
      children: [
        if (upcoming.isNotEmpty) ...[
          SectionHeading(
            title: l10n.upcomingMatchesTitle,
            count: upcoming.length,
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.lg,
              kPageMargin,
              Gap.xs,
            ),
          ),
          // A grid each, not one grid over both. The two lists are separate on
          // purpose — a plan and a record are different things to a member —
          // and a shared grid would let the last fixture of one share a row
          // with the first of the other.
          _MatchGrid(matches: upcoming, onChanged: onChanged),
        ],
        if (completed.isNotEmpty) ...[
          SectionHeading(
            title: l10n.completedMatchesTitle,
            count: completed.length,
          ),
          _MatchGrid(matches: completed, onChanged: onChanged),
        ],
        if (permissionNote != null) FootNote(permissionNote!),
      ],
    );
  }
}

/// One run of matches, two across.
class _MatchGrid extends StatelessWidget {
  const _MatchGrid({required this.matches, required this.onChanged});

  final List<Match> matches;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => ResponsiveCardGrid(
        maxColumns: 2,
        minCardWidth: GridCard.matchMinWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.sheetGutter,
          vertical: Gap.xs,
        ),
        children: [
          for (final match in matches)
            // The community's name is not repeated on a card inside that
            // community's own screen, which is the rule the row card used here
            // as well.
            CompactMatchCard(match: match, onChanged: onChanged),
        ],
      );
}

/// Who is in the community — and, for an organizer, how to let more people in.
class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.community,
    required this.members,
    required this.joinCode,
    required this.positionLabel,
    required this.onCopyJoinCode,
  });

  final Community community;
  final List<CommunityMember> members;

  /// The community's join code, or null when this reader is not entitled to one.
  ///
  /// This used to be an `isOrganizer` flag beside a code every build carried,
  /// which made the tab responsible for not drawing something it was holding.
  /// Since migration `0056` the code is fetched only for an owner or an admin,
  /// so a Player's build has nothing to withhold — the null is the permission.
  final String? joinCode;
  final String Function(BuildContext, String) positionLabel;
  final Future<void> Function(String) onCopyJoinCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xxl * 2),
      children: [
        if (community.description != null &&
            community.description!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.lg,
              kPageMargin,
              0,
            ),
            child: Text(
              community.description!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),

        // **Organizers only.** The join code is the credential that lets
        // somebody into this community, and a player holding one can hand the
        // community to anybody. It is not merely hidden from the roster here —
        // the invitation screen that shares it is reachable only from the
        // actions sheet, which offers it under the same condition.
        if (joinCode != null)
          _JoinCodeCard(
            code: joinCode!,
            onCopy: () => onCopyJoinCode(joinCode!),
          ),

        SectionHeading(title: l10n.membersTitle, count: members.length),
        if (members.isEmpty)
          EmptyState(icon: Icons.group_outlined, message: l10n.membersEmpty)
        else
          // Three across, where three fit. A roster used to be a column of
          // list rows, each spending a full line of the screen on a face and
          // two short words; a squad of sixteen was most of a scroll. What each
          // card carries is unchanged from the row it replaces — the face, the
          // name, the position, the role where there is one — and so is what
          // happens when it is touched.
          ResponsiveCardGrid(
            maxColumns: 3,
            minCardWidth: GridCard.memberMinWidth,
            padding: const EdgeInsets.symmetric(
              horizontal: Layout.sheetGutter,
              vertical: Gap.xs,
            ),
            children: [
              for (final member in members)
                CommunityMemberCard(
                  userId: member.userId,
                  fullName: member.fullName,
                  avatarUrl: member.avatarUrl,
                  positionLabel: positionLabel(context, member.position),
                  roleLabel: member.role == CommunityRole.player
                      ? null
                      : _roleLabel(l10n, member.role),
                ),
            ],
          ),
      ],
    );
  }
}

/// The join code, set out as the credential it is.
///
/// Left-to-right and monospaced whatever the reader's language: it is not
/// language, it is read aloud and typed, and it never reverses.
class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.lg,
        kPageMargin,
        Gap.xs,
      ),
      child: Card(
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: [
              Icon(Icons.key_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.joinCodeLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color:
                            scheme.onPrimaryContainer.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      code,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.copyJoinCodeButton,
                icon: const Icon(Icons.copy_outlined),
                color: scheme.onPrimaryContainer,
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What to call a role.
///
/// One function rather than a method on the tab that used to own it: the hero
/// and the members list now name the same role, and two places wording it
/// separately is how they end up disagreeing.
String _roleLabel(AppLocalizations l10n, CommunityRole role) => switch (role) {
      CommunityRole.owner => l10n.roleOwner,
      CommunityRole.admin => l10n.roleAdmin,
      CommunityRole.player => l10n.rolePlayer,
    };

/// The bar a place shows while it has nothing to put on its hero.
///
/// Deep green and empty rather than the app header: the screen underneath is
/// about to be a hero, and flashing a white bar first is a jump the reader has
/// no reason to see. It keeps the back button, because a load that fails still
/// has to be leaveable.
class _PlaceLoadingBar extends StatelessWidget implements PreferredSizeWidget {
  const _PlaceLoadingBar();

  @override
  Size get preferredSize => const Size.fromHeight(Layout.heroBarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: Layout.heroBarHeight,
      backgroundColor: GoColors.bgHero,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(
        color: Colors.white,
        size: IconSize.navBack,
      ),
    );
  }
}

/// Whose place this is: the crest, the name, the reader's standing in it, and
/// what the community says about itself.
class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity({required this.community, required this.roleLabel});

  final Community community;

  /// Null for a player and for a visitor. A role marker that says "Player" on
  /// every ordinary member is a badge for having done nothing.
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    final description = community.description?.trim() ?? '';

    return Row(
      children: [
        CommunityCrest(name: community.name, size: 58, onHero: true),
        const SizedBox(width: Gap.sm + 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Bounded, so a long name shortens instead of pushing the
                  // role marker off the edge of the hero.
                  Flexible(
                    child: Text(
                      community.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (roleLabel != null) ...[
                    const SizedBox(width: Gap.sm),
                    _OnHeroRoleChip(label: roleLabel!),
                  ],
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// [GoRoleChip] as it appears on a hero.
///
/// The same square, the same type, the same measurements — only the two colours
/// differ, because the shared chip is drawn for a light card and this one sits
/// on deep green. The shape is what carries the meaning and the shape is
/// unchanged.
class _OnHeroRoleChip extends StatelessWidget {
  const _OnHeroRoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Radii.roleChip),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        softWrap: false,
        style: GoType.roleChip.copyWith(color: Colors.white),
      ),
    );
  }
}
