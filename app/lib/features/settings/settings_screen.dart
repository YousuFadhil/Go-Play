import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/locale_controller.dart';
import '../../core/states.dart';
import '../notifications/notification_settings_screen.dart';

/// The app's settings, and the only place the language is chosen.
///
/// The language control used to be on the login screen and on Discover — a
/// segmented button sitting above the form, in the way of the thing the visitor
/// actually came to do, on the two screens least likely to be the one where
/// somebody decides to change languages. It is here instead, where a setting
/// belongs, and the app follows the device until somebody comes here and says
/// otherwise.
///
/// Deliberately thin. Everything on it is a preference held on this device;
/// nothing here writes to the account except the push preferences, which have
/// their own screen and keep it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xxl),
        children: [
          SectionHeading(title: l10n.settingsLanguageSection),
          const _LanguageCard(),
          FootNote(
            l10n.languageSystemDefaultHelp,
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.xs,
              kPageMargin,
              0,
            ),
          ),
          SectionHeading(title: l10n.settingsNotificationsSection),
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(l10n.pushSettingsTitle),
                subtitle: Text(l10n.pushSettingsIntro),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The three answers to "what language", one of which is "whatever the phone
/// says" — offered first, because it is the default and the one that needs no
/// decision.
///
/// Radio rows rather than a segmented button: a segmented control implies a
/// small set of equals, and "follow the device" is not the peer of a language.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, locale, _) {
        final selected = locale?.languageCode;

        return RadioGroup<String?>(
          groupValue: selected,
          onChanged: (choice) => LocaleController.instance.setLocale(choice),
          child: SectionCard(
            padding: EdgeInsets.zero,
            children: [
              for (final (value, label) in <(String?, String)>[
                (null, l10n.languageSystemDefault),
                ('ar', l10n.languageArabic),
                ('en', l10n.languageEnglish),
              ])
                RadioListTile<String?>(
                  value: value,
                  title: Text(label),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
            ],
          ),
        );
      },
    );
  }
}
