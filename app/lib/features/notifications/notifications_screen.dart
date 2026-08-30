import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../../core/club_task.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../matches/match_details_screen.dart';
import 'notification_display.dart';
import 'notification_models.dart';
import 'notification_route.dart';
import 'notification_service.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.service, this.onOpenMatch});

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final NotificationService? service;

  /// Where a tapped notice goes. Supplied only by tests, for the same reason
  /// [service] is: Match Details builds its own repositories, so a test that
  /// let the real screen be pushed would be a test against Supabase.
  final void Function(String matchId)? onOpenMatch;

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
    return () async {
      // Read because it was acted on. This screen already marks everything read
      // on open, so this is belt and braces here — but it keeps the tile's
      // behaviour identical to a tapped push, which has no such sweep.
      try {
        await _service.markRead(n.id);
      } catch (_) {
        // A stale badge, never a lost notice. Not worth failing the tap over.
      }
      if (!mounted) return;
      final open = widget.onOpenMatch;
      if (open != null) {
        open(target.matchId!);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MatchDetailsScreen(matchId: target.matchId!),
        ),
      );
      // Back from the match. The list itself has not changed, but the read
      // state has, and re-reading is what keeps this screen and the badge
      // telling the same story.
      _refresh();
    };
  }

  /// The match a notice is about, for the tile's second line.
  ///
  /// Null when the notice names no match, and null when its match has been
  /// deleted — `match_id` is nulled by the delete, so there is nothing to name.
  /// Both render as no subtitle rather than as an apology for one.
  String? _context(AppNotification n) {
    final title = n.matchTitle?.trim();
    return (title == null || title.isEmpty) ? null : title;
  }

  Widget _taskBody(Widget child) => ClubTaskBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: context.l10n.pushSettingsTitle,
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: _openSettings,
              ),
            ),
            child,
          ],
        ),
      );

  Widget _notificationRow(
    AppLocalizations l10n,
    AppNotification notification,
    String locale,
  ) {
    final display = notificationDisplays[notification.type];
    final (background, foreground) =
        (display?.tone ?? NotificationTone.neutral)
            .colours(Theme.of(context).colorScheme);
    final theme = Theme.of(context);
    final matchTitle = _context(notification);
    final unread = !notification.isRead;

    return Material(
      key: Key('notification_surface_${notification.id}'),
      color: unread ? GoColors.surfaceCard : GoColors.rowTintLight,
      child: InkWell(
        key: Key('notification_${notification.id}'),
        onTap: _openFor(notification),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Layout.cardInner,
            Gap.md,
            Gap.sm,
            Gap.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: background,
                foregroundColor: foreground,
                child: Icon(display?.icon ?? Icons.notifications, size: 20),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _text(l10n, notification),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (matchTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        matchTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.yMMMEd(locale)
                          .add_Hm()
                          .format(notification.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: Gap.sm,
                    top: 7,
                  ),
                  child: DecoratedBox(
                    key: Key('notification_unread_${notification.id}'),
                    decoration: BoxDecoration(
                      color: GoColors.alert,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(width: 8, height: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: ClubTaskBar(title: l10n.notificationsTitle),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _taskBody(const LoadingState());
          }
          if (snapshot.hasError) {
            return _taskBody(ErrorState(onRetry: _refresh));
          }

          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return _taskBody(EmptyState(
              icon: Icons.notifications_none,
              message: l10n.notificationsEmpty,
            ));
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: _taskBody(
              DecoratedBox(
                decoration: BoxDecoration(
                  color: GoColors.surfaceCard,
                  borderRadius: BorderRadius.circular(Radii.card),
                  boxShadow: Elevations.card,
                ),
                child: Column(
                  children: [
                    for (final (index, notification) in items.indexed) ...[
                      _notificationRow(l10n, notification, locale),
                      if (index < items.length - 1)
                        Divider(height: 1, color: GoColors.hairline),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
