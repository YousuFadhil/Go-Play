import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'notification_models.dart';
import 'notification_service.dart';

/// What the phone is allowed to interrupt a player about.
///
/// Three switches, and the note at the top is load-bearing rather than
/// decorative: these settings govern **push only**. Every notice is written to
/// the Notification Center whatever is set here, so nothing on this screen can
/// lose a player anything — which is what makes it safe to turn all of it off.
///
/// Deliberately not a per-type matrix. Sixteen notification types would make
/// sixteen switches, and a settings screen nobody finishes reading is a settings
/// screen that gets muted wholesale instead.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.service});

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final NotificationService? service;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationService _service =
      widget.service ?? NotificationService();

  late Future<PushPreferences> _future;
  PushPreferences? _current;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PushPreferences> _load() async {
    final preferences = await _service.fetchPushPreferences();
    _current = preferences;
    return preferences;
  }

  /// Applies a switch immediately and writes it behind the flip.
  ///
  /// Optimistic because a switch that waits for a round trip before moving
  /// reads as broken. A failed write puts it back and says so, which is the
  /// only honest thing to do with a setting that did not take.
  Future<void> _apply(PushPreferences next) async {
    final previous = _current!;
    setState(() {
      _current = next;
      _saving = true;
    });

    try {
      await _service.savePushPreferences(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _current = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pushSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.pushSettingsTitle)),
      body: FutureBuilder<PushPreferences>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || _current == null) {
            return ErrorState(
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final preferences = _current!;
          // The master switch does not merely outrank the other two — it makes
          // them meaningless, so they are shown as such rather than left
          // looking effective.
          final categoriesEnabled = !preferences.muteAll && !_saving;

          return ListView(
            padding: const EdgeInsets.only(bottom: Gap.xxl),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kPageMargin,
                  Gap.lg,
                  kPageMargin,
                  Gap.sm,
                ),
                child: Text(
                  l10n.pushSettingsIntro,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              SwitchListTile(
                value: preferences.matchPush && !preferences.muteAll,
                onChanged: categoriesEnabled
                    ? (value) => _apply(preferences.copyWith(matchPush: value))
                    : null,
                secondary: const Icon(Icons.sports_soccer),
                title: Text(l10n.pushMatchLabel),
                subtitle: Text(l10n.pushMatchSubtitle),
              ),
              SwitchListTile(
                value: preferences.communityPush && !preferences.muteAll,
                onChanged: categoriesEnabled
                    ? (value) =>
                        _apply(preferences.copyWith(communityPush: value))
                    : null,
                secondary: const Icon(Icons.groups),
                title: Text(l10n.pushCommunityLabel),
                subtitle: Text(l10n.pushCommunitySubtitle),
              ),
              const Divider(height: Gap.xl),
              SwitchListTile(
                value: preferences.muteAll,
                onChanged: _saving
                    ? null
                    : (value) => _apply(preferences.copyWith(muteAll: value)),
                secondary: const Icon(Icons.notifications_off_outlined),
                title: Text(l10n.pushMuteAllLabel),
                subtitle: Text(l10n.pushMuteAllSubtitle),
              ),
            ],
          );
        },
      ),
    );
  }
}
