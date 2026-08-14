import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/locale_controller.dart';
import '../../core/states.dart';
import '../notifications/notification_settings_screen.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';

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
  const SettingsScreen({super.key, this.profileRepository});

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ProfileRepository? profileRepository;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xxl),
        children: [
          SectionHeading(title: l10n.settingsPrivacySection),
          _PrivacyCard(repository: profileRepository),
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

/// Who may open this player's profile, and whether it carries their age.
///
/// The one thing on this screen that is not a device preference, which is why it
/// reads and writes rather than only setting a value: both answers live on the
/// player's row, because the *server* is what applies them (`player_profile`,
/// migration `0043`). Nothing here is a check — a client that never drew this
/// card would still be refused a profile it may not open.
///
/// A change is written immediately. There is no Save button because there is no
/// form: each control is one answer to one question, and a setting that needed
/// confirming would be the only one on the screen that did.
class _PrivacyCard extends StatefulWidget {
  const _PrivacyCard({this.repository});

  final ProfileRepository? repository;

  @override
  State<_PrivacyCard> createState() => _PrivacyCardState();
}

class _PrivacyCardState extends State<_PrivacyCard> {
  late final ProfileRepository _profiles =
      widget.repository ?? ProfileRepository();

  /// Null until the player's own row has been read. The controls are not drawn
  /// against a guessed value: showing "visible to everyone" before the read
  /// returns would state somebody's privacy setting on the strength of a
  /// default.
  ProfilePrivacy? _privacy;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _profiles.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _privacy = profile.privacy;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Writes [next], and puts the previous answer back if the write is refused.
  ///
  /// Shown first and stored second, because the control is a switch and a radio:
  /// waiting for a round trip before either moves reads as a control that does
  /// not work. What must not happen is the screen going on showing a setting the
  /// database does not hold, which is what the revert is for.
  Future<void> _save(ProfilePrivacy next) async {
    final previous = _privacy;
    setState(() {
      _privacy = next;
      _saving = true;
    });
    try {
      await _profiles.saveMyPrivacy(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _privacy = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.genericError)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final privacy = _privacy;

    if (_failed) {
      return FootNote(
        l10n.loadFailed,
        padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.xs, kPageMargin, 0),
      );
    }
    if (privacy == null) {
      return const SectionCard(
        children: [
          Padding(
            padding: EdgeInsets.all(Gap.lg),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<ProfileVisibility>(
          groupValue: privacy.visibility,
          // `RadioGroup` takes a non-null callback, so the guard is inside it
          // rather than on it: a second answer while the first is being written
          // is ignored, exactly as a disabled control would have ignored it.
          onChanged: (choice) {
            if (choice == null || _saving) return;
            _save(privacy.copyWith(visibility: choice));
          },
          child: SectionCard(
            padding: EdgeInsets.zero,
            children: [
              for (final (value, label, help)
                  in <(ProfileVisibility, String, String)>[
                (
                  ProfileVisibility.everyone,
                  l10n.profileVisibilityEveryone,
                  l10n.profileVisibilityEveryoneHelp,
                ),
                (
                  ProfileVisibility.communityMembersOnly,
                  l10n.profileVisibilityCommunityMembers,
                  l10n.profileVisibilityCommunityMembersHelp,
                ),
              ])
                RadioListTile<ProfileVisibility>(
                  value: value,
                  title: Text(label),
                  subtitle: Text(help),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
            ],
          ),
        ),
        SectionCard(
          padding: EdgeInsets.zero,
          children: [
            SwitchListTile(
              value: privacy.ageVisible,
              onChanged: _saving
                  ? null
                  : (value) => _save(privacy.copyWith(ageVisible: value)),
              title: Text(l10n.profileAgeVisibleLabel),
              subtitle: Text(l10n.profileAgeVisibleHelp),
            ),
          ],
        ),
      ],
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
