import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// What the four recorded actions read as.
///
/// **An action this build does not know renders as itself.** The log is
/// append-only and the database deliberately does not filter it, so a later
/// cycle's action will arrive here before this switch has heard of it. Showing
/// the raw value is unlovely and truthful; the alternatives — dropping the row,
/// or crashing on it — would hide exactly the entries most worth seeing.
String _actionLabel(AppLocalizations l10n, String action) => switch (action) {
      'USER_SUSPENDED' => l10n.adminActionUserSuspended,
      'USER_REACTIVATED' => l10n.adminActionUserReactivated,
      'COMMUNITY_SUSPENDED' => l10n.adminActionCommunitySuspended,
      'COMMUNITY_REACTIVATED' => l10n.adminActionCommunityReactivated,
      _ => action,
    };

/// Whether an action put a record out of use, so the row can be toned.
bool _isSuspension(String action) => action.endsWith('_SUSPENDED');

/// The administrative record: what was done, by whom, to what, and why.
///
/// **Read only, structurally.** There is no delete, no edit, no undo and no
/// replay — not hidden behind a role check, but absent from the file. The log
/// is append-only in the database, its writer is granted to nobody, and this
/// screen holds one repository method that returns rows. There is no write path
/// in reach of it.
class AdminAuditTab extends StatefulWidget {
  const AdminAuditTab({super.key, required this.repository});

  final AdminRepository repository;

  @override
  State<AdminAuditTab> createState() => _AdminAuditTabState();
}

class _AdminAuditTabState extends State<AdminAuditTab> {
  late Future<List<AdminAuditEntry>> _future = widget.repository.listAuditLog();

  void _reload() {
    // Block-bodied: an arrow here returns the assigned Future, which trips
    // `setState() callback argument returned a Future` in debug.
    setState(() {
      _future = widget.repository.listAuditLog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<List<AdminAuditEntry>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return ErrorState(onRetry: _reload);
        }

        final entries = snapshot.data!;
        if (entries.isEmpty) {
          // Nothing has happened yet, which on a fresh platform is the ordinary
          // state and not a fault.
          return EmptyState(
            icon: Icons.history,
            message: l10n.adminAuditEmpty,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _AuditRow(entry: entries[index]),
          ),
        );
      },
    );
  }
}

/// One entry: the act, then who and what, then why, then when.
class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AdminAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    // The snapshots are what keep an entry legible after its subject is gone.
    // Where one was never captured the reader is told so in words -- the raw
    // uuid is deliberately not shown, because it names nothing an administrator
    // can act on and reads as noise.
    final actor = entry.actorEmailSnapshot ?? l10n.adminAuditUnavailable;
    final target = entry.targetLabelSnapshot ?? l10n.adminAuditUnavailable;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageMargin,
        vertical: Gap.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GoStatusChip(
                      label: _actionLabel(l10n, entry.action),
                      tone: _isSuspension(entry.action)
                          ? GoChipTone.danger
                          : GoChipTone.open,
                    ),
                    Text(
                      target,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                formatTime(context, entry.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            '${formatMatchDay(context, entry.createdAt)} · $actor',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          // Present for a suspension and absent for a reactivation, which is
          // the database's own rule rather than a display choice.
          if (entry.reason != null) ...[
            const SizedBox(height: Gap.xs),
            Text(entry.reason!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
