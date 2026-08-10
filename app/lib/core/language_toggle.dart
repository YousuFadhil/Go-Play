import 'package:flutter/material.dart';

import 'locale_controller.dart';

/// The Arabic/English switch.
///
/// It lived on the login screen because the login screen was the first thing
/// anyone saw. It is not any more — a visitor now lands on Discover and may
/// never reach a form — so the control moved out of that screen rather than
/// being copied into this one. Both places build the same widget, and the
/// choice is persisted by [LocaleController] either way.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'ar', label: Text('العربية')),
        ButtonSegment(value: 'en', label: Text('English')),
      ],
      selected: {Localizations.localeOf(context).languageCode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) =>
          LocaleController.instance.setLocale(selection.first),
    );
  }
}
