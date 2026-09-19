import 'package:flutter/material.dart';

import '../results/result_card.dart';
import 'football_models.dart';

/// A completed match, as a line in a member's list.
///
/// **This is now an adapter and not a composition.** What it draws is
/// [ResultCard] — the one card this product draws a played match with — and all
/// this type does is turn the authenticated read model into the presentation
/// model that card takes. The public Discover card does the same from its own
/// contract, which is how a visitor and a member came to be looking at the same
/// football in the same shape again.
///
/// The two read models stay apart. [CompletedMatch] is a member's read and is
/// not mentioned anywhere inside [ResultCard]; nothing here reaches for a
/// public field and nothing public reaches for one of these.
///
/// It shows what the read model already knows and computes nothing. In
/// particular it does **not** total the scorers: attributed goals and the
/// recorded score are two different facts, and a card that added the first up
/// and presented it as the second would be inventing one.
class FootballResultCard extends StatelessWidget {
  const FootballResultCard({
    super.key,
    required this.match,
    required this.onOpen,
    this.showCommunityName = true,
  });

  final CompletedMatch match;
  final VoidCallback onOpen;

  /// False on a community's own page, where every match belongs to the
  /// community already named at the top of the screen.
  final bool showCommunityName;

  /// The authenticated result, as the shared card takes it.
  ///
  /// A member's feed knows when the match finished, so the date line is the
  /// range rather than the day alone. It carries no community picture — that
  /// field is not on this read — so the crest falls back to the initials every
  /// community without a logo is drawn with.
  ResultCardData get data => ResultCardData(
        title: match.displayName,
        communityName: match.communityName,
        startAt: match.startAt,
        endAt: match.endAt,
        teamAScore: match.hasResult ? match.teamAScore : null,
        teamBScore: match.hasResult ? match.teamBScore : null,
        mvpName: match.mvp?.displayName,
        mvpAvatarUrl: match.mvp?.avatarUrl,
        mvpIsProfessionalGuest:
            match.mvp?.type == ParticipantType.professionalGuest,
      );

  @override
  Widget build(BuildContext context) => ResultCard(
        data: data,
        onOpen: onOpen,
        showCommunityName: showCommunityName,
      );
}
