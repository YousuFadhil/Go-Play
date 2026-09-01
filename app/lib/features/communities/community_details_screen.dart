import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../matches/create_match_screen.dart';
import '../matches/match_card.dart';
import '../profile/player_identity.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../invitations/community_invitation_screen.dart';
import '../members/member_management_screen.dart';
import '../statistics/community_dashboard_tab.dart';
import '../statistics/community_leaderboards_tab.dart';
import 'community_models.dart';
import '../members/member_repository.dart';
import 'community_repository.dart';

class CommunityDetailsScreen extends StatefulWidget {
  const CommunityDetailsScreen({super.key, required this.communityId});

  final String communityId;

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
  final _communityRepository = CommunityRepository();
  final _memberRepository = MemberRepository();
  final _matchService = MatchService();
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
                onTap: () => Navigator.of(sheetContext)
                    .pop(_CommunityAction.invitation),
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
                onTap: () => Navigator.of(sheetContext)
                    .pop(_CommunityAction.joinPolicy),
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
            appBar: AppHeader(),
            body: LoadingState(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: const AppHeader(),
            body: ErrorState(onRetry: _refresh),
          );
        }

        final (community, members, matches, myRole, joinCode) =
            snapshot.data!;
        final isOwner = myRole == CommunityRole.owner;
        // Creating a match is an organizer action now (PD-06), and so is
        // everything to do with the join code (see `_MembersTab`).
        final isOrganizer = myRole?.atLeast(CommunityRole.admin) ?? false;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppHeader(
              title: Text(community.name),
              actions: [
                IconButton(
                  tooltip: l10n.moreActionsLabel,
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
              bottom: TabBar(
                // Four tabs no longer fit side by side on a phone, so the bar
                // scrolls rather than squeezing every label into a third of
                // its width.
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: l10n.matchesTitle),
                  Tab(text: l10n.membersTitle),
                  Tab(text: l10n.dashboardTab),
                  Tab(text: l10n.leaderboardsTab),
                ],
              ),
            ),
            floatingActionButton: isOrganizer
                ? FloatingActionButton.extended(
                    tooltip: l10n.createMatchTitle,
                    onPressed: _openCreateMatch,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.createMatchButton),
                  )
                : null,
            body: TabBarView(
              children: [
                _MatchesTab(
                  matches: matches,
                  onChanged: _refresh,
                  // Players could create matches before; say why the button is
                  // gone rather than leaving them to guess.
                  permissionNote:
                      isOrganizer ? null : l10n.matchCreateOrganizersOnly,
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
                  // Already loaded and already in this screen's title; the tab
                  // needs it for the card it can share and reads nothing of its
                  // own to get it.
                  communityName: community.name,
                ),
                CommunityLeaderboardsTab(communityId: widget.communityId),
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
          for (final match in upcoming)
            MatchCard(match: match, onChanged: onChanged),
        ],
        if (completed.isNotEmpty) ...[
          SectionHeading(
            title: l10n.completedMatchesTitle,
            count: completed.length,
          ),
          for (final match in completed)
            MatchCard(match: match, onChanged: onChanged),
        ],
        if (permissionNote != null) FootNote(permissionNote!),
      ],
    );
  }
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

  String _roleLabel(AppLocalizations l10n, CommunityRole role) {
    return switch (role) {
      CommunityRole.owner => l10n.roleOwner,
      CommunityRole.admin => l10n.roleAdmin,
      CommunityRole.player => l10n.rolePlayer,
    };
  }

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
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              for (final member in members)
                ListTile(
                  leading: PlayerAvatar(
                    avatarUrl: member.avatarUrl,
                    fullName: member.fullName,
                  ),
                  title: Text(member.fullName),
                  subtitle: Text(positionLabel(context, member.position)),
                  // A name in a roster is a player, and a player has a record.
                  // Nothing else claims this row — the role chip is a label,
                  // not a control — so the whole tile opens the profile, and
                  // whether it may be read is the server's answer.
                  onTap: () => openPlayerProfile(context, member.userId),
                  trailing: member.role == CommunityRole.player
                      ? null
                      : _RoleChip(label: _roleLabel(l10n, member.role)),
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
                        color: scheme.onPrimaryContainer
                            .withValues(alpha: 0.85),
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

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
