import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../communities/community_models.dart';
import '../auth/auth_service.dart';
import '../communities/community_errors.dart';
import 'member_repository.dart';

/// Roster of a community with the actions the viewer's role allows.
/// Every action is re-checked on the server; this screen only decides what to
/// offer and explains why something is unavailable.
class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  final String communityId;
  final String communityName;

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

typedef _Data = (List<CommunityMember>, CommunityRole?);

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final _members = MemberRepository();
  final _authService = AuthService();
  late Future<_Data> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data> _load() async {
    final role = await _members.fetchMyRole(widget.communityId);
    final members = await _members.fetchMembers(widget.communityId);
    return (members, role);
  }

  void _refresh() => setState(() => _future = _load());

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _actionError(AppLocalizations l10n, CommunityActionError e) {
    return switch (e) {
      CommunityActionError.notAuthorized => l10n.errNotAuthorized,
      CommunityActionError.cannotChangeOwnRole => l10n.errCannotChangeOwnRole,
      CommunityActionError.cannotRemoveSelf => l10n.errCannotRemoveSelf,
      CommunityActionError.cannotRemoveOwner => l10n.errCannotRemoveOwner,
      CommunityActionError.alreadyOwner => l10n.errAlreadyOwner,
      CommunityActionError.memberNotFound => l10n.errMemberNotFound,
      CommunityActionError.alreadyMember => l10n.alreadyMemberOfCommunity,
      CommunityActionError.invalidRole => l10n.errInvalidRole,
      // The invite-link and match codes cannot come from these RPCs.
      _ => l10n.genericError,
    };
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
      _say(success);
    } on CommunityActionException catch (e) {
      _say(_actionError(l10n, e.error));
    } catch (_) {
      _say(l10n.genericError);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
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
    final myId = _authService.currentUserId;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageMembersTitle)),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.loadFailed),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: _refresh, child: Text(l10n.retryButton)),
                ],
              ),
            );
          }

          final (members, myRole) = snapshot.data!;
          final isOwner = myRole == CommunityRole.owner;
          final isOrganizer = myRole?.atLeast(CommunityRole.admin) ?? false;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (!isOrganizer)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.permissionOrganizersOnly,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              const Divider(),
              for (final member in members)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(member.fullName),
                  subtitle: Text(_roleLabel(l10n, member.role)),
                  trailing: _memberActions(
                    l10n: l10n,
                    member: member,
                    isOwner: isOwner,
                    isOrganizer: isOrganizer,
                    myId: myId,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget? _memberActions({
    required AppLocalizations l10n,
    required CommunityMember member,
    required bool isOwner,
    required bool isOrganizer,
    required String? myId,
  }) {
    if (member.role == CommunityRole.owner) {
      return Chip(label: Text(l10n.roleOwner));
    }
    // An admin may only act on players; the role structure is the owner's.
    final canAct =
        isOwner || (isOrganizer && member.role == CommunityRole.player);
    if (!canAct || member.userId == myId) return null;

    return PopupMenuButton<String>(
      enabled: !_busy,
      onSelected: (value) async {
        switch (value) {
          case 'promote':
            await _run(
              () => _members.setMemberRole(
                  widget.communityId, member.userId, CommunityRole.admin),
              l10n.memberRoleChanged,
            );
          case 'demote':
            await _run(
              () => _members.setMemberRole(
                  widget.communityId, member.userId, CommunityRole.player),
              l10n.memberRoleChanged,
            );
          case 'transfer':
            if (await _confirm(
              l10n.transferOwnershipConfirmTitle,
              l10n.transferOwnershipConfirmBody(member.fullName),
              l10n.transferOwnershipButton,
            )) {
              await _run(
                () => _members.transferOwnership(
                    widget.communityId, member.userId),
                l10n.ownershipTransferred,
              );
            }
          case 'remove':
            if (await _confirm(
              l10n.removeMemberConfirmTitle,
              l10n.removeMemberConfirmBody(member.fullName),
              l10n.removeMemberButton,
            )) {
              await _run(
                () => _members.removeMember(widget.communityId, member.userId),
                l10n.memberRemoved,
              );
            }
        }
      },
      itemBuilder: (context) => [
        // Role changes and ownership are owner-only (PD-02, PD-03).
        if (isOwner && member.role == CommunityRole.player)
          PopupMenuItem(
              value: 'promote', child: Text(l10n.promoteToAdminButton)),
        if (isOwner && member.role == CommunityRole.admin)
          PopupMenuItem(
              value: 'demote', child: Text(l10n.demoteToPlayerButton)),
        if (isOwner)
          PopupMenuItem(
              value: 'transfer', child: Text(l10n.transferOwnershipButton)),
        PopupMenuItem(value: 'remove', child: Text(l10n.removeMemberButton)),
      ],
    );
  }
}
