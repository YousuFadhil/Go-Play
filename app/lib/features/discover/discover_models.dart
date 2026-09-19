// Domain Models for what a visitor sees before they sign in (OP-3).
//
// These are deliberately *not* `Community` and `Match`. Those two carry things a
// guest is not given — a community's join code, a match's creator, the
// registration roster — and widening them with nullable fields would leave every
// reader guessing which of them are populated on which screen. A separate pair
// of models says it once, in the type: this is the public face of a community
// and of a match, and there is nothing else in it.
//
// Both are read-only. Nothing here has a write path, because browsing is the
// only thing a guest does.

/// A community as the Discover page shows it.
///
/// Every active community appears, whatever its join policy — being listed is
/// not being joinable, and joining is still refused without the code where the
/// policy requires one.
class PublicCommunity {
  const PublicCommunity({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.upcomingMatchCount,
    this.description,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String? description;

  /// The community's picture, when it has one.
  ///
  /// Public, and deliberately: a community's logo is its identity, and the
  /// pages a visitor sees before signing in are exactly where an identity has
  /// the most work to do. The object it names lives in a public bucket, so this
  /// exposes nothing that having the address did not already.
  ///
  /// Null is the initials crest, here as everywhere else.
  final String? logoUrl;

  /// How many players are in it. An aggregate, never the roster: who they are
  /// is not a guest's to read.
  final int memberCount;

  /// Matches that have not ended yet. Zero is an ordinary answer — a community
  /// with nothing scheduled is still worth showing.
  final int upcomingMatchCount;

  /// The letters shown when a community has no picture.
  ///
  /// There is no logo column in the schema and this sprint adds none, so the
  /// initials *are* the logo rather than a placeholder standing in for one.
  /// Two words at most: "Muscat United" reads as MU, and a one-word name gives
  /// its first letter.
  String get initials {
    final words = [
      for (final word in name.trim().split(RegExp(r'\s+')))
        if (word.isNotEmpty) word,
    ];
    if (words.isEmpty) return '';
    return words.take(2).map(_initialOf).join();
  }

  /// The letter that stands for one word.
  ///
  /// Arabic's definite article is written joined to the word it defines, so
  /// "البحر" and "الشمال" both begin with `ال` and both used to reduce to the
  /// same mark — which made every second community on the page look identical
  /// and defeated the point of having a mark at all. Skipping the article gives
  /// ب and ش, the letters a reader would actually name the club by.
  ///
  /// Deliberately the whole of the rule. `ال` is one prefix among several in
  /// Arabic, and this is not a morphological parser: it is the one case that
  /// occurs constantly in club names, handled literally. Anything more would be
  /// guessing at grammar in a getter that draws a circle.
  ///
  /// The article is skipped only when something follows it, so a community
  /// actually called "ال" keeps its own letters rather than reducing to
  /// nothing.
  static String _initialOf(String word) {
    const arabicDefiniteArticle = 'ال';
    final stem = word.startsWith(arabicDefiniteArticle) &&
            word.length > arabicDefiniteArticle.length
        ? word.substring(arabicDefiniteArticle.length)
        : word;
    // Arabic has no letter case, so this is a no-op there and does the work it
    // always did for Latin names.
    return stem.substring(0, 1).toUpperCase();
  }
}

/// A match as the Discover page shows it: when, where, whose, and how many
/// places are left.
class PublicMatch {
  const PublicMatch({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.startingPlayers,
    required this.openSlots,
    this.title,
  });

  final String id;
  final String communityId;
  final String communityName;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  /// The playing capacity, which is what [openSlots] counts down from. Not the
  /// maximum registration: that is the starting players plus the global reserve
  /// allowance (DD-06), and offering it as the number of seats would promise a
  /// six-a-side match twelve places.
  final int startingPlayers;

  /// Places still open. Zero means the starting side is complete — registering
  /// then joins the reserve queue, which is the match screen's business to
  /// explain, not this card's.
  final int openSlots;

  final String? title;

  /// What to show as the headline: the title if it has one, else the location.
  /// The same rule [Match.displayName] uses, so a match reads the same way
  /// before and after signing in.
  String get displayName =>
      (title != null && title!.isNotEmpty) ? title! : location;

  /// True once every starting place is taken.
  bool get isFull => openSlots == 0;
}

/// One match, as a `/match/{id}` link opens it for a visitor.
///
/// One completed match in a public list of results.
///
/// **The completed shape `public_match_detail` already returns, as a row in a
/// list** (`public_recent_results`, migration `0081`) — so a result a visitor
/// could already open by id is one they can now also find. What is on it is
/// what a result card shows: whose community, which match, when and where, the
/// score, and the best player's display name. There is no lineup here, no
/// registration, no places and no identifier for anybody: the roster of a
/// completed match is [PublicCompletedMatch]'s, one read further in, and a
/// Professional Guest is never named by one of these.
class PublicResult {
  const PublicResult({
    required this.matchId,
    required this.communityId,
    required this.communityName,
    required this.startAt,
    required this.teamAScore,
    required this.teamBScore,
    this.communityLogoUrl,
    this.title,
    this.location,
    this.mvpDisplayName,
    this.mvpAvatarUrl,
  });

  final String matchId;
  final String communityId;
  final String communityName;
  final String? communityLogoUrl;
  final String? title;
  final String? location;
  final DateTime startAt;

  /// Both scores, always: a match with no recorded result is not published as
  /// a result at all.
  final int teamAScore;
  final int teamBScore;

  /// The best player's name, where the result named one. Never an id.
  final String? mvpDisplayName;

  /// Their picture, resolved from the `mvp_avatar_path` the public contract
  /// already publishes (migration `0081`). A path is storage knowledge; the
  /// adapter turns it into an address, exactly as it does for the lineup on a
  /// public match page.
  final String? mvpAvatarUrl;

  bool get isDraw => teamAScore == teamBScore;

  /// Whether Team A won. Meaningless on a draw, which [isDraw] answers first.
  bool get teamAWon => teamAScore > teamBScore;
}

/// **Two kinds, and the fields of one are not on the other.** An upcoming match
/// has places and no score; a completed match has a score and a lineup and no
/// places. A sealed pair makes that a fact about the type, so no screen can
/// read a score off a match that has not been played.
///
/// What either carries is the whole of `public_match_detail` and
/// `public_match_lineup` (migration `0079`), both of which answer only for a
/// match in an active community.
sealed class PublicMatchDetail {
  const PublicMatchDetail();
}

/// A match that has not finished: what public discovery already publishes.
final class PublicUpcomingMatch extends PublicMatchDetail {
  const PublicUpcomingMatch({required this.match, this.communityLogoUrl});

  final PublicMatch match;
  final String? communityLogoUrl;
}

/// A match that has been played, with the result information a shared result
/// card already shows.
final class PublicCompletedMatch extends PublicMatchDetail {
  const PublicCompletedMatch({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.startAt,
    required this.endAt,
    required this.hasResult,
    required this.lineup,
    this.communityLogoUrl,
    this.title,
    this.location,
    this.teamAScore,
    this.teamBScore,
    this.mvpDisplayName,
    this.mvpAvatarUrl,
  });

  final String id;
  final String communityId;
  final String communityName;
  final String? communityLogoUrl;
  final String? title;
  final String? location;
  final DateTime startAt;
  final DateTime endAt;

  /// False for a match that ended with no result recorded yet. Its scores and
  /// MVP are then null, which is the honest answer rather than a nil-nil.
  final bool hasResult;
  final int? teamAScore;
  final int? teamBScore;
  final String? mvpDisplayName;
  final String? mvpAvatarUrl;

  /// Empty when no lineup was stored.
  final List<PublicLineupEntry> lineup;
}

/// One participant in a completed match's public lineup.
class PublicLineupEntry {
  const PublicLineupEntry({
    required this.team,
    required this.displayName,
    required this.isProfessionalGuest,
    required this.goals,
    required this.isMvp,
    this.assignedPosition,
    this.avatarUrl,
    this.playerId,
  });

  /// `A` or `B`, as the lineup stores it.
  final String team;
  final String? assignedPosition;
  final String displayName;
  final String? avatarUrl;
  final bool isProfessionalGuest;
  final int goals;
  final bool isMvp;

  /// The registered player's id, present **only** when their public profile is
  /// available — so a name leads to `/player/{id}` exactly when that page would
  /// open. Null for a Professional Guest and for a player whose profile is not
  /// available; the database decides both.
  final String? playerId;
}
