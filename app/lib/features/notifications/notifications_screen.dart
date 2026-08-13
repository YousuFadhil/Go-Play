import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../matches/match_details_screen.dart';
import 'notification_display.dart';
import 'notification_models.dart';
import 'notification_route.dart';
import 'notification_service.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.service});

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final NotificationService? service;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationService _service =
      widget.service ?? NotificationService();
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppNotification>> _load() async {
    final list = await _service.fetchAll();
    // Opening the screen marks everything as read.
    await _service.markAllRead();
    return list;
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );
  }

  /// Localized text for a notification, falling back to the stored message.
  ///
  /// The fallback is Arabic whatever the reader's language, so a type with no
  /// entry in [notificationDisplays] is a defect rather than a graceful
  /// degradation — it renders in one language for everybody and says nothing
  /// about why.
  String _text(AppLocalizations l10n, AppNotification n) =>
      notificationDisplays[n.type]?.label(l10n) ?? n.message;

  /// Opens what a notice is about, through the same decision a tapped push goes
  /// through.
  ///
  /// Returns null — leaving the tile inert rather than tappable — for a notice
  /// that names nothing, so the affordance and the behaviour cannot disagree.
  /// This screen *is* the fallback destination, so there is nowhere for a
  /// non-actionable notice to go; a match that then fails to load renders Match
  /// Details' own error state, which is the existing answer to that and is not
  /// changed here.
  VoidCallback? _openFor(AppNotification n) {
    final target = NotificationTarget.of(n);
    if (!target.opensMatch) return null;
    return () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchDetailsScreen(matchId: target.matchId!),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppHeader(
        title: Text(l10n.notificationsTitle),
        actions: [
          IconButton(
            tooltip: l10n.pushSettingsTitle,
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError) {
            return ErrorState(onRetry: _refresh);
          }

          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none,
              message: l10n.notificationsEmpty,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.xl),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: Gap.xxl + Gap.xl),
              itemBuilder: (context, index) {
                final n = items[index];
                final display = notificationDisplays[n.type];
                // An unregistered type still renders — as a plain notice in
                // whatever language it was stored in, which is what an
                // unrecognised kind of thing honestly looks like.
                final (background, foreground) =
                    (display?.tone ?? NotificationTone.neutral)
                        .colours(Theme.of(context).colorScheme);

                final theme = Theme.of(context);

                return ListTile(
                  onTap: _openFor(n),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: background,
                    foregroundColor: foreground,
                    child: Icon(display?.icon ?? Icons.notifications, size: 20),
                  ),
                  title: Text(_text(l10n, n), style: theme.textTheme.bodyLarge),
                  subtitle: Text(
                    DateFormat.yMMMEd(locale).add_Hm().format(n.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
