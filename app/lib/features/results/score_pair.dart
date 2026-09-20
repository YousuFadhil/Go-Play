import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/tokens.dart';

/// A recorded score, with each number bound to the team that scored it.
///
/// **Not "2 - 3".** A bare pair of numbers is only unambiguous if the reader
/// already knows which side is written first, and on an Arabic page the answer
/// looks like it should be the other way round. So each score is drawn with its
/// team's name under it, as a pair of blocks laid out by the ambient direction
/// — Team A leads in English and in Arabic alike, because it leads in the
/// reading order rather than on the left.
///
/// One widget because two surfaces show the same fact: the public Latest
/// Results a visitor reads, and the football feed a member reads. A second copy
/// is how the two would come to disagree about which number is whose.
class ScorePair extends StatelessWidget {
  const ScorePair({
    super.key,
    required this.teamAScore,
    required this.teamBScore,
  });

  final int teamAScore;
  final int teamBScore;

  bool get _isDraw => teamAScore == teamBScore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm - 2,
      ),
      decoration: BoxDecoration(
        color: GoColors.statusOpenBg,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Side(
            label: l10n.teamAName,
            score: teamAScore,
            // The winner's figure carries the weight. A draw gives neither it,
            // which is the honest reading of a drawn match.
            won: !_isDraw && teamAScore > teamBScore,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Container(
              width: 1,
              height: 22,
              color: GoColors.primaryDeep.withValues(alpha: 0.18),
            ),
          ),
          _Side(
            label: l10n.teamBName,
            score: teamBScore,
            won: !_isDraw && teamBScore > teamAScore,
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.score, required this.won});

  final String label;
  final int score;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          // A number reads left to right in both languages; what mirrors is
          // which block comes first, and the Row above does that.
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 18,
            height: 1,
            fontWeight: won ? FontWeight.w800 : FontWeight.w600,
            color: GoColors.primaryDeep,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w600,
              color: GoColors.primaryDeep.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
