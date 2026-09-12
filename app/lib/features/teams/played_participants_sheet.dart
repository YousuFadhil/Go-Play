import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../profile/player_identity.dart';
import 'team_models.dart';

/// Correcting who actually played a completed match, for several players at
/// once.
///
/// **Why a batch and not a queue of single edits.** Every correction to a
/// played match reverses the ratings and counters the match produced and
/// reapplies them. Adding four players one at a time would do that four times,
/// over lineups nobody ever played, and a refusal on the fourth would leave
/// the first three standing. The organizer's intent is one statement — "these
/// people played, on these sides, in these positions" — so it leaves here as
/// one list and reaches the database as one transaction (migration `0074`).
///
/// **The position is asked for and never guessed.** A profile's position is
/// shown beside each name as a reminder of who the player usually is, and it is
/// nothing more than that: where somebody played on the day is historical
/// evidence, and filling it in from their profile would be the product
/// inventing a fact about a match it did not watch.
///
/// Professional Guests are absent by construction — [load] supplies community
/// members — because a guest is corrected by the guest operations, which keep
/// their own rules about seats and lineup rows.
class PlayedParticipantsSheet extends StatefulWidget {
  const PlayedParticipantsSheet({
    super.key,
    required this.load,
    required this.positionLabel,
  });

  /// The community members who are not already in the factual lineup.
  ///
  /// A closure rather than a list so the sheet owns its own loading and retry
  /// states, as the roster screen's picker does, and so the Teams screen does
  /// not read a list almost nobody asks for on every visit.
  final Future<List<CommunityMember>> Function() load;

  /// The localized word for a position code, which lives with the caller.
  final String Function(String position) positionLabel;

  @override
  State<PlayedParticipantsSheet> createState() =>
      _PlayedParticipantsSheetState();
}

class _PlayedParticipantsSheetState extends State<PlayedParticipantsSheet> {
  late Future<List<CommunityMember>> _future = widget.load();

  /// What has been said about each chosen player, by user id.
  ///
  /// Keyed by id so a selection survives a reload of the list, and ordered by
  /// the list rather than by the order rows were tapped, so the batch is sent
  /// in the order the organizer sees it.
  final _chosen = <String, _PlayedAssignment>{};

  void _toggle(String userId) => setState(() {
        if (_chosen.remove(userId) == null) {
          _chosen[userId] = _PlayedAssignment();
        }
      });

  void _retry() => setState(() {
        _future = widget.load();
      });

  /// Every chosen player has a side and a position, and at least one player is
  /// chosen.
  ///
  /// The empty case is not merely pointless: a batch with nothing in it would
  /// still detach and reapply the match's ratings, writing a fresh audit trail
  /// for no correction, so `0074` refuses it. The button is disabled rather
  /// than letting the organizer find that out from the server.
  bool get _complete =>
      _chosen.isNotEmpty &&
      _chosen.values.every((a) => a.team != null && a.position != null);

  List<CompletedPlayerCorrection> get _corrections => [
        for (final entry in _chosen.entries)
          CompletedPlayerCorrection.played(
            entry.key,
            team: entry.value.team!,
            position: entry.value.position!,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  Text(l10n.editPlayedParticipantsAction,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    l10n.playedParticipantsHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<CommunityMember>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LoadingState();
                  }
                  if (snapshot.hasError) {
                    return ErrorState(onRetry: _retry);
                  }

                  final members = snapshot.data ?? const <CommunityMember>[];
                  if (members.isEmpty) {
                    return EmptyState(
                      icon: Icons.person_outline,
                      message: l10n.addPlayedPlayerNobodyAvailable,
                    );
                  }

                  return ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final assignment = _chosen[member.userId];
                      return _CandidateRow(
                        member: member,
                        assignment: assignment,
                        positionLabel: widget.positionLabel,
                        onToggle: () => _toggle(member.userId),
                        onTeam: (team) =>
                            setState(() => assignment?.team = team),
                        onPosition: (position) =>
                            setState(() => assignment?.position = position),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('savePlayedParticipantsButton'),
                    onPressed: _complete
                        ? () => Navigator.of(context).pop(_corrections)
                        : null,
                    child: Text(
                      l10n.savePlayedParticipantsButton(_chosen.length),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One candidate, and what is being said about them.
///
/// Unchosen, the row is the picker row the roster sheet already uses: a face, a
/// name, the position the profile claims. Chosen, it grows the two questions
/// only a played match can answer — which side, and where.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.member,
    required this.assignment,
    required this.positionLabel,
    required this.onToggle,
    required this.onTeam,
    required this.onPosition,
  });

  final CommunityMember member;
  final _PlayedAssignment? assignment;
  final String Function(String position) positionLabel;
  final VoidCallback onToggle;
  final ValueChanged<TeamId> onTeam;
  final ValueChanged<Position> onPosition;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final chosen = assignment != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          // The row's tap is the selection. A picker that opened a profile
          // instead of choosing somebody would be a picker that does not pick.
          leading: PlayerAvatar(
            avatarUrl: member.avatarUrl,
            fullName: member.fullName,
          ),
          title: Text(member.fullName),
          subtitle: Text(positionLabel(member.position)),
          selected: chosen,
          trailing: Checkbox(
            key: Key('playedPick_${member.userId}'),
            value: chosen,
            onChanged: (_) => onToggle(),
          ),
          onTap: onToggle,
        ),
        if (chosen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.chooseTeamTitle, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (team, label) in [
                      (TeamId.a, l10n.teamAName),
                      (TeamId.b, l10n.teamBName),
                    ])
                      ChoiceChip(
                        key: Key('playedTeam_${member.userId}_${team.name}'),
                        label: Text(label),
                        selected: assignment!.team == team,
                        onSelected: (_) => onTeam(team),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.choosePositionTitle,
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final position in Position.values)
                      ChoiceChip(
                        key: Key(
                            'playedPosition_${member.userId}_${position.code}'),
                        label: Text(positionLabel(position.code)),
                        selected: assignment!.position == position,
                        onSelected: (_) => onPosition(position),
                      ),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// The side and the position a chosen player is being recorded in. Both start
/// unanswered, which is what keeps Save disabled until the organizer has said.
class _PlayedAssignment {
  TeamId? team;
  Position? position;
}
