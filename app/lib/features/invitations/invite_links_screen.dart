import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import '../communities/community_errors.dart';
import 'invitation_models.dart';
import 'invitation_repository.dart';
import 'invite_link.dart';

/// The organizer's view of the links they have shared: what is out there, and
/// the ability to take one back.
///
/// Only live links are listed. Revoking is how an organizer says they are done
/// with a link, so a revoked one drops off rather than lingering as clutter.
class InviteLinksScreen extends StatefulWidget {
  const InviteLinksScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  final String communityId;
  final String communityName;

  @override
  State<InviteLinksScreen> createState() => _InviteLinksScreenState();
}

class _InviteLinksScreenState extends State<InviteLinksScreen> {
  final _invitations = InvitationRepository();
  late Future<List<InviteLinkSummary>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _invitations.fetchInviteLinks(widget.communityId);
  }

  void _refresh() {
    setState(() {
      _future = _invitations.fetchInviteLinks(widget.communityId);
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(InviteLinkSummary link) async {
    final l10n = context.l10n;
    final message = link.isMatchLink
        ? l10n.inviteShareMatchBody(widget.communityName, link.matchTitle ?? '',
            InviteLink.format(link.token))
        : l10n.inviteShareCommunityBody(
            widget.communityName, InviteLink.format(link.token));
    await Clipboard.setData(ClipboardData(text: message));
    _say(l10n.inviteLinkCopied);
  }

  Future<void> _revoke(InviteLinkSummary link) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.revokeLinkConfirmTitle),
        content: Text(l10n.revokeLinkConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.revokeLinkButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _invitations.revokeInviteLink(link.id);
      _say(l10n.inviteLinkRevokedMessage);
      _refresh();
    } on CommunityActionException catch (e) {
      _say(e.error == CommunityActionError.notAuthorized
          ? l10n.errNotAuthorized
          : l10n.genericError);
    } catch (_) {
      _say(l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.inviteLinksTitle)),
      body: FutureBuilder<List<InviteLinkSummary>>(
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

          final links = snapshot.data!;
          if (links.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.inviteLinksEmpty,
                    textAlign: TextAlign.center),
              ),
            );
          }

          return ListView.separated(
            itemCount: links.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _LinkTile(link: links[index], busy: _busy, onCopy: _copy,
                    onRevoke: _revoke),
          );
        },
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.link,
    required this.busy,
    required this.onCopy,
    required this.onRevoke,
  });

  final InviteLinkSummary link;
  final bool busy;
  final Future<void> Function(InviteLinkSummary) onCopy;
  final Future<void> Function(InviteLinkSummary) onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final dateFormat = DateFormat.yMMMd(locale);

    // A link that can no longer be opened says so, rather than looking live.
    final state = link.isMatchDeleted
        ? l10n.inviteLinkMatchDeletedLabel
        : link.isExpired
            ? l10n.inviteLinkExpiredLabel
            : l10n.inviteLinkCreatedOn(dateFormat.format(link.createdAt));

    return ListTile(
      leading: Icon(
        link.isMatchLink ? Icons.sports_soccer : Icons.groups,
        color: link.isUsable ? null : theme.colorScheme.outline,
      ),
      title: Text(
        // A deleted match leaves no title behind, so the row says what kind of
        // link it is rather than borrowing an unrelated label.
        link.isMatchLink
            ? (link.matchTitle ?? l10n.inviteLinkMatchLabel)
            : l10n.inviteLinkCommunityLabel,
      ),
      subtitle: Text(
        state,
        style: link.isUsable
            ? null
            : theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.copyLinkButton,
            icon: const Icon(Icons.copy_outlined),
            // Copying a dead link would only spread something that cannot work.
            onPressed: busy || !link.isUsable ? null : () => onCopy(link),
          ),
          IconButton(
            tooltip: l10n.revokeLinkButton,
            icon: const Icon(Icons.link_off),
            onPressed: busy ? null : () => onRevoke(link),
          ),
        ],
      ),
    );
  }
}
