import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_widgets.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_result_card.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/results/result_card.dart';
import 'package:go_play/features/results/score_pair.dart';

/// One football result, one card — whoever is reading it.
///
/// **The defect this pins.** Discover drew the same played match two ways: a
/// member saw the Club card with a community line, a face for the best player
/// and a pill; a visitor saw a bare Material `Card`, the community folded into
/// the date, and the best player as a star and a line of text. Signing in
/// changed the shape of the football, which reads as two products rather than
/// two audiences.
///
/// What is asserted here is that both surfaces now *adapt into the same
/// composition* — and, just as deliberately, that the two read models did not
/// merge to achieve it.
void main() {
  PublicResult publicResult({
    String? title = 'Friday football',
    String community = 'Al Amerat FC',
    String? logo,
    String? mvp = 'Yousif Adhil',
    String? mvpAvatar,
    int a = 3,
    int b = 2,
  }) =>
      PublicResult(
        matchId: 'm1',
        communityId: 'c1',
        communityName: community,
        communityLogoUrl: logo,
        title: title,
        location: 'Al Amerat Pitch',
        startAt: DateTime(2026, 9, 11, 17),
        teamAScore: a,
        teamBScore: b,
        mvpDisplayName: mvp,
        mvpAvatarUrl: mvpAvatar,
      );

  CompletedMatch completedMatch({
    String community = 'Al Amerat FC',
    String? title = 'Friday football',
    bool hasResult = true,
    FootballParticipant? mvp,
  }) =>
      CompletedMatch(
        matchId: 'm1',
        communityId: 'c1',
        communityName: community,
        location: 'Al Amerat Pitch',
        startAt: DateTime(2026, 9, 11, 17),
        endAt: DateTime(2026, 9, 11, 19),
        title: title,
        isHistorical: false,
        hasResult: hasResult,
        teamAScore: hasResult ? 3 : null,
        teamBScore: hasResult ? 2 : null,
        mvp: mvp,
      );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: ListView(children: [child])),
    ));
    await tester.pumpAndSettle();
  }

  group('both audiences are shown the same card', () {
    testWidgets('the public result draws the shared composition',
        (tester) async {
      await pump(
        tester,
        PublicResultCard(result: publicResult(), onOpen: () {}),
      );

      expect(find.byType(ResultCard), findsOneWidget);
      expect(find.byType(ScorePair), findsOneWidget);
    });

    testWidgets('and so does the authenticated one', (tester) async {
      await pump(
        tester,
        FootballResultCard(match: completedMatch(), onOpen: () {}),
      );

      expect(find.byType(ResultCard), findsOneWidget);
      expect(find.byType(ScorePair), findsOneWidget);
    });

    testWidgets('the best player is a face and a pill on both', (tester) async {
      // Not a star and a line of text on one of them, which is what the
      // visitor used to get.
      await pump(
        tester,
        PublicResultCard(result: publicResult(), onOpen: () {}),
      );
      expect(find.byType(PlayerAvatar), findsOneWidget);
      expect(find.text('MVP'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);

      await pump(
        tester,
        FootballResultCard(
          match: completedMatch(
            mvp: const FootballParticipant(
              userId: 'u1',
              displayName: 'Yousif Adhil',
              type: ParticipantType.user,
            ),
          ),
          onOpen: () {},
        ),
      );
      expect(find.byType(PlayerAvatar), findsOneWidget);
      expect(find.text('MVP'), findsOneWidget);
    });

    test('and the two read models did not merge to get there', () {
      // The whole point of the presentation model: the card knows neither
      // type, and each surface adapts its own.
      final fromPublic = PublicResultCard(
        result: publicResult(),
        onOpen: () {},
      ).data;
      final fromMember = FootballResultCard(
        match: completedMatch(),
        onOpen: () {},
      ).data;

      expect(fromPublic, isA<ResultCardData>());
      expect(fromMember, isA<ResultCardData>());
      // The public contract publishes no finish time; the member's read does.
      expect(fromPublic.endAt, isNull);
      expect(fromMember.endAt, isNotNull);
    });
  });

  group('the crest', () {
    testWidgets('is drawn where the contract carries one', (tester) async {
      await pump(
        tester,
        PublicResultCard(
          result: publicResult(logo: 'https://example.invalid/logo.png'),
          onOpen: () {},
        ),
      );

      expect(find.byType(CommunityCrest), findsOneWidget);
    });

    testWidgets('degrades to the initials mark with no logo', (tester) async {
      // Not a gap and not a broken-image glyph: a community without a picture
      // is the ordinary case in this product.
      await pump(
        tester,
        PublicResultCard(result: publicResult(logo: null), onOpen: () {}),
      );

      expect(find.byType(CommunityCrest), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and goes away on the community own page', (tester) async {
      // The mark would be repeating the identity of the page it is on.
      await pump(
        tester,
        PublicResultCard(
          result: publicResult(),
          showCommunityName: false,
          onOpen: () {},
        ),
      );

      expect(find.byType(CommunityCrest), findsNothing);
      expect(find.text('Al Amerat FC'), findsNothing);
    });
  });

  group('what may be missing', () {
    testWidgets('no best player leaves no empty row', (tester) async {
      await pump(
        tester,
        PublicResultCard(result: publicResult(mvp: null), onOpen: () {}),
      );

      expect(find.byType(PlayerAvatar), findsNothing);
      expect(find.text('MVP'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a match played but not written up says so', (tester) async {
      // 0-0 is a result somebody recorded, and this is not one.
      await pump(
        tester,
        FootballResultCard(
          match: completedMatch(hasResult: false),
          onOpen: () {},
        ),
      );

      expect(find.byType(ScorePair), findsNothing);
      expect(find.text('Result pending'), findsOneWidget);
    });

    testWidgets('a public result with no title of its own is still named',
        (tester) async {
      await pump(
        tester,
        PublicResultCard(result: publicResult(title: null), onOpen: () {}),
      );

      expect(find.text('Al Amerat FC'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the score stays with its team', () {
    for (final locale in [const Locale('en'), const Locale('ar')]) {
      testWidgets('in ${locale.languageCode}, each number under its own name',
          (tester) async {
        await pump(
          tester,
          PublicResultCard(
            result: publicResult(a: 3, b: 2),
            onOpen: () {},
          ),
          locale: locale,
        );

        // Never a bare "3 - 2": the pair is what binds a number to a side.
        expect(find.byType(ScorePair), findsOneWidget);
        expect(find.text('3 - 2'), findsNothing);
        expect(find.text('2 - 3'), findsNothing);

        final pair = find.byType(ScorePair);
        final three = find.descendant(of: pair, matching: find.text('3'));
        final two = find.descendant(of: pair, matching: find.text('2'));
        expect(three, findsOneWidget);
        expect(two, findsOneWidget);

        // Team A leads in the reading order in both languages, so the winning
        // figure is the one nearer the start of the line either way.
        final aFirst = tester.getCenter(three).dx;
        final bSecond = tester.getCenter(two).dx;
        if (locale.languageCode == 'ar') {
          expect(aFirst, greaterThan(bSecond),
              reason: 'Arabic reads right to left');
        } else {
          expect(aFirst, lessThan(bSecond));
        }
      });
    }
  });

  group('long names survive a narrow phone', () {
    const long = 'Al Amerat Football and Sporting Community of Muscat South';

    for (final width in [320.0, 412.0, 480.0]) {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        testWidgets('at ${width.toInt()}px in ${locale.languageCode}',
            (tester) async {
          await pump(
            tester,
            PublicResultCard(
              result: publicResult(
                community: long,
                title: 'A very long friendly match title that keeps going on',
                mvp: 'Abdulrahman Al Balushi Al Amri',
              ),
              onOpen: () {},
            ),
            locale: locale,
            size: Size(width, 900),
          );

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
