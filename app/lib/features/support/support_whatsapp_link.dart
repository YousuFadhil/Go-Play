/// A WhatsApp support message is handed to WhatsApp by a normal https link.
/// Go Play never sends the message and never needs WhatsApp API credentials.
abstract final class SupportWhatsAppLink {
  static final _phonePattern = RegExp(r'^[1-9][0-9]{7,14}$');

  /// E.164 international digits (the only form wa.me accepts), without '+'.
  /// Empty input deliberately means 'not configured'.
  static String? normalizePhone(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return null;
    final digits = value.startsWith('+') ? value.substring(1) : value;
    return _phonePattern.hasMatch(digits) ? digits : null;
  }

  static Uri build({
    required String phone,
    required String reason,
    required String message,
  }) {
    final digits = normalizePhone(phone);
    if (digits == null || message.trim().isEmpty) {
      throw const FormatException('Invalid support destination or message');
    }
    final content = 'Go Play — ${reason.trim()}\n${message.trim()}';
    // Percent-encoded by hand: Uri.https(queryParameters) writes a space as '+',
    // while WhatsApp's documented links use %20, which every reader accepts.
    return Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/$digits',
      query: 'text=${Uri.encodeComponent(content)}',
    );
  }
}
