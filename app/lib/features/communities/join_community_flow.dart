import 'package:flutter/material.dart';

import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Joining a community, wherever it is asked for.
///
/// It is asked for in two places now — the communities list and Discover — and
/// what "join" means is not obvious enough to be written twice: an OPEN
/// community joins outright, one that requires its code asks for the code, being
/// already a member is a normal answer rather than an error, and a policy that
/// changed between the read and the tap has to be handled rather than reported.
/// One implementation, so those four cannot drift into two versions of
/// themselves.
///
/// Returns true when the user is a member afterwards, which is what a caller
/// needs in order to decide whether to reload.

/// Runs the whole flow and reports what happened to the user itself.
///
/// [joinPolicy] is passed when the caller already knows it, which lets a
/// CODE_REQUIRED community ask for its code without a round trip that is certain
/// to be refused. Left null the server is asked first and answers
/// [NeedsJoinCode] if it needs to — the outcome is handled identically either
/// way, so a caller that does not have the policy is not a caller with less
/// behaviour.
Future<bool> runJoinCommunity(
  BuildContext context, {
  required CommunityRepository repository,
  required String communityId,
  JoinPolicy? joinPolicy,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  if (joinPolicy == JoinPolicy.codeRequired) {
    return await _askForCode(context, repository, l10n.joinCodeRequiredPrompt) !=
        null;
  }

  try {
    final outcome = await repository.joinCommunity(communityId);
    if (!context.mounted) return false;

    switch (outcome) {
      case JoinedCommunity():
        // A real join, and only a real join. `AlreadyMember` below is not one:
        // the reader was already in this community, and counting it would make
        // the figure a count of taps on a button rather than of people who
        // joined something.
        ProductAnalytics.instance.track(
          ProductEvent.communityJoined,
          communityId: communityId,
        );
        messenger.showSnackBar(SnackBar(content: Text(l10n.joinedCommunity)));
        return true;
      case NeedsJoinCode():
        // The policy changed under us, or the caller did not know it. Either
        // way the answer is to ask for the code, not to fail.
        return await _askForCode(
              context,
              repository,
              l10n.joinCodeRequiredPrompt,
            ) !=
            null;
      case AlreadyMember():
        // Joined from elsewhere while this list was open.
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.alreadyMemberOfCommunity)));
        return true;
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.communityJoinFailed)));
    return false;
  }
}

Future<String?> _askForCode(
  BuildContext context,
  CommunityRepository repository,
  String prompt,
) =>
    showDialog<String>(
      context: context,
      builder: (_) =>
          JoinCommunityDialog(repository: repository, prompt: prompt),
    );

/// Self-contained "join by code" dialog. It owns its text controller and
/// resolves all inherited widgets (l10n, messenger) through its own context,
/// so nothing from the parent screen leaks into the dialog subtree. Returns
/// the joined community id via [Navigator.pop], or null when dismissed.
class JoinCommunityDialog extends StatefulWidget {
  const JoinCommunityDialog({super.key, required this.repository, this.prompt});

  final CommunityRepository repository;

  /// Shown above the field when the dialog was opened because a community's
  /// policy requires the code, rather than from the generic join action.
  final String? prompt;

  @override
  State<JoinCommunityDialog> createState() => _JoinCommunityDialogState();
}

class _JoinCommunityDialogState extends State<JoinCommunityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final outcome =
          await widget.repository.joinCommunityByCode(_controller.text);
      if (!mounted) return;
      switch (outcome) {
        case JoinedCommunity(:final communityId):
          // The other half of the same event. Joining by code and joining an
          // open community are one thing to the product and are recorded as
          // one; they are two paths only because the door is different.
          ProductAnalytics.instance.track(
            ProductEvent.communityJoined,
            communityId: communityId,
          );
          Navigator.of(context).pop(communityId);
        case AlreadyMember():
          _setError(l10n.alreadyMemberOfCommunity);
        case NeedsJoinCode():
          // Unreachable: this path always sends a code.
          _setError(l10n.communityJoinFailed);
      }
    } on NotFoundFailure {
      _setError(l10n.communityNotFound);
    } catch (_) {
      _setError(l10n.communityJoinFailed);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorText = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.joinCommunityTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.prompt != null) ...[
              Text(widget.prompt!),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _controller,
              autofocus: true,
              // A join code is a number of up to six digits (migration `0030`),
              // so the keyboard that opens is the one it is typed on.
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l10n.joinCodeLabel,
                errorText: _errorText,
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.joinCodeRequired
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.joinCommunityButton),
        ),
      ],
    );
  }
}
