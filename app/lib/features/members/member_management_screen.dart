import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../auth/auth_service.dart';
import '../profile/profile_screen.dart';
import 'member_repository.dart';

/// Roster of a community with the actions the viewer's role allows.
/// Every action is re-checked on the server; this screen only decides what to
/// offer and explains why something is unavailable.
class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.memberRepository,
    this.authService,
  });

  final String communityId;
  final String communityName;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final MemberRepository? memberRepository;
  final AuthService? authService;

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

typedef _Data = (List<CommunityMember>, CommunityRole?);

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  late final MemberRepository _members =
      widget.memberRepository ?? MemberRepository();
  late final AuthService _authService = widget.authService ?? AuthService();
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

  /// The failure type decides nothing here — every one of these ends the same
  /// way, with a sentence — so the reason is free to choose which sentence.
  String _actionError(AppLocalizations l10n, Failure failure) {
    if (failure is AuthorizationFailure) return l10n.errNotAuthorized;
    return switch (failure.reason) {
      FailureReason.cannotChangeOwnRole => l10n.errCannotChangeOwnRole,
      FailureReason.cannotRemoveSelf => l10n.errCannotRemoveSelf,
      FailureReason.cannotRemoveOwner => l10n.errCannotRemoveOwner,
      FailureReason.alreadyOwner => l10n.errAlreadyOwner,
      FailureReason.memberNotFound => l10n.errMemberNotFound,
      FailureReason.alreadyMember => l10n.alreadyMemberOfCommunity,
      FailureReason.invalidRole => l10n.errInvalidRole,
      // The registration and joining reasons cannot come from these RPCs.
      _ => l10n.genericError,
    };
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
      _say(success);
    } on Failure catch (failure) {
      _say(_actionError(l10n, failure));
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

  /// Opens a member's player profile — the existing screen, told whose record to
  /// read. Tapping yourself lands on your own, which is the same screen again.
  void _openProfile(CommunityMember member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: member.userId),
      ),
    );
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
      appBar: AppHeader(
        title: Text(l10n.manageMembersTitle),
      ),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _refresh);
          }

          final theme = Theme.of(context);
          final (members, myRole) = snapshot.data!;
          final isOwner = myRole == CommunityRole.owner;
          final isOrganizer = myRole?.atLeast(CommunityRole.admin) ?? false;

          if (members.isEmpty) {
            return EmptyState(
              icon: Icons.group_outlined,
              message: l10n.membersEmpty,
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: Gap.xxl),
            children: [
              // A player sees the roster and no controls. Saying so once, at
              // the top, is what stops the screen reading as broken.
              if (!isOrganizer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPageMargin,
                    Gap.lg,
                    kPageMargin,
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          l10n.permissionOrganizersOnly,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SectionHeading(
                title: l10n.membersTitle,
                count: members.length,
                padding: const EdgeInsets.fromLTRB(
                  kPageMargin,
                  Gap.lg,
                  kPageMargin,
                  Gap.sm,
                ),
              ),
              SectionCard(
                padding: EdgeInsets.zero,
                children: [
                  for (final member in members)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        child: const Icon(Icons.person, size: 20),
                      ),
                      title: Text(member.fullName),
                      subtitle: Text(_roleLabel(l10n, member.role)),
                      // A name in a roster is a player, and a player has a
                      // record. Whether this viewer may read it is the server's
                      // decision — sharing this community is one of the two
                      // things that opens a profile, so from here it ordinarily
                      // is — and the profile screen reports a refusal itself.
                      onTap: () => _openProfile(member),
                      trailing: _memberActions(
                        l10n: l10n,
                        member: member,
                        isOwner: isOwner,
                        isOrganizer: isOrganizer,
                        myId: myId,
                      ),
                    ),
                ],
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
      return _RoleChip(label: l10n.roleOwner);
    }
    // An admin may only act on players; the role structure is the owner's.
    final canAct =
        isOwner || (isOrganizer && member.role == CommunityRole.player);
    if (!canAct || member.userId == myId) return null;

    return PopupMenuButton<String>(
      enabled: !_busy,
      tooltip: l10n.moreActionsLabel,
      icon: const Icon(Icons.more_vert),
      position: PopupMenuPosition.under,
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
            value: 'promote',
            child: _MenuRow(
              icon: Icons.shield_outlined,
              label: l10n.promoteToAdminButton,
            ),
          ),
        if (isOwner && member.role == CommunityRole.admin)
          PopupMenuItem(
            value: 'demote',
            child: _MenuRow(
              icon: Icons.person_outline,
              label: l10n.demoteToPlayerButton,
            ),
          ),
        if (isOwner)
          PopupMenuItem(
            value: 'transfer',
            child: _MenuRow(
              icon: Icons.swap_horiz,
              label: l10n.transferOwnershipButton,
            ),
          ),
        PopupMenuItem(
          value: 'remove',
          child: _MenuRow(
            icon: Icons.person_remove_outlined,
            label: l10n.removeMemberButton,
            destructive: true,
          ),
        ),
      ],
    );
  }
}

/// A menu entry with its icon, so a list of actions reads as actions rather
/// than as a list of sentences.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = destructive ? scheme.error : null;

    return Row(
      children: [
        Icon(icon, size: 20, color: colour),
        const SizedBox(width: Gap.md),
        Expanded(child: Text(label, style: TextStyle(color: colour))),
      ],
    );
  }
}

/// The role a member holds, where it is not the ordinary one.
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
