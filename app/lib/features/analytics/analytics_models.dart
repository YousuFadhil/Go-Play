/// The eleven events the product records, and the only eleven it records.
///
/// **A closed enum, not a string.** The wire name is carried by the value
/// rather than written at the call site, so a screen cannot invent an
/// twelfth event by typing one, cannot misspell an approved one, and cannot
/// drift from the database — where the same ten names are a CHECK constraint on
/// `product_events.event_name` and are restated in `record_product_event`. A
/// name that is not on this list is refused by the database as
/// `INVALID_ANALYTICS_EVENT`; this enum is what makes that refusal unreachable
/// from ordinary code.
///
/// [wireName] must match the CHECK constraint exactly — migration `0067` for
/// the first ten, migration `0079` for the eleventh, which also restates the
/// whole list. Static tests assert every one of them against the migration
/// text.
enum ProductEvent {
  /// An authenticated, active reader entered the application. Once per session
  /// — not per rebuild, not per resume. See `ProductAnalytics.trackSession`.
  sessionStarted('session_started'),

  /// A community's own screen was opened and its community actually loaded.
  communityViewed('community_viewed'),

  /// A community was created, and the creation succeeded.
  communityCreated('community_created'),

  /// A community was joined, and the join succeeded. Already being a member is
  /// not a join and is not recorded.
  communityJoined('community_joined'),

  /// A match's own screen was opened and its match actually loaded.
  matchViewed('match_viewed'),

  /// A registration succeeded.
  matchRegistered('match_registered'),

  /// A withdrawal succeeded. Recorded because the business table cannot be:
  /// withdrawing **deletes** the `match_registrations` row.
  matchWithdrawn('match_withdrawn'),

  /// The Teams screen was opened and its match context loaded.
  teamsViewed('teams_viewed'),

  /// A saved result was actually put in front of the reader. Opening the entry
  /// form is not viewing a result.
  resultViewed('result_viewed'),

  /// A share was handed to the operating system and not dismissed.
  shareUsed('share_used'),

  /// A public link — `/player/{id}`, `/community/{id}`, `/match/{id}` — was
  /// opened and its destination actually shown.
  ///
  /// **Recorded for a signed-in reader only, and that is the approved
  /// boundary rather than an oversight.** `product_events.user_id` is `not
  /// null` and `record_product_event` takes its actor from `auth.uid()`, so
  /// there is no path by which a signed-out visitor's open reaches the table —
  /// and opening one would mean an unauthenticated write, which Package 5
  /// deliberately does not build. A guest who opens a link and then registers
  /// records nothing for the open: a back-dated event would be a fabricated
  /// one.
  publicLinkOpened('public_link_opened');

  const ProductEvent(this.wireName);

  /// The value written to `product_events.event_name`.
  final String wireName;

  /// The event a stored [wireName] refers to, or null when this build does not
  /// know it.
  ///
  /// **Null is a real answer, not a failure.** A row written by a newer release
  /// carries a name this one has never heard of, and the honest thing for a
  /// reader to do with it is show it as it was recorded rather than crash or
  /// silently drop it. The Admin timeline is the only caller and does exactly
  /// that.
  static ProductEvent? fromWireName(String name) {
    for (final event in values) {
      if (event.wireName == name) return event;
    }
    return null;
  }
}

/// What a share was of, recorded as `product_events.share_type`.
///
/// **A closed enum for the same reason [ProductEvent] is.** The six names below
/// are a CHECK constraint on the column (migration `0079`) and are restated in
/// `record_product_event`, which refuses anything else as
/// `INVALID_ANALYTICS_SHARE_TYPE`. Recording the kind is what turns one
/// undifferentiated `share_used` count into the funnel the approved scope asks
/// for: which cards people actually send.
enum ShareType {
  /// The Player Profile card — identity, rating, form.
  playerProfile('player_profile'),

  /// The Player Statistics card — one player's period.
  playerStatistics('player_statistics'),

  /// The Community Statistics card.
  community('community'),

  /// A match, shared from the match's own screen.
  match('match'),

  /// A team lineup.
  lineup('lineup'),

  /// A recorded result.
  result('result');

  const ShareType(this.wireName);

  /// The value written to `product_events.share_type`.
  final String wireName;
}

/// The screens a share or a public-link open is recorded as coming from.
///
/// **Plain strings, not an enum, and deliberately.** The database bounds
/// `product_events.source` to 64 characters and validates nothing else,
/// because the list of screens grows with the product and a CHECK on it would
/// make adding a screen a migration. Gathering the values the application
/// actually passes in one place is what gives a funnel query something stable
/// to group by without closing the set.
abstract final class ShareSource {
  static const playerProfile = 'player_profile_screen';
  static const playerStatistics = 'player_statistics_screen';
  static const communityStatistics = 'community_statistics_tab';
  static const teamOfPeriod = 'team_of_period_screen';
  static const teams = 'teams_screen';
  static const matchResult = 'football_match_screen';

  /// Where a public link was opened from: the link itself, whatever screen it
  /// landed on. It is the arrival that is being counted, not a screen the
  /// reader navigated from.
  static const publicLink = 'public_link';
}
