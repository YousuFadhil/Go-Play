import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'notification_models.dart';
import 'notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
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

  /// Localized text for a notification, falling back to the stored message.
  String _text(AppLocalizations l10n, AppNotification n) {
    return switch (n.type) {
      'match_updated' => l10n.notifMatchUpdated,
      'moved_to_reserve' => l10n.notifMovedToReserve,
      'removed' => l10n.notifRemoved,
      'promoted' => l10n.notifPromoted,
      'match_deleted' => l10n.notifMatchDeleted,
      _ => n.message,
    };
  }

  IconData _icon(String type) {
    return switch (type) {
      'match_updated' => Icons.edit_calendar,
      'moved_to_reserve' => Icons.hourglass_top,
      'removed' => Icons.person_remove,
      'promoted' => Icons.arrow_upward,
      'match_deleted' => Icons.delete_forever,
      _ => Icons.notifications,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.loadFailed),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            );
          }

          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.notificationsEmpty,
                    textAlign: TextAlign.center),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = items[index];
                return ListTile(
                  leading: CircleAvatar(child: Icon(_icon(n.type))),
                  title: Text(_text(l10n, n)),
                  subtitle: Text(
                    DateFormat.yMMMEd(locale).add_Hm().format(n.createdAt),
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
