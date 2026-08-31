import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/tokens.dart';
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
    this.communityRepository,
  });

  final String communityId;
  final String communityName;
  final String joinCode;

  /// Supplied only by tests. Every sibling screen carries the same seam.
  final CommunityRepository? communityRepository;

  @override
  State<CommunityInvitationScreen> createState() =>
      _CommunityInvitationScreenState();
}

class _CommunityInvitationScreenState extends State<CommunityInvitationScreen> {
  // Late, so that a screen which is only being looked at never reaches for the
  // provider. Regenerating is the one action here that needs it, and it builds
  // the repository when it is asked for rather than when the screen is.
  late final CommunityRepository _communities =
      widget.communityRepository ?? CommunityRepository();
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
    } on AuthorizationFailure {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errNotAuthorized)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.genericError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ClubHero(
              bar: ClubHeroBar(
                title: l10n.communityInvitationTitle,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              identity: Row(
                children: [
                  CommunityCrest(name: widget.communityName, onHero: true),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      widget.communityName,
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
                ],
              ),
            ),
          ),
          Expanded(
            child: ClubSheet(
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Layout.sheetGutter - 4,
                  Gap.md,
                  Layout.sheetGutter - 4,
                  Gap.xl,
                ),
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: GoColors.surfaceCard,
                      borderRadius: BorderRadius.circular(Radii.card),
                      boxShadow: Elevations.card,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Layout.cardInner,
                        Layout.cardInner + 2,
                        Layout.cardInner,
                        Layout.cardInner,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.joinCodeLabel,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: Gap.md),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: SelectableText(
                              _joinCode,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 34,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 6,
                                color: GoColors.primaryDeep,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.lg),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _copy(
                                            value:
                                                l10n.inviteShareCommunityBody(
                                              widget.communityName,
                                              _link,
                                            ),
                                            confirmation:
                                                l10n.inviteLinkCopied,
                                          ),
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(l10n.shareInvitation),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _copy(
                                          value: _joinCode,
                                          confirmation: l10n.joinCodeCopied,
                                        ),
                                icon: const Icon(Icons.copy_outlined),
                                label: Text(l10n.copyJoinCodeButton),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: GoColors.surfaceCard,
                      borderRadius: BorderRadius.circular(Radii.card),
                      boxShadow: Elevations.card,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            Layout.cardInner,
                            Gap.md,
                            Gap.sm,
                            Gap.md,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.link, size: IconSize.action),
                              const SizedBox(width: Gap.md),
                              Expanded(
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    _link,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.start,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _copy(
                                          value: _link,
                                          confirmation: l10n.inviteLinkCopied,
                                        ),
                                child: Text(l10n.copyLinkButton),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: GoColors.hairline),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            Layout.cardInner,
                            Gap.md,
                            Layout.cardInner,
                            Gap.md,
                          ),
                          child: Text(
                            l10n.communityInvitationHelp,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
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
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
