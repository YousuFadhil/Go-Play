import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../matches/create_match_screen.dart';
import '../matches/match_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import 'group_models.dart';
import 'group_service.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final _groupService = GroupService();
  final _matchService = MatchService();
  late Future<(Community, List<CommunityMember>, List<Match>)> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<(Community, List<CommunityMember>, List<Match>)> _loadData() async {
    final results = await Future.wait([
      _groupService.fetchGroup(widget.groupId),
      _groupService.fetchMembers(widget.groupId),
      _matchService.fetchGroupMatches(widget.groupId),
    ]);
    return (
      results[0] as Community,
      results[1] as List<CommunityMember>,
      results[2] as List<Match>,
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _openCreateMatch() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMatchScreen(groupId: widget.groupId),
      ),
    );
    if (created == true) _refresh();
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.joinCodeCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<(Community, List<CommunityMember>, List<Match>)>(
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

        final (group, members, matches) = snapshot.data!;

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(group.name),
              bottom: TabBar(
                tabs: [
                  Tab(text: l10n.matchesTitle),
                  Tab(text: '${l10n.membersTitle} (${members.length})'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              tooltip: l10n.createMatchTitle,
              onPressed: _openCreateMatch,
              child: const Icon(Icons.add),
            ),
            body: TabBarView(
              children: [
                _MatchesTab(matches: matches, onChanged: _refresh),
                _MembersTab(
                  group: group,
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
  const _MatchesTab({required this.matches, required this.onChanged});

  final List<Match> matches;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.groupMatchesEmpty,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final match in matches)
          MatchCard(match: match, onChanged: onChanged),
      ],
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.group,
    required this.members,
    required this.positionLabel,
    required this.onCopyJoinCode,
  });

  final Community group;
  final List<CommunityMember> members;
  final String Function(BuildContext, String) positionLabel;
  final Future<void> Function(String) onCopyJoinCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (group.description != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(group.description!),
          ),
        ListTile(
          leading: const Icon(Icons.key),
          title: Text(l10n.joinCodeLabel),
          subtitle: Text(
            group.joinCode,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => onCopyJoinCode(group.joinCode),
          ),
        ),
        const Divider(),
        for (final member in members)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(member.fullName),
            subtitle: Text(positionLabel(context, member.position)),
            trailing:
                member.isOwner ? Chip(label: Text(l10n.ownerBadge)) : null,
          ),
      ],
    );
  }
}
