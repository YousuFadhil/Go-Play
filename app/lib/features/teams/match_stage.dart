import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and it
// would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/l10n.dart';

/// The approved Teams and share-card presentation modes.
///
/// Phone and share geometry are intentionally independent. In particular, a
/// share card is not a phone layout multiplied to 1080 pixels.
enum MatchStagePresentation { phone, shareBeforeResult, shareResult }

/// The final semantic palette for the Teams feature.
abstract final class MatchStage {
  static const ground = Color(0xFF05281D);
  static const section = Color(0xFF0B3A29);
  static const pitchDark = Color(0xFF237A3A);
  static const pitchLight = Color(0xFF3B9B43);
  static const pitchLine = Color(0x80FFFFFF);
  static const accent = Color(0xFF45DF7C);
  static const ink = Color(0xFFF5F8F6);
  static const inkMuted = Color(0xFFAEC0B5);
  static const rating = Color(0xB3082D22);
  static const star = Color(0xFFF5C451);
  static const goal = Color(0xFFFF6B57);
  static const wonFill = Color(0x2645DF7C);
  static const restFill = Color(0x59082D22);
}

/// Community, match and date, followed by a result strip only when a result
/// exists. The match-information block keeps its approved fixed height rather
/// than growing to consume spare space.
class MatchStageHeader extends StatelessWidget {
  const MatchStageHeader({
    super.key,
    required this.community,
    required this.title,
    required this.playedAt,
    this.teamAScore,
    this.teamBScore,
    this.presentation = MatchStagePresentation.phone,
  });

  final String? community;
  final String? title;
  final DateTime? playedAt;
  final int? teamAScore;
  final int? teamBScore;
  final MatchStagePresentation presentation;

  bool get hasResult => teamAScore != null && teamBScore != null;

  TeamId? get winner {
    if (!hasResult || teamAScore == teamBScore) return null;
    return teamAScore! > teamBScore! ? TeamId.a : TeamId.b;
  }

  bool get _isPhone => presentation == MatchStagePresentation.phone;

  double get _matchInfoHeight => switch (presentation) {
        MatchStagePresentation.phone => 102,
        MatchStagePresentation.shareBeforeResult => 170,
        MatchStagePresentation.shareResult => 150,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _matchInfoHeight,
          child: _MatchInfo(
            community: community,
            title: title,
            playedAt: playedAt,
            presentation: presentation,
          ),
        ),
        if (hasResult) ...[
          if (_isPhone) const SizedBox(height: 8),
          _ScoreStrip(
            teamA: l10n.teamAName,
            teamB: l10n.teamBName,
            scoreA: teamAScore!,
            scoreB: teamBScore!,
            winner: winner,
            winnerLabel: l10n.matchResultWinnerLabel,
            presentation: presentation,
          ),
        ],
      ],
    );
  }
}

class _MatchInfo extends StatelessWidget {
  const _MatchInfo({
    required this.community,
    required this.title,
    required this.playedAt,
    required this.presentation,
  });

  final String? community;
  final String? title;
  final DateTime? playedAt;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final phone = presentation == MatchStagePresentation.phone;
    final resultShare = presentation == MatchStagePresentation.shareResult;

