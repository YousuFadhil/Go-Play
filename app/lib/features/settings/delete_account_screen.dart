import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../auth/auth_service.dart';
import '../members/member_management_screen.dart';
import 'account_deletion_models.dart';
import 'account_deletion_repository.dart';

/// Deleting your own account, for good.
///
/// **Server first.** The screen asks the database whether anything blocks the deletion
/// and shows what it answers; it decides nothing. The database asks again, inside its
/// own transaction, when the deletion is requested.
///
/// What can block, and what the person can do about it:
///   * owning a community -- listed by name, each opening the existing member screen,
///     where ownership is transferred. Coming back reads the question again;
///   * being a System Admin, or being suspended -- told, with nothing to do here.
///
/// When nothing blocks, one destructive button opens a confirmation that asks for a
/// word to be typed, and a single request does the whole thing. The request names no
/// account: it is the signed-in user's own, and the server knows who that is.
///
/// A deletion that returned has happened. The session is then ended on this device and
/// the app goes back to its first screen. A failure that may have reached the server is
/// worded as "may or may not have worked" -- never as "nothing changed" -- so a dropped
/// connection cannot invite a second attempt at something already done.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    this.repository,
    this.onSignOut,
    this.onOpenCommunity,
  });

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AccountDeletionRepository? repository;

  /// Ends the session on this device. Default: the app's own sign-out.
  final Future<void> Function()? onSignOut;

  /// Opens the screen where a community's ownership is transferred.
  final Future<void> Function(BuildContext context, OwnedCommunity community)?
      onOpenCommunity;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  late final AccountDeletionRepository _repository =
      widget.repository ?? AccountDeletionRepository();

  late Future<MyAccountDeletionPreview> _future = _load();

  /// True from the moment the request is sent until it is answered.
  bool _deleting = false;

  /// True while the confirmation is open, so that two taps in one frame open one dialog.
  bool _confirming = false;

  /// The account is gone. Shown until the session has ended and the app has left this screen.
  bool _done = false;
  Failure? _failure;

  Future<MyAccountDeletionPreview> _load() {
    final preview = _repository.previewMyDeletion();
    // A retry builds on the next frame, after this may already have failed.
    // `FutureBuilder` still shows the failure; `ignore` only stops it being
    // reported a second time as unhandled.
    preview.ignore();
    return preview;
  }

  void _reload() {
    setState(() {
      _future = _load();
      _failure = null;
    });
  }

  Future<void> _openCommunity(OwnedCommunity community) async {
    final open = widget.onOpenCommunity ?? _defaultOpenCommunity;
    await open(context, community);
    // Ownership may have moved; ask again.
    if (mounted) _reload();
  }

  static Future<void> _defaultOpenCommunity(
    BuildContext context,
    OwnedCommunity community,
  ) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MemberManagementScreen(
            communityId: community.id,
            communityName: community.name,
          ),
        ),
      );

  static Future<void> _defaultSignOut() => AuthService().logout();

  Future<void> _delete() async {
    if (_deleting || _confirming) return;
    _confirming = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const _ConfirmDialog(),
      );
    } finally {
      _confirming = false;
    }
    if (confirmed != true || !mounted || _deleting) return;

    setState(() {
      _deleting = true;
      _failure = null;
    });
    try {
      await _repository.deleteMyAccount();
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _failure = failure;
      });
      return;
    }

    // The account is gone. Said at once; what is left on this device goes too.
    if (mounted) {
      setState(() {
        _deleting = false;
        _done = true;
      });
    }
    try {
      await (widget.onSignOut ?? _defaultSignOut)();
    } catch (_) {
      // The server already ended every session of the account, so a sign-out that cannot
      // reach it has nothing left to end there; the local copy is cleared first.
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (_done) {
      return Scaffold(
        appBar: AppHeader(title: Text(l10n.deleteMyAccountTitle)),
        body: Padding(
          key: const Key('deleteAccountDone'),
          padding: const EdgeInsets.all(kPageMargin),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: Gap.md),
              Text(
                l10n.deleteAccountDoneTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.sm),
              Text(l10n.deleteAccountDoneBody, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.deleteMyAccountTitle)),
      body: FutureBuilder<MyAccountDeletionPreview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _reload);
          }
          return _Body(
            preview: snapshot.data!,
            deleting: _deleting,
            failure: _failure,
            onOpenCommunity: _openCommunity,
            onDelete: _delete,
            onCheckAgain: _reload,
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.preview,
    required this.deleting,
    required this.failure,
    required this.onOpenCommunity,
    required this.onDelete,
    required this.onCheckAgain,
  });

  final MyAccountDeletionPreview preview;
  final bool deleting;
  final Failure? failure;
  final Future<void> Function(OwnedCommunity community) onOpenCommunity;
  final VoidCallback onDelete;
  final VoidCallback onCheckAgain;

  static String failureText(AppLocalizations l10n, Failure failure) {
    // The deletion was never attempted: the picture could not be removed first.
    if (failure.reason == FailureReason.avatarCleanupFailed) {
      return l10n.deleteAccountFailedAvatarCleanup;
    }
    final text = switch (failure) {
      ConflictFailure() => l10n.deleteAccountFailedBlocked,
      AuthorizationFailure() => l10n.deleteAccountFailedAuthorization,
      ValidationFailure() ||
      NotFoundFailure() ||
      AuthenticationFailure() =>
        l10n.deleteAccountFailedGeneric,
      // A dropped connection, a database error: the request may have reached the server
      // and the deletion may have committed.
      _ => l10n.deleteAccountFailedUncertain,
    };
    // The picture goes before the deletion runs, so a deletion that failed afterwards has
    // still cost it. Said as a fact on top of the failure, never instead of it.
    return failure.reason == FailureReason.avatarRemovedFirst
        ? '$text ${l10n.deleteAccountAvatarRemovedNote}'
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final failure = this.failure;
    // After a failed attempt nothing more is offered until the question has been asked
    // again: the server may have refused for a reason this screen no longer reflects, or
    // may even have done the deletion.
    final canDelete = !preview.hasBlockers && !deleting && failure == null;

    return ListView(
      padding: const EdgeInsets.only(bottom: Layout.listBottom),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
          child: Row(
            key: const Key('deleteAccountIntro'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: IconSize.meta,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  l10n.deleteAccountIntro,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (preview.ownsCommunities) ...[
          SectionHeading(
            title: l10n.deleteAccountOwnsTitle,
            count: preview.ownedTotal,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: Text(
              l10n.deleteAccountOwnsBody,
              key: const Key('deleteAccountOwnsBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              for (final community in preview.ownedCommunities)
                ListTile(
                  key: Key('deleteAccountOwned_${community.id}'),
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(community.name),
                  subtitle: Text(
                    l10n.deleteAccountOwnedRow(community.memberCount),
                  ),
                  trailing: TextButton(
                    onPressed: deleting
                        ? null
                        : () => onOpenCommunity(community),
                    child: Text(l10n.deleteAccountManageMembers),
                  ),
                  onTap: deleting ? null : () => onOpenCommunity(community),
                ),
            ],
          ),
        ],
        if (preview.isSystemAdmin)
          _Note(
            key: const Key('deleteAccountBlockedAdmin'),
            text: l10n.deleteAccountBlockedAdmin,
          ),
        if (preview.isSuspended)
          _Note(
            key: const Key('deleteAccountBlockedSuspended'),
            text: l10n.deleteAccountBlockedSuspended,
          ),
        if (preview.upcomingRegistrations > 0 && !preview.hasBlockers)
          _Note(
            key: const Key('deleteAccountUpcoming'),
            text: l10n.deleteAccountUpcoming(preview.upcomingRegistrations),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.xl, kPageMargin, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (failure != null) ...[
                Container(
                  key: const Key('deleteAccountFailure'),
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(Gap.sm),
                  ),
                  child: Text(
                    failureText(l10n, failure),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                OutlinedButton(
                  key: const Key('deleteAccountCheckAgain'),
                  onPressed: deleting ? null : onCheckAgain,
                  child: Text(l10n.adminMergeCheckAgain),
                ),
                const SizedBox(height: Gap.md),
              ],
              FilledButton(
                key: const Key('deleteAccountButton'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: canDelete ? onDelete : null,
                child: deleting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: Gap.sm),
                          Text(l10n.deleteAccountRunning),
                        ],
                      )
                    : Text(l10n.deleteAccountButton),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
}

/// The confirmation: a word has to be typed.
class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog();

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final word = l10n.deleteAccountConfirmWord;
    final matches = _controller.text.trim().toLowerCase() == word.toLowerCase();

    return AlertDialog(
      key: const Key('deleteAccountConfirmDialog'),
      title: Text(l10n.deleteAccountConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountConfirmBody),
            const SizedBox(height: Gap.md),
            TextField(
              key: const Key('deleteAccountConfirmField'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.deleteAccountConfirmLabel(word),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('deleteAccountConfirmCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          key: const Key('deleteAccountConfirmAction'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.deleteAccountConfirmAction),
        ),
      ],
    );
  }
}
