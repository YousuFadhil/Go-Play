import 'package:flutter/foundation.dart';

/// The shareable form of an invitation, and the one place that knows how a
/// token is written into a link and read back out of one.
///
/// The scheme is the app's own rather than an https address: Go Play has no
/// web presence, and a link on a domain nobody owns would send anyone without
/// the app to a stranger's site. The trade-off is that some messaging apps
/// render `goplay://` as plain text, so the shared message carries the token on
/// its own line as well and the app accepts either form.
class InviteLink {
  const InviteLink._();

  static const scheme = 'goplay';
  static const _prefix = '$scheme://invite/';

  static String format(String token) => '$_prefix$token';

  /// Pulls a token out of a link, a pasted message, or a bare token. Returns
  /// null when there is nothing token-shaped in [input].
  static String? parse(String? input) {
    if (input == null) return null;
    final text = input.trim();
    if (text.isEmpty) return null;

    final match = RegExp('(?:$_prefix)?([0-9a-fA-F]{32})').firstMatch(text);
    return match?.group(1)?.toLowerCase();
  }
}

/// Holds a token that arrived from outside the app until a screen can act on
/// it. It outlives sign-in on purpose: someone who opens an invitation without
/// an account registers first, and the invitation must still be waiting when
/// they come back.
class PendingInvite {
  PendingInvite._();

  static final instance = PendingInvite._();

  final token = ValueNotifier<String?>(null);

  /// Accepts anything link-shaped; ignores everything else, so an unrelated
  /// route or a stray paste cannot open the invitation screen.
  void offer(String? input) {
    final parsed = InviteLink.parse(input);
    if (parsed != null) token.value = parsed;
  }

  void clear() => token.value = null;
}
