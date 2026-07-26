import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../communities/community_models.dart';
import '../communities/community_errors.dart';
import 'invitation_repository.dart';
import 'invitation_models.dart';

/// Invitations addressed to the signed-in user. Only the named invitee can
/// accept one, which the server enforces.
class MyInvitationsScreen extends StatefulWidget {
  const MyInvitationsScreen({super.key});

  @override
  State<MyInvitationsScreen> createState() => _MyInvitationsScreenState();
}

class _MyInvitationsScreenState extends State<MyInvitationsScreen> {
  final _repository = InvitationRepository();
  late Future<List<Invitation>> _future;
  bool _busy = false;
  bool _joinedAny = false;

  @override
  void initState() {
    super.initState();
    _future = _repository.fetchMyInvitations();
  }

  void _refresh() => setState(() => _future = _repository.fetchMyInvitations());

  String _actionError(AppLocalizations l10n, CommunityActionError e) {
    return switch (e) {
      CommunityActionError.notAuthorized => l10n.errNotAuthorized,
      CommunityActionError.alreadyMember => l10n.alreadyMemberOfCommunity,
      CommunityActionError.invitationNotFound => l10n.errInvitationNotFound,
      CommunityActionError.invitationNotPending => l10n.errInvitationNotPending,
      CommunityActionError.invitationExpired => l10n.errInvitationExpired,
      _ => l10n.genericError,
    };
  }

  Future<void> _accept(Invitation invitation) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await _repository.acceptInvitation(invitation.id);
      _joinedAny = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.invitationAccepted)));
    } on CommunityActionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_actionError(l10n, e.error))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.genericError)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_joinedAny);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.myInvitationsTitle)),
        body: FutureBuilder<List<Invitation>>(
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

            final invitations = snapshot.data!;
            if (invitations.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.myInvitationsEmpty,
                      textAlign: TextAlign.center),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final invitation in invitations)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.mail)),
                    title: Text(
                      l10n.invitationFrom(invitation.communityName ?? '—'),
                    ),
                    subtitle: Text(_roleLabel(l10n, invitation.role)),
                    trailing: FilledButton(
                      onPressed: _busy || !invitation.isActionable
                          ? null
                          : () => _accept(invitation),
                      child: Text(l10n.acceptInvitationButton),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
