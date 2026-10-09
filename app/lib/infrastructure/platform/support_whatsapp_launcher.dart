import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp via its official https link. The user must press Send there.
/// `wa.me` also offers WhatsApp Web when the app is not installed.
class SupportWhatsAppLauncher {
  const SupportWhatsAppLauncher();

  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
