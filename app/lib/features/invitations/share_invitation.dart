import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../communities/community_errors.dart';
import 'invitation_repository.dart';
import 'invite_link.dart';

/// Creates (or re-uses) the shareable invitation for a community, or for one
/// match in it, and puts the message on the clipboard.
///
/// The clipboard rather than a share sheet: a native sheet would mean another
/// dependency, and copy-and-paste already reaches every place these are
/// actually shared. The message carries the link and nothing else the reader
/// has to decode.
Future<void> shareInvitation(
  BuildContext context, {
  required String communityId,
  required String communityName,
  String? matchId,
  String? matchTitle,
  InvitationRepository? repository,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final invitations = repository ?? InvitationRepository();

  try {
    final token = await invitations.createInviteLink(
      communityId: communityId,
      matchId: matchId,
    );
    final link = InviteLink.format(token);
    final message = matchId == null
        ? l10n.inviteShareCommunityBody(communityName, link)
        : l10n.inviteShareMatchBody(communityName, matchTitle ?? '', link);

    await Clipboard.setData(ClipboardData(text: message));
    messenger.showSnackBar(SnackBar(content: Text(l10n.inviteLinkCopied)));
  } on CommunityActionException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(switch (e.error) {
        CommunityActionError.notAuthorized => l10n.errNotAuthorized,
        CommunityActionError.matchLocked => l10n.errMatchLocked,
        _ => l10n.genericError,
      }),
    ));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.genericError)));
  }
}
