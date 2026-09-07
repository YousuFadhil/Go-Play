import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../results/match_result_card.dart' show ShareCardSignature;
import '../teams/match_stage.dart';
import '../teams/pitch_view.dart';
import '../teams/team_models.dart';
import 'team_of_period_models.dart';

/// One awarded player, as the picture needs them.
///
/// Resolved on the screen and passed in whole. Everything the card can draw is
/// here and nothing else is reachable: there is no candidate, no repository and
/// no way for the template to ask a question at compose time.
@immutable
class TeamOfPeriodSharePlayer {
  const TeamOfPeriodSharePlayer({
    required this.userId,
    required this.name,
    required this.assignedPosition,
    required this.currentOverallRating,
    this.avatarUrl,
    this.goals = 0,
    this.hasMvp = false,
  });

  final String userId;

  /// What the screen calls them, including the neutral fallback where their
  /// profile could not be read. The picture and the screen must agree.
  final String name;

  final Position assignedPosition;

  /// The player's rating **today**, as every other Go Play player card shows
  /// it. Not a reconstruction of what they held during the period: no such
  /// figure exists, and inventing one would be a number nobody earned.
  final double currentOverallRating;

  final String? avatarUrl;

  /// Goals **in the award period**, not a career total.
  final int goals;
  final bool hasMvp;
}

/// Everything the Team of Period card draws, resolved before it is drawn.
///
/// **The rating is the player's current global one**, drawn the way every Go
/// Play player card draws it — approved by the Product Owner so that a shared
/// team reads as the same football the app draws everywhere else. It is not a
/// reconstruction of what they held during the period, and nothing is
/// substituted for it: not the Period Form Score, not a rating at period end,
/// because no such user-facing figure exists.
///
/// Worth knowing when reading a card months later: a PNG outlives the moment
/// it was made, so the number on it is the rating that player held when the
/// picture was taken rather than a fact about the award period.
///
/// **No selection evidence, though.** Participation, win rate, points per game
/// and the Period Form Score belong to the interactive screen, where a reader
/// can ask what they mean.
@immutable
class TeamOfPeriodCardData {
  const TeamOfPeriodCardData({
    required this.communityName,
    required this.kind,
    required this.periodStart,
    required this.periodEnd,
    required this.players,
    this.communityLogoUrl,
  });

  /// The snapshot the reader is looking at, turned into a picture of itself.
  ///
  /// Built from an award and the identities already loaded beside it — never
  /// from a fresh read. The order is the award's own, so the card and the
  /// screen put the same players in the same places.
  factory TeamOfPeriodCardData.of(
    TeamOfPeriod award, {
    required String communityName,
    required Map<String, TeamOfPeriodPlayerIdentity> identities,
    required String Function(String userId) nameOf,
    String? communityLogoUrl,
  }) =>
      TeamOfPeriodCardData(
        communityName: communityName,
        communityLogoUrl: communityLogoUrl,
        kind: award.window.kind,
        periodStart: award.window.periodStart,
        periodEnd: award.window.periodEnd,
        players: [
          for (final entry in award.selected)
            TeamOfPeriodSharePlayer(
              userId: entry.userId,
              name: nameOf(entry.userId),
              assignedPosition: entry.assignedPosition,
              avatarUrl: identities[entry.userId]?.avatarUrl,
              currentOverallRating: entry.candidate.currentOverallRating,
              goals: entry.candidate.goals,
              hasMvp: entry.candidate.mvpCount > 0,
            ),
        ],
      );

  final String communityName;

  /// Null is the ordinary case, not an unfinished one: the crest shows the
  /// community's letters, exactly as it does everywhere else in the app.
  final String? communityLogoUrl;

  final TeamOfPeriodKind kind;

  /// The period the database resolved. Formatted here and never recomputed:
  /// `periodEnd` is exclusive, and the range is drawn to the day before it.
  final DateTime periodStart;
  final DateTime periodEnd;

  final List<TeamOfPeriodSharePlayer> players;

  /// The faces to load before the card is composed. The crest is fetched
  /// alongside them.
  List<String> get imageUrls => [
        for (final player in players)
          if (player.avatarUrl != null) player.avatarUrl!,
        if (communityLogoUrl != null && communityLogoUrl!.isNotEmpty)
          communityLogoUrl!,
      ];
}

/// The award, as a picture.
///
/// **The same family as Share Result, with one team instead of two.** The
/// ground, the gradient, the two faint balls, the pitch and the signature are
/// that card's, because the application already draws football well and a
/// picture of it that looks like something else is a picture of somebody
/// else's product. What differs is the composition, and only because the
/// subject differs: an award has one side, no opponent and no score, so the
/// room the second pitch and the score strip used goes to the community, the
/// period and a larger pitch.
///
/// **One hierarchy.** Who and when at the top, the football in the middle, the
/// signature at the foot. No statistics table, no roster list, no trophy.
class TeamOfPeriodCard extends StatelessWidget {
  const TeamOfPeriodCard({super.key, required this.data});

