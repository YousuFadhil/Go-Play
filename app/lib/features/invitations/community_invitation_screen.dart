import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../communities/community_errors.dart';
import '../communities/community_repository.dart';
import 'invite_link.dart';

/// The one place an organizer invites people to a community.
///
/// There is a single identifier behind every action here: the community's join
/// code. The link is that code in a URL, so someone who cannot tap a link can
/// still be told the code and type it — and regenerating retires both at once,
/// because there is only one thing to retire.
class CommunityInvitationScreen extends StatefulWidget {
  const CommunityInvitationScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.joinCode,
  });

  final String communityId;
  final String communityName;
  final String joinCode;

  @override
  State<CommunityInvitationScreen> createState() =>
      _CommunityInvitationScreenState();
}

class _CommunityInvitationScreenState extends State<CommunityInvitationScreen> {
  final _communities = CommunityRepository();
  late String _joinCode = widget.joinCode;
  bool _busy = false;

  String get _link => InviteLink.format(_joinCode);

  Future<void> _copy({
    required String value,
    required String confirmation,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: value));
    messenger.showSnackBar(SnackBar(content: Text(confirmation)));
  }

  Future<void> _regenerate() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.regenerateJoinCodeConfirmTitle),
        content: Text(l10n.regenerateJoinCodeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.regenerateJoinCodeButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final code = await _communities.regenerateJoinCode(widget.communityId);
      // Held in state rather than popped back for, so the new code and link are
      // copyable straight away without reopening the screen.
      setState(() => _joinCode = code);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.joinCodeRegenerated)),
      );
    } on CommunityActionException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.error == CommunityActionError.notAuthorized
            ? l10n.errNotAuthorized
            : l10n.genericError),
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.genericError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.communityInvitationTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.communityInvitationHelp,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),

            Text(l10n.joinCodeLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            // The code is what people read aloud, so it is set large and
            // left-to-right: it is not language, and it never reverses.
            SelectableText(
              _joinCode,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _copy(
                      value: _joinCode, confirmation: l10n.joinCodeCopied),
              icon: const Icon(Icons.copy_outlined),
              label: Text(l10n.copyJoinCodeButton),
            ),

            const Divider(height: 40),

            Text(l10n.inviteLinkLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SelectableText(
              _link,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () =>
                      _copy(value: _link, confirmation: l10n.inviteLinkCopied),
              icon: const Icon(Icons.link),
              label: Text(l10n.copyLinkButton),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _copy(
                        value: l10n.inviteShareCommunityBody(
                            widget.communityName, _link),
                        confirmation: l10n.inviteLinkCopied,
                      ),
              icon: const Icon(Icons.ios_share),
              label: Text(l10n.shareInvitation),
            ),

            const Divider(height: 40),

            // Last, and outlined rather than filled: it is the destructive one.
            OutlinedButton.icon(
              onPressed: _busy ? null : _regenerate,
              icon: _busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.autorenew),
              label: Text(l10n.regenerateJoinCodeButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
