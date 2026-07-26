import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../matches/create_match_screen.dart';
import '../matches/match_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../invitations/invite_links_screen.dart';
import '../invitations/share_invitation.dart';
import '../members/member_management_screen.dart';
import 'community_models.dart';
import '../members/member_repository.dart';
import 'community_errors.dart';
import 'community_repository.dart';

class CommunityDetailsScreen extends StatefulWidget {
  const CommunityDetailsScreen({super.key, required this.communityId});

  final String communityId;

  @override
  State<CommunityDetailsScreen> createState() => _CommunityDetailsScreenState();
}

typedef _Data = (
  Community,
  List<CommunityMember>,
  List<Match>,
  CommunityRole?,
);

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
    return (
      results[0] as Community,
      results[1] as List<CommunityMember>,
      results[2] as List<Match>,
      results[3] as CommunityRole?,
    );
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

  Future<void> _openInviteLinks(String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InviteLinksScreen(
          communityId: widget.communityId,
          communityName: name,
        ),
      ),
    );
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

  Future<bool> _confirm(String title, String body, String action) async {
    final l10n = context.l10n;
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
    } on CommunityActionException catch (e) {
      _say(e.error == CommunityActionError.notAuthorized
          ? l10n.permissionOwnerOnly
          : l10n.genericError);
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
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.loadFailed),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            ),
          );
        }

        final (community, members, matches, myRole) = snapshot.data!;
        final isOwner = myRole == CommunityRole.owner;
        // Creating a match is an organizer action now (PD-06).
        final canCreateMatch = myRole?.atLeast(CommunityRole.admin) ?? false;

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(community.name),
              actions: [
                if (canCreateMatch)
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.ios_share),
                        onPressed: () => shareInvitation(
                          context,
                          communityId: community.id,
                          communityName: community.name,
                        ),
                        child: Text(l10n.shareInvitation),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.link),
                        onPressed: () => _openInviteLinks(community.name),
                        child: Text(l10n.inviteLinksTitle),
                      ),
                    ],
                    builder: (context, controller, _) => IconButton(
                      tooltip: l10n.shareInvitation,
                      icon: const Icon(Icons.ios_share),
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                IconButton(
                  tooltip: l10n.manageMembersTitle,
                  icon: const Icon(Icons.group),
                  onPressed: () => _openMembers(community.name),
                ),
                if (isOwner)
                  IconButton(
                    tooltip: l10n.deleteCommunityButton,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : _deleteCommunity,
                  ),
              ],
              bottom: TabBar(
                tabs: [
                  Tab(text: l10n.matchesTitle),
                  Tab(text: '${l10n.membersTitle} (${members.length})'),
                ],
              ),
            ),
            floatingActionButton: canCreateMatch
                ? FloatingActionButton(
                    tooltip: l10n.createMatchTitle,
                    onPressed: _openCreateMatch,
                    child: const Icon(Icons.add),
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
                      canCreateMatch ? null : l10n.matchCreateOrganizersOnly,
                ),
                _MembersTab(
                  community: community,
                  members: members,
                  positionLabel: _positionLabel,
                  onCopyJoinCode: _copyJoinCode,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.communityMatchesEmpty, textAlign: TextAlign.center),
              if (permissionNote != null) ...[
                const SizedBox(height: 12),
                Text(
                  permissionNote!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final match in matches)
          MatchCard(match: match, onChanged: onChanged),
        if (permissionNote != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              permissionNote!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.community,
    required this.members,
    required this.positionLabel,
    required this.onCopyJoinCode,
  });

  final Community community;
  final List<CommunityMember> members;
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

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (community.description != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(community.description!),
          ),
        ListTile(
          leading: const Icon(Icons.key),
          title: Text(l10n.joinCodeLabel),
          subtitle: Text(
            community.joinCode,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => onCopyJoinCode(community.joinCode),
          ),
        ),
        const Divider(),
        for (final member in members)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(member.fullName),
            subtitle: Text(positionLabel(context, member.position)),
            trailing: member.role == CommunityRole.player
                ? null
                : Chip(label: Text(_roleLabel(l10n, member.role))),
          ),
      ],
    );
  }
}