  final TeamOfPeriodCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // The award title and the resolved period, from the window the database
    // gave. A card that said only "Weekly" would be undatable the moment it
    // left the phone.
    final title = switch (data.kind) {
      TeamOfPeriodKind.weekly => l10n.teamOfPeriodWeekHeading,
      TeamOfPeriodKind.monthly => l10n.teamOfPeriodMonthHeading,
    };
    final period = switch (data.kind) {
      TeamOfPeriodKind.weekly =>
        formatAwardWeek(context, data.periodStart, data.periodEnd),
      TeamOfPeriodKind.monthly => formatAwardMonth(context, data.periodStart),
    };

    final assignments = [
      for (final player in data.players)
        TeamAssignment(
          userId: player.userId,
          team: TeamId.a,
          assignedPosition: player.assignedPosition,
          basis: null,
        ),
    ];
    final byId = {for (final player in data.players) player.userId: player};

    return LayoutBuilder(builder: (context, constraints) {
      final sx = constraints.maxWidth / MatchStage.referenceWidth;
      final sy = constraints.maxHeight / MatchStage.referenceHeight;

      return DecoratedBox(
        key: const ValueKey('team-of-period-card-background'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF063126), MatchStage.ground],
          ),
        ),
        child: Stack(
          children: [
            // The same restrained motif Share Result carries, at the same
            // weights, so the two read as one family at a glance.
            Positioned(
              key: const ValueKey('share-header-ball-left'),
              top: -70 * sy,
              left: -115 * sx,
              child: Icon(
                Icons.sports_soccer,
                size: 255 * sx,
                color: Colors.white.withValues(alpha: .035),
              ),
            ),
            Positioned(
              key: const ValueKey('share-header-ball-right'),
              top: -95 * sy,
              right: -105 * sx,
              child: Icon(
                Icons.sports_soccer,
                size: 405 * sx,
                color: Colors.white.withValues(alpha: .045),
              ),
            ),
            Positioned(
              left: 60 * sx,
              top: 78 * sy,
              width: MatchStage.referenceWidth * sx - 120 * sx,
              child: _Heading(
                data: data,
                title: title,
                period: period,
                sx: sx,
                sy: sy,
              ),
            ),
            // One pitch, and the subject of the card. Bounded by the width, so
            // it is as large as a 9:16 card allows, and centred in the room
            // between the heading and the signature.
            // The subject of the card, and now sized as one.
            //
            // It was laid out at the width Share Result gives each of its two
            // pitches and then centred in the room left over, which left broad
            // bands of empty ground above and below it -- a picture of a pitch
            // rather than a picture of a team. The card is full-bleed here and
            // the heading sits closer to the top, so the pitch takes the width
            // it can and the height follows from its own proportion. Nothing
            // about the pitch's internals changed: this is the box it is given.
            Positioned(
              key: const ValueKey('team-of-period-card-pitch'),
              left: 0,
              top: 590 * sy,
              width: MatchStage.referenceWidth * sx,
              height: 604 * sy,
              child: PitchView(
                assignments: assignments,
                // The award's own rows. No formation, no borrowing, no
                // minimum line, and an unusual shape stays unusual.
                layout: PitchLayoutMode.exactAssignedPositions,
                nameOf: (userId) => byId[userId]?.name ?? '',
                avatarUrlOf: (userId) => byId[userId]?.avatarUrl,
                // The same rating badge the Teams and Match screens draw,
                // from the snapshot already loaded. Current and global, as the
                // class comment on the data explains.
                ratingOf: (userId) => byId[userId]?.currentOverallRating,
                goalsOf: (userId) => byId[userId]?.goals ?? 0,
                isMvpOf: (userId) => byId[userId]?.hasMvp ?? false,
                presentation: PitchPresentation.shareResult,
                // Team A is the non-mirrored orientation. There is no second
                // side to face, and no label saying so.
                team: TeamId.a,
                pitchKey: const ValueKey('team-of-period-pitch'),
              ),
            ),
            Positioned(
              left: 0,
              top: 1538 * sy,
              width: constraints.maxWidth,
              height: 134 * sy,
              child: const ShareCardSignature(),
            ),
          ],
        ),
      );
    });
  }
}

/// Crest, community, award, period — in that order, and none of them louder
/// than the pitch below.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.data,
    required this.title,
    required this.period,
    required this.sx,
    required this.sy,
  });

  final TeamOfPeriodCardData data;
  final String title;
  final String period;
  final double sx;
  final double sy;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CommunityCrest(
            key: const ValueKey('team-of-period-card-crest'),
            name: data.communityName,
            logoUrl: data.communityLogoUrl,
            size: 150 * sx,
            // The translucent treatment, because this crest sits on the green.
            onHero: true,
          ),
          SizedBox(height: 34 * sy),
          Text(
            data.communityName,
            key: const ValueKey('team-of-period-card-community'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MatchStage.inkMuted,
              fontSize: 44 * sx,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
          SizedBox(height: 26 * sy),
          Text(
            title,
            key: const ValueKey('team-of-period-card-title'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MatchStage.ink,
              fontSize: 68 * sx,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          SizedBox(height: 18 * sy),
          Text(
            period,
            key: const ValueKey('team-of-period-card-period'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MatchStage.accent,
              fontSize: 42 * sx,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}
