import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'admin_community_inspection_screen.dart';
import 'admin_detail_row.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// A match, as the Platform Admin inspects it.
///
/// **Structurally read only**, on the same terms as the community screen beside
/// it: no register, no withdraw, no roster, no team generation, no result
/// entry, no edit and no delete — absent from the file rather than hidden. The
/// screen holds one repository method that returns facts, and there is no write
/// path in reach of it.
///
/// The community name leads to [AdminCommunityInspectionScreen] rather than to
/// the member-only community screen, for the reason that screen exists: a
/// System Admin inspecting a match must not acquire a membership by following a
/// link out of it.
class AdminMatchInspectionScreen extends StatefulWidget {
  const AdminMatchInspectionScreen({
    super.key,
    required this.matchId,
    this.repository,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  @override
  State<AdminMatchInspectionScreen> createState() =>
      _AdminMatchInspectionScreenState();
}

class _AdminMatchInspectionScreenState
    extends State<AdminMatchInspectionScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  late Future<AdminMatchInspection> _future =
      _repository.matchInspection(widget.matchId);

  void _reload() {
    // Block-bodied: an arrow here returns the assigned Future, which trips
    // `setState() callback argument returned a Future` in debug.
    setState(() {
      _future = _repository.matchInspection(widget.matchId);
    });
  }

  void _openCommunity(AdminMatchInspection match) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminCommunityInspectionScreen(
          communityId: match.communityId,
          repository: _repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminMatchInspectionTitle)),
      body: FutureBuilder<AdminMatchInspection>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _reload);
          }

          final match = snapshot.data!;
          final theme = Theme.of(context);

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
                      match.title ?? match.location,
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (match.description != null) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        match.description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SectionCard(children: [
                AdminDetailRow(
                  label: l10n.adminCommunitiesTab,
                  value: match.communityName ?? adminUnknownValue,
                  unknown: match.communityName == null,
                  // Only when there is still a community to open.
                  onTap: match.communityName == null
                      ? null
                      : () => _openCommunity(match),
                ),
                AdminDetailRow(
                  label: l10n.adminMetricKickOff,
                  value: '${formatMatchDay(context, match.startAt)} '
                      '• ${formatTime(context, match.startAt)}',
                ),
                AdminDetailRow(
                  label: l10n.adminMetricLocation,
                  value: match.location,
                ),
                AdminDetailRow(
                  label: l10n.adminMetricStatus,
                  value: match.status,
                ),
                AdminDetailRow(
                  label: l10n.adminMetricCreated,
                  value: formatMatchDay(context, match.createdAt),
                ),
                AdminDetailRow(
                  label: l10n.adminMetricCreatedBy,
                  value: match.creatorName ?? adminUnknownValue,
                  unknown: match.creatorName == null,
                ),
                AdminDetailRow(
                  label: l10n.adminMetricRegistered,
                  value: '${match.registrationCount}',
                ),
                AdminDetailRow(
                  label: l10n.adminMetricStartingPlayers,
                  value: match.startingPlayers == null
                      ? adminUnknownValue
                      : '${match.startingPlayers}',
                  unknown: match.startingPlayers == null,
                ),
              ]),

              // The result, only where there is one. A match that has been
              // played but not written up has no score, and an empty card
              // saying so would be a card about nothing.
              if (match.hasScore) ...[
                SectionHeading(title: l10n.adminMetricResults),
                SectionCard(children: [
                  AdminDetailRow(
                    label: l10n.adminMetricScore,
                    // Isolated left-to-right: the score runs A-then-B in every
                    // language, and an Arabic layout would otherwise reverse
                    // the two and swap the sides.
                    value: '\u2066${match.scoreA} - ${match.scoreB}\u2069',
                  ),
                  if (match.mvpName != null)
                    AdminDetailRow(
                      label: l10n.mvpLabel,
                      value: match.mvpName!,
                    ),
                  if (match.resultCreatedAt != null)
                    AdminDetailRow(
                      label: l10n.adminMetricResultRecorded,
                      value: formatMatchDay(context, match.resultCreatedAt!),
                    ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }
}
