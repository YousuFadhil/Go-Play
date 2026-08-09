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
  });

  final String id;
  final String name;
  final String? description;

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
