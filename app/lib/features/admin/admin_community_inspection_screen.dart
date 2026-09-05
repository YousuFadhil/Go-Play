import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'admin_detail_row.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// A community, as the Platform Admin inspects it.
///
/// **Inspection, not membership, and the distinction is the whole reason this
/// screen exists.** `CommunityDetailsScreen` is built out of a member's reads —
/// the roster, the join code, the dashboard, the leaderboards — and every one
/// of them is role-checked in the database. Sending a System Admin there would
/// mean loosening those checks so that a non-member could pass them, which is a
/// far larger and more dangerous change than "show me the facts about this
/// community". So this is a separate screen over a separate `security definer`
/// read, and looking at a community here grants the reader nothing.
///
/// **Structurally read only.** There is no join, no join code, no member
/// management, no create-match, no edit, no logo change, no delete and no
/// second Suspend/Reactivate — not hidden behind a check, but absent from the
/// file. Suspension stays on the Users and Communities lists, where its busy
/// flag and reload already live.
class AdminCommunityInspectionScreen extends StatefulWidget {
  const AdminCommunityInspectionScreen({
    super.key,
    required this.communityId,
    this.repository,
  });

  final String communityId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  @override
  State<AdminCommunityInspectionScreen> createState() =>
      _AdminCommunityInspectionScreenState();
}

class _AdminCommunityInspectionScreenState
    extends State<AdminCommunityInspectionScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  late Future<AdminCommunityInspection> _future =
      _repository.communityInspection(widget.communityId);

  void _reload() {
    // Block-bodied: an arrow here returns the assigned Future, which trips
    // `setState() callback argument returned a Future` in debug.
    setState(() {
      _future = _repository.communityInspection(widget.communityId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminCommunityInspectionTitle)),
      body: FutureBuilder<AdminCommunityInspection>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _reload);
          }

          final community = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.only(bottom: Layout.listBottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kPageMargin,
                  Gap.lg,
                  kPageMargin,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (community.description != null) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        community.description!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: Gap.md),
                    GoStatusChip(
                      label: community.isActive
                          ? l10n.adminStatusActive
                          : l10n.adminStatusSuspended,
                      tone: community.isActive
                          ? GoChipTone.open
                          : GoChipTone.danger,
                    ),
                    // Why, and only while it applies: a reason left over from a
                    // suspension that has been lifted would read as a current
                    // one.
                    if (!community.isActive &&
                        community.suspensionReason != null) ...[
                      const SizedBox(height: Gap.sm),
                      Text(
                        community.suspensionReason!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              SectionCard(children: [
                AdminDetailRow(
                  label: l10n.adminMetricOwner,
                  value: community.ownerName ?? adminUnknownValue,
                  unknown: community.ownerName == null,
                ),
                AdminDetailRow(
                  label: l10n.adminMetricCreated,
                  value: formatMatchDay(context, community.createdAt),
                ),
                AdminDetailRow(
                  label: l10n.adminMetricJoinPolicy,
                  value: community.joinPolicy,
                ),
                AdminDetailRow(
                  label: l10n.adminMetricMembers,
                  value: '${community.memberCount}',
                ),
                AdminDetailRow(
                  label: l10n.adminMetricMatches,
                  value: '${community.matchCount}',
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