    final communitySize = phone ? 13.0 : 28.0;
    final titleSize = phone
        ? 23.0
        : resultShare
            ? 54.0
            : 58.0;
    final dateSize = phone ? 13.0 : 27.0;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (community != null)
            Text(
              community!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MatchStage.inkMuted,
                fontSize: communitySize,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          if (title != null) ...[
            SizedBox(height: phone ? 5 : 8),
            Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MatchStage.ink,
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
          ],
          if (playedAt != null) ...[
            SizedBox(height: phone ? 5 : 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: phone ? 14 : 28,
                  color: MatchStage.inkMuted,
                ),
                SizedBox(width: phone ? 6 : 12),
                Flexible(
                  child: Text(
                    DateFormat.yMMMMEEEEd(locale).format(playedAt!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MatchStage.inkMuted,
                      fontSize: dateSize,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip({
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.winnerLabel,
    required this.presentation,
  });

  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final String winnerLabel;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final phone = presentation == MatchStagePresentation.phone;

    return SizedBox(
      height: phone ? 58 : 104,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(phone ? 14 : 22),
          border: Border.all(
            color: MatchStage.accent.withValues(alpha: 0.32),
            width: phone ? 1 : 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(phone ? 13 : 20),
          child: Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StripSide(
                  label: teamA,
                  won: winner == TeamId.a,
                  winnerLabel: winnerLabel,
                  presentation: presentation,
                ),
              ),
              _StripScore(
                scoreA: scoreA,
                scoreB: scoreB,
                winner: winner,
                presentation: presentation,
              ),
              Expanded(
                child: _StripSide(
                  label: teamB,
                  won: winner == TeamId.b,
                  winnerLabel: winnerLabel,
                  presentation: presentation,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripSide extends StatelessWidget {
  const _StripSide({
    required this.label,
    required this.won,
    required this.winnerLabel,
    required this.presentation,
  });

  final String label;
  final bool won;
  final String winnerLabel;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final phone = presentation == MatchStagePresentation.phone;

    return ColoredBox(
      color: won ? MatchStage.wonFill : MatchStage.restFill,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: phone ? 7 : 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (won) ...[
              _WinnerChip(
                label: winnerLabel,
                presentation: presentation,
              ),
              SizedBox(height: phone ? 2 : 5),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: phone ? 17 : 32,
                  color: won ? MatchStage.accent : MatchStage.inkMuted,
                ),
                SizedBox(width: phone ? 5 : 12),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MatchStage.ink,
                      fontSize: phone ? 15 : 30,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StripScore extends StatelessWidget {
  const _StripScore({
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.presentation,
  });

  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final phone = presentation == MatchStagePresentation.phone;

    Widget numeral(int value, bool won) => Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: won ? MatchStage.accent : MatchStage.ink,
            fontSize: phone ? 28 : 58,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: -1,
          ),
        );

    return ColoredBox(
      color: MatchStage.restFill,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: phone ? 10 : 24),
        child: Center(
          child: Row(
            textDirection: TextDirection.ltr,
            mainAxisSize: MainAxisSize.min,
            children: [
              numeral(scoreA, winner == TeamId.a),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: phone ? 6 : 14),
                child: Text(
                  '–',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: MatchStage.inkMuted,
                    fontSize: phone ? 20 : 42,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
              ),
              numeral(scoreB, winner == TeamId.b),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinnerChip extends StatelessWidget {
  const _WinnerChip({required this.label, required this.presentation});

  final String label;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final phone = presentation == MatchStagePresentation.phone;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: phone ? 6 : 13,
        vertical: phone ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: MatchStage.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MatchStage.accent.withValues(alpha: 0.45),
          width: phone ? 1 : 2,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: MatchStage.accent,
          fontSize: phone ? 8 : 18,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// A team heading and pitch on the final approved dark team-card surface.
class MatchStageSection extends StatelessWidget {
  const MatchStageSection({
    super.key,
    required this.title,
    required this.won,
    required this.child,
    this.presentation = MatchStagePresentation.phone,
  });

  final String title;
  final bool won;
  final Widget child;
  final MatchStagePresentation presentation;

  bool get _isPhone => presentation == MatchStagePresentation.phone;
  bool get _isShareBefore =>
      presentation == MatchStagePresentation.shareBeforeResult;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: MatchStage.section,
        borderRadius: BorderRadius.circular(_isPhone ? 18 : 28),
        border: Border.all(
          color: MatchStage.accent.withValues(alpha: won ? 0.80 : 0.32),
          width: _isPhone ? 1 : 2,
        ),
      ),
      padding: _isPhone
          ? const EdgeInsets.all(7)
          : EdgeInsets.fromLTRB(
              23,
              _isShareBefore ? 16 : 18,
              23,
              _isShareBefore ? 16 : 18,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _isPhone
                ? 28
                : _isShareBefore
                    ? 56
                    : 48,
            child: _TeamHeading(
              title: title,
              won: won,
              presentation: presentation,
            ),
          ),
          SizedBox(
              height: _isPhone
                  ? 10
                  : _isShareBefore
                      ? 18
                      : 12),
          child,
        ],
      ),
    );

    if (_isPhone) return content;
    return SizedBox(height: _isShareBefore ? 720 : 680, child: content);
  }
}

class _TeamHeading extends StatelessWidget {
  const _TeamHeading({
    required this.title,
    required this.won,
    required this.presentation,
  });

  final String title;
  final bool won;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final phone = presentation == MatchStagePresentation.phone;

    if (phone) {
      return Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MatchStage.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          if (won) const _WinnerTrophy(size: 22),
        ],
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _HeadingRule(),
            const SizedBox(width: 20),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MatchStage.ink,
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 20),
            const _HeadingRule(),
          ],
        ),
        if (won) const Positioned(left: 0, child: _WinnerTrophy(size: 40)),
      ],
    );
  }
}

class _HeadingRule extends StatelessWidget {
  const _HeadingRule();

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 4,
        decoration: BoxDecoration(
          color: MatchStage.accent,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}

class _WinnerTrophy extends StatelessWidget {
  const _WinnerTrophy({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MatchStage.accent.withValues(alpha: 0.12),
        ),
        child: Icon(
          Icons.emoji_events,
          size: size * 0.58,
          color: MatchStage.accent,
        ),
      );
}
