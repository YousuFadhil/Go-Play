import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/player_record_mapper.dart';

import 'player_record_fakes.dart';

/// Recent Form and Recent Highlight, as rules rather than as pixels.
///
/// Everything asserted here is a decision the product makes: how many matches
/// the window is, what the summary counts, which of two achievements is shown,
/// and what happens when there is nothing to show. The widgets that draw them
/// are tested separately; these are the answers those widgets are handed.
void main() {
  group('the recent-form window', () {
    test('a player with no completed matches has an empty form', () {
      const form = RecentForm.empty;
      expect(form.isEmpty, isTrue);
      expect(form.matches, 0);
      expect(form.goals, 0);
      expect(form.wins, 0);
    });

    test('fewer than five matches is a complete answer, not a partial one', () {
      final form = formOf(
        [MatchOutcome.win, MatchOutcome.draw],
        goals: [2, 0],
      );
      expect(form.matches, 2);
      expect(form.wins, 1);
      expect(form.goals, 2);
    });

    test('five matches summarise the same five', () {
      final form = formOf(
        [
          MatchOutcome.win,
          MatchOutcome.loss,
          MatchOutcome.win,
          MatchOutcome.draw,
          MatchOutcome.win,
        ],
        goals: [1, 0, 3, 0, 2],
      );
      expect(form.matches, 5);
      expect(form.wins, 3);
      expect(form.goals, 6);
    });

    test('the window the product asks for is five', () {
      expect(PlayerRecordRepository.formWindow, 5);
    });

    test('a player with more than five gets the five the read returned',
        () async {
      // The cap is the database's — `player_recent_form` clamps it — and the
      // repository is what names the number. What is asserted here is that the
      // repository asks for five rather than for everything and trimming.
      final records = FakePlayerRecordAdapter(
        form: formOf(List.filled(5, MatchOutcome.win)),
      );
      final form = await PlayerRecordRepository(records).recentForm('u1');

      expect(records.requestedLimit, 5);
      expect(form.matches, 5);
    });

    test('the order is the read\'s, newest first, and nothing re-sorts it', () {
      final form = formOf([
        MatchOutcome.loss,
        MatchOutcome.win,
        MatchOutcome.win,
      ]);
      expect(
        [for (final entry in form.entries) entry.outcome],
        [MatchOutcome.loss, MatchOutcome.win, MatchOutcome.win],
        reason: 'the most recent match is first, because the database said so',
      );
    });
  });

  group('reading form rows', () {
    test('the authenticated read carries which match it was', () {
      final form = recentFormFromRows([
        {
          'match_id': 'm1',
          'community_id': 'c1',
          'community_name': 'Al Amerat FC',
          'start_at': '2026-09-14T18:00:00Z',
          'outcome': 'WIN',
          'goals': 2,
          'is_mvp': true,
        },
      ]);

      final entry = form.entries.single;
      expect(entry.outcome, MatchOutcome.win);
      expect(entry.goals, 2);
      expect(entry.isMvp, isTrue);
      expect(entry.matchId, 'm1');
      expect(entry.communityName, 'Al Amerat FC');
      expect(entry.occurredAt, isNotNull);
    });

    test('the public read carries the record and not the fixtures', () {
      final form = publicRecentFormFromRows([
        {'sequence_no': 1, 'outcome': 'LOSS', 'goals': 0, 'is_mvp': false},
        {'sequence_no': 2, 'outcome': 'DRAW', 'goals': 1, 'is_mvp': false},
      ]);

      expect(form.matches, 2);
      expect(form.entries.first.outcome, MatchOutcome.loss);
      // This is the disclosure boundary: a visitor learns the shape of a
      // player's recent record and nothing about which matches produced it.
      for (final entry in form.entries) {
        expect(entry.matchId, isNull);
        expect(entry.communityId, isNull);
        expect(entry.occurredAt, isNull);
      }
    });

    test('an outcome this build cannot name is dropped, never guessed', () {
      final form = publicRecentFormFromRows([
        {'sequence_no': 1, 'outcome': 'WIN', 'goals': 0, 'is_mvp': false},
        {'sequence_no': 2, 'outcome': 'ABANDONED', 'goals': 0, 'is_mvp': false},
      ]);
      expect(form.matches, 1);
      expect(form.entries.single.outcome, MatchOutcome.win);
    });

    test('a missing goal count reads as none rather than failing the row', () {
      final form = publicRecentFormFromRows([
        {'sequence_no': 1, 'outcome': 'DRAW'},
      ]);
      expect(form.entries.single.goals, 0);
      expect(form.entries.single.isMvp, isFalse);
    });
  });

  group('choosing the one highlight to show', () {
    RecentHighlight mvp(DateTime at) =>
        RecentHighlight(kind: HighlightKind.mvp, occurredAt: at);
    RecentHighlight xi(DateTime at) =>
        RecentHighlight(kind: HighlightKind.teamOfPeriod, occurredAt: at);

    test('nothing eligible means no highlight at all', () {
      expect(RecentHighlight.mostRecent(const []), isNull);
      expect(RecentHighlight.mostRecent([null, null]), isNull);
    });

    test('the only candidate wins', () {
      final only = mvp(DateTime(2026, 9, 1));
      expect(RecentHighlight.mostRecent([null, only]), same(only));
    });

    test('the most recent wins, whichever kind it is', () {
      final older = xi(DateTime(2026, 8, 1));
      final newer = mvp(DateTime(2026, 9, 10));
      expect(RecentHighlight.mostRecent([older, newer]), same(newer));
      expect(RecentHighlight.mostRecent([newer, older]), same(newer));

      final newerXi = xi(DateTime(2026, 9, 12));
      final olderMvp = mvp(DateTime(2026, 9, 11));
      expect(RecentHighlight.mostRecent([olderMvp, newerXi]), same(newerXi));
    });

    test('on the same effective date, Team of Period takes precedence', () {
      final sameDayMvp = mvp(DateTime(2026, 9, 14));
      final sameDayXi = xi(DateTime(2026, 9, 14));

      // Both orders, because a tie rule that depended on the order the
      // candidates happened to be listed in would not be a rule.
      expect(
          RecentHighlight.mostRecent([sameDayMvp, sameDayXi]), same(sameDayXi));
      expect(
          RecentHighlight.mostRecent([sameDayXi, sameDayMvp]), same(sameDayXi));
    });

    test('same day means the calendar day, not the same instant', () {
      // A Team of Period describes a period rather than a moment. Comparing it
      // to a kick-off time to the second would let the rule turn on which hour
      // a match started.
      final eveningMvp = mvp(DateTime(2026, 9, 14, 20, 30));
      final morningXi = xi(DateTime(2026, 9, 14, 6));
      expect(
          RecentHighlight.mostRecent([eveningMvp, morningXi]), same(morningXi));
    });
  });

  group('reading highlight rows', () {
    test('an MVP row becomes an MVP candidate, dated by the match', () {
      final candidates = highlightCandidatesFromRows([
        {
          'highlight_type': 'MVP',
          'occurred_at': '2026-09-14T18:00:00Z',
          'community_name': 'Al Amerat FC',
        },
      ]);

      final highlight = candidates.single;
      expect(highlight.kind, HighlightKind.mvp);
      expect(highlight.communityName, 'Al Amerat FC');
      // A match is not a period.
      expect(highlight.period, isNull);
    });

    test('a stored Team of Period row carries its period', () {
      final candidates = highlightCandidatesFromRows([
        {
          'highlight_type': 'TEAM_OF_PERIOD',
          'occurred_at': '2026-09-13T20:59:59.999Z',
          'community_name': 'Al Amerat FC',
          'period_type': 'weekly',
        },
        {
          'highlight_type': 'TEAM_OF_PERIOD',
          'occurred_at': '2026-08-31T20:59:59.999Z',
          'community_name': 'Al Amerat FC',
          'period_type': 'monthly',
        },
      ]);

      expect(candidates.map((c) => c.kind),
          everyElement(HighlightKind.teamOfPeriod));
      expect(candidates.map((c) => c.period),
          [HighlightPeriod.week, HighlightPeriod.month]);
    });

    test('both candidates are kept: choosing is not the mapper\'s job', () {
      final candidates = highlightCandidatesFromRows([
        {'highlight_type': 'MVP', 'occurred_at': '2026-09-14T18:00:00Z'},
        {
          'highlight_type': 'TEAM_OF_PERIOD',
          'occurred_at': '2026-09-13T20:59:59.999Z',
          'period_type': 'weekly',
        },
      ]);
      expect(candidates, hasLength(2));
    });

    test('no rows is no candidate, and a row with no date is dropped', () {
      // The rule a candidate takes part in is "the most recent wins", and one
      // that cannot be compared is better dropped than ranked arbitrarily.
      expect(highlightCandidatesFromRows(const []), isEmpty);
      expect(
        highlightCandidatesFromRows([
          {'highlight_type': 'MVP'},
        ]),
        isEmpty,
      );
    });

    test('a kind this build does not know is no candidate', () {
      expect(
        highlightCandidatesFromRows([
          {
            'highlight_type': 'GOLDEN_BOOT',
            'occurred_at': '2026-09-14T18:00:00Z',
          },
        ]),
        isEmpty,
      );
    });
  });

  group('the repository applies the rule, and the screen never does', () {
    RecentHighlight mvpOn(DateTime at) => RecentHighlight(
          kind: HighlightKind.mvp,
          occurredAt: at,
          communityName: 'Al Amerat FC',
        );
    RecentHighlight xiEnding(DateTime at) => RecentHighlight(
          kind: HighlightKind.teamOfPeriod,
          occurredAt: at,
          communityName: 'Al Amerat FC',
          period: HighlightPeriod.week,
        );

    test('an MVP alone is the highlight', () async {
      final records =
          FakePlayerRecordAdapter(mvp: mvpOn(DateTime(2026, 9, 14)));
      final highlight =
          await PlayerRecordRepository(records).recentHighlight('u1');
      expect(highlight?.kind, HighlightKind.mvp);
    });

    test('a stored Team of Period alone is the highlight', () async {
      final records = FakePlayerRecordAdapter(
        teamOfPeriod: xiEnding(DateTime(2026, 9, 13, 23, 59)),
      );
      final highlight =
          await PlayerRecordRepository(records).recentHighlight('u1');
      expect(highlight?.kind, HighlightKind.teamOfPeriod);
      expect(highlight?.period, HighlightPeriod.week);
    });

    test('the more recent of the two wins', () async {
      final newerMvp = FakePlayerRecordAdapter(
        mvp: mvpOn(DateTime(2026, 9, 15, 19)),
        teamOfPeriod: xiEnding(DateTime(2026, 9, 13, 23, 59)),
      );
      expect(
        (await PlayerRecordRepository(newerMvp).recentHighlight('u1'))?.kind,
        HighlightKind.mvp,
      );

      final newerXi = FakePlayerRecordAdapter(
        mvp: mvpOn(DateTime(2026, 9, 10, 19)),
        teamOfPeriod: xiEnding(DateTime(2026, 9, 13, 23, 59)),
      );
      expect(
        (await PlayerRecordRepository(newerXi).recentHighlight('u1'))?.kind,
        HighlightKind.teamOfPeriod,
      );
    });

    test('an MVP on the day a period ends loses the tie to Team of Period',
        () async {
      // Sunday's match and the week that ends on Sunday share an effective date,
      // and the approved rule gives it to Team of Period.
      final records = FakePlayerRecordAdapter(
        mvp: mvpOn(DateTime(2026, 9, 13, 19)),
        teamOfPeriod: xiEnding(DateTime(2026, 9, 13, 23, 59)),
      );
      final highlight =
          await PlayerRecordRepository(records).recentHighlight('u1');
      expect(highlight?.kind, HighlightKind.teamOfPeriod);
    });

    test('a player with neither has no highlight', () async {
      final highlight = await PlayerRecordRepository(FakePlayerRecordAdapter())
          .recentHighlight('u1');
      expect(highlight, isNull);
    });
  });

  group('the public record is one read for one screen', () {
    test('a player with no public profile answers null, not an error',
        () async {
      final record = await PlayerRecordRepository(FakePlayerRecordAdapter())
          .publicRecord('u-missing');
      // The database gives no rows for a player who does not exist and for one
      // who is not active alike, so a guessed id learns nothing either way.
      expect(record, isNull);
    });
  });
}
