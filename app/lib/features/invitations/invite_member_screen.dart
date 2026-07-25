import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../communities/community_models.dart';
import '../communities/group_service.dart';
import 'invitation_models.dart';

/// Finds a player by name and invites them. Only an owner may offer the admin
/// role, so the role choice is hidden for admins (PD-10); the server enforces
/// it either way.
class InviteMemberScreen extends StatefulWidget {
  const InviteMemberScreen({
    super.key,
    required this.communityId,
    required this.myRole,
  });

  final String communityId;
  final CommunityRole myRole;

  @override
  State<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

class _InviteMemberScreenState extends State<InviteMemberScreen> {
  final _service = GroupService();
  final _controller = TextEditingController();
  List<UserSummary> _results = const [];
  CommunityRole _role = CommunityRole.player;
  bool _searching = false;
  bool _sending = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final results = await _service.searchUsers(_controller.text);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
          _searched = true;
        });
      }
    }
  }

  String _actionError(AppLocalizations l10n, CommunityActionError e) {
    return switch (e) {
      CommunityActionError.notAuthorized => l10n.errNotAuthorized,
      CommunityActionError.alreadyMember => l10n.alreadyMemberOfCommunity,
      CommunityActionError.invitationExists => l10n.errInvitationExists,
      CommunityActionError.invalidRole => l10n.errInvalidRole,
      _ => l10n.genericError,
    };
  }

  Future<void> _invite(UserSummary user) async {
    final l10n = context.l10n;
    setState(() => _sending = true);
    try {
      await _service.createInvitation(widget.communityId, user.id, _role);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.invitationSent)));
      Navigator.of(context).pop(true);
    } on CommunityActionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_actionError(l10n, e.error))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.genericError)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _positionLabel(AppLocalizations l10n, String position) {
    return switch (position) {
      'GK' => l10n.positionGk,
      'DEF' => l10n.positionDef,
      'MID' => l10n.positionMid,
      'FWD' => l10n.positionFwd,
      _ => position,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canInviteAdmins = widget.myRole == CommunityRole.owner;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.inviteMemberTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: l10n.searchPlayersLabel,
                helperText: l10n.searchPlayersHint,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ),
            ),
          ),
          if (canInviteAdmins)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(l10n.inviteAsRoleLabel),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<CommunityRole>(
                      segments: [
                        ButtonSegment(
                          value: CommunityRole.player,
                          label: Text(l10n.rolePlayer),
                        ),
                        ButtonSegment(
                          value: CommunityRole.admin,
                          label: Text(l10n.roleAdmin),
                        ),
                      ],
                      selected: {_role},
                      onSelectionChanged: (s) =>
                          setState(() => _role = s.first),
                    ),
                  ),
                ],
              ),
            ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searched ? l10n.searchNoResults : l10n.searchPlayersHint,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final user in _results)
                        ListTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(user.fullName),
                          subtitle:
                              Text(_positionLabel(l10n, user.position)),
                          trailing: FilledButton.tonal(
                            onPressed: _sending ? null : () => _invite(user),
                            child: Text(l10n.inviteButton),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
