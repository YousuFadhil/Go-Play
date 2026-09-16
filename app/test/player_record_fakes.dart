import 'package:go_play/features/profile/player_record_adapter.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/profile_models.dart';

/// A player-record port that answers from what a test handed it, and remembers
/// what it was asked.
///
/// Shared between the profile suites because they all need the same thing: a
/// profile screen reads a record now, and a screen test that supplied every
/// other port would otherwise reach for the real Supabase one and fail on an
/// uninitialized client rather than on anything the test is about.
class FakePlayerRecordAdapter implements PlayerRecordAdapter {
  FakePlayerRecordAdapter({
    this.form = RecentForm.empty,
    this.mvp,
    this.teamOfPeriod,
    this.publicRecord,
    this.thrown,
  });

  RecentForm form;
  RecentHighlight? mvp;

  /// The stored Team of Period award the database would return, if any.
  RecentHighlight? teamOfPeriod;
  PublicPlayerRecord? publicRecord;

  /// What every read should throw instead of answering.
  Object? thrown;

  String? requestedUserId;
  String? requestedPublicUserId;
  int? requestedLimit;
  int reads = 0;

  @override
  Future<RecentForm> fetchRecentForm(String userId, {int limit = 5}) async {
    if (thrown != null) throw thrown!;
    reads++;
    requestedUserId = userId;
    requestedLimit = limit;
    return form;
  }

  @override
  Future<List<RecentHighlight>> fetchRecentHighlights(String userId) async {
    if (thrown != null) throw thrown!;
    requestedUserId = userId;
    return [if (mvp != null) mvp!, if (teamOfPeriod != null) teamOfPeriod!];
  }

  @override
  Future<PublicPlayerRecord?> fetchPublicRecord(
    String userId, {
    int limit = 5,
  }) async {
    if (thrown != null) throw thrown!;
    requestedPublicUserId = userId;
    requestedLimit = limit;
    return publicRecord;
  }
}

/// A form of [outcomes], newest first, with [goals] scored in the first match.
///
/// A helper rather than five literals in every test: what these suites assert
/// is the order and the summary, and spelling out a `RecentFormEntry` each time
/// would bury both.
RecentForm formOf(
  List<MatchOutcome> outcomes, {
  List<int>? goals,
  List<bool>? mvp,
}) =>
    RecentForm([
      for (var i = 0; i < outcomes.length; i++)
        RecentFormEntry(
          outcome: outcomes[i],
          goals: goals == null || i >= goals.length ? 0 : goals[i],
          isMvp: mvp != null && i < mvp.length && mvp[i],
        ),
    ]);

/// A public record built around [profile], for the visitor reading.
PublicPlayerRecord publicRecordOf(
  PlayerProfileView profile, {
  RecentForm form = RecentForm.empty,
  RecentHighlight? highlight,
}) =>
    PublicPlayerRecord(profile: profile, form: form, highlight: highlight);
