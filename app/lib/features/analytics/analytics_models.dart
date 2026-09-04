/// The ten events the product records, and the only ten it records.
///
/// **A closed enum, not a string.** The wire name is carried by the value
/// rather than written at the call site, so a screen cannot invent an
/// eleventh event by typing one, cannot misspell an approved one, and cannot
/// drift from the database — where the same ten names are a CHECK constraint on
/// `product_events.event_name` and are restated in `record_product_event`. A
/// name that is not on this list is refused by the database as
/// `INVALID_ANALYTICS_EVENT`; this enum is what makes that refusal unreachable
/// from ordinary code.
///
/// [wireName] must match migration `0067` exactly. A static test asserts every
/// one of them against the migration text.
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
  shareUsed('share_used');

  const ProductEvent(this.wireName);

  /// The value written to `product_events.event_name`.
  final String wireName;
}
