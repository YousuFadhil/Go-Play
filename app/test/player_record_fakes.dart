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
    this.extraAchievements = const [],
  });

  RecentForm form;
  RecentHighlight? mvp;

  /// The stored Team of Period award the database would return, if any.
  RecentHighlight? teamOfPeriod;

  /// Anything else the achievements read should answer with, after the two
  /// above — a second community's award in the same period, for instance.
  List<RecentHighlight> extraAchievements;
  PublicPlayerRecord? publicRecord;

  /// What every read should throw instead of answering.
  Object? thrown;

  String? requestedUserId;
  String? requestedPublicUserId;
  int? requestedLimit;
  int? requestedAchievementLimit;
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
  Future<List<RecentHighlight>> fetchRecentAchievements(
    String userId, {
    int limit = 5,
  }) async {
    if (thrown != null) throw thrown!;
    requestedUserId = userId;
    requestedAchievementLimit = limit;
    // Newest first, as the database returns them: the fake orders nothing, so
    // a test that cares about order states it in what it hands over.
    return [
      if (mvp != null) mvp!,
      if (teamOfPeriod != null) teamOfPeriod!,
      ...extraAchievements,
    ].take(limit).toList();
  }

  @override
  Future<PublicPlayerRecord?> fetchPublicRecord(
    String userId, {
    int limit = 5,
    int achievements = 5,
  }) async {
    if (thrown != null) throw thrown!;
    requestedPublicUserId = userId;
    requestedLimit = limit;
    requestedAchievementLimit = achievements;
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
  List<(int, int)>? scores,
}) =>
    RecentForm([
      for (var i = 0; i < outcomes.length; i++)
        RecentFormEntry(
          outcome: outcomes[i],
          goals: goals == null || i >= goals.length ? 0 : goals[i],
          isMvp: mvp != null && i < mvp.length && mvp[i],
          scoreFor: _score(outcomes[i], scores, i).$1,
          scoreAgainst: _score(outcomes[i], scores, i).$2,
        ),
    ]);

/// The scoreline a test asked for, or one the outcome implies.
///
/// Since migration `0080` every real form row carries a scoreline, so a fixture
/// without one would be a shape the database no longer produces. A test that
/// cares about the numbers passes them; a test that only cares that there is a
/// result gets a plausible pair that agrees with its own outcome.
(int, int) _score(
  MatchOutcome outcome,
  List<(int, int)>? scores,
  int index,
) {
  if (scores != null && index < scores.length) return scores[index];
  return switch (outcome) {
    MatchOutcome.win => (3, 1),
    MatchOutcome.draw => (2, 2),
    MatchOutcome.loss => (0, 2),
  };
}

/// A public record built around [profile], for the visitor reading.
PublicPlayerRecord publicRecordOf(
  PlayerProfileView profile, {
  RecentForm form = RecentForm.empty,
  RecentHighlight? highlight,
  List<RecentHighlight>? achievements,
}) =>
    PublicPlayerRecord(
      profile: profile,
      form: form,
      achievements: achievements ?? [if (highlight != null) highlight],
    );
