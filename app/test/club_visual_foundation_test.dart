import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/core/tokens.dart';
import 'package:go_play/features/teams/match_stage.dart';

/// The two approved visual corrections, and the line each of them stops at.
///
/// Both are one-line changes with a wide reach, which is exactly why they are
/// pinned: the hero colour is a token every place-screen reads, and the team
/// heading is a widget the Teams screen and the shared result card both draw.
/// A change made carelessly at either point shows up on a screen nobody was
/// looking at, so what is asserted here is as much what did *not* move.
void main() {
  group('the Light Club hero', () {
    test('the general hero is the primary green', () {
      // The correction itself. The hero used to be `primaryDeep`, which held
      // the top of every place-screen down; it is now the same green the filled
      // controls and the brand accents are drawn in.
      expect(GoColors.bgHero, GoColors.primary);
      expect(GoColors.bgHero, const Color(0xFF306A42));
    });

    test('the deeper green is still itself, and still available', () {
      // Not a global replacement. `primaryDeep` keeps its value and keeps its
      // job: it is what the crest letters, the hero's own filled button and the
      // selected navigation destination are drawn in, each of which wants the
      // darker green *against* something.
      expect(GoColors.primaryDeep, const Color(0xFF123D24));
      expect(GoColors.bgHero, isNot(GoColors.primaryDeep));
      expect(ClubHeroButtons.filled.foregroundColor?.resolve({}),
          GoColors.primaryDeep);
    });

    testWidgets('a hero block paints it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ClubHero(
            bar: ClubHeroBar(title: 'A place'),
            identity: Text('Muscat United'),
          ),
        ),
      ));

      final ground = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(ClubHero),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(ground.color, GoColors.primary);
    });

    test('the Teams palette is untouched by any of it', () {
      // The Teams screen and the share cards are deliberately dark and are not
      // part of the Light Club direction. None of these is derived from the
      // hero token, and this is what says so if one ever becomes so.
      expect(MatchStage.ground, const Color(0xFF05281D));
      expect(MatchStage.section, const Color(0xFF0B3A29));
      expect(MatchStage.accent, const Color(0xFF45DF7C));
      expect(MatchStage.ink, const Color(0xFFF5F8F6));
    });
  });

  group('the team headings', () {
    /// One section, at the width and in the presentation asked for.
    ///
    /// The share presentation is pumped at the raster's own section width; the
    /// phone at the width a 390pt screen leaves it. Both are pumped here rather
    /// than only one, because the phone heading and the share heading are now
    /// two answers out of one widget and a change to either can reach the other.
    Future<void> pumpSection(
      WidgetTester tester, {
      required String title,
      TeamId team = TeamId.a,
      MatchStagePresentation presentation = MatchStagePresentation.shareResult,
    }) async {
      final phone = presentation == MatchStagePresentation.phone;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          backgroundColor: MatchStage.ground,
          body: SingleChildScrollView(
            child: SizedBox(
              width: phone
                  ? MatchStage.phoneReferenceWidth
                  : MatchStageSection.sourceWidth,
              child: MatchStageSection(
                title: title,
                won: false,
                team: team,
                presentation: presentation,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('the words remain', (tester) async {
      for (final presentation in MatchStagePresentation.values) {
        await pumpSection(
          tester,
          title: 'Team A',
          presentation: presentation,
        );
        expect(find.text('Team A'), findsOneWidget, reason: '$presentation');

        await pumpSection(
          tester,
          title: 'Team B',
          team: TeamId.b,
          presentation: presentation,
        );
        expect(find.text('Team B'), findsOneWidget, reason: '$presentation');
      }
    });

    testWidgets('the decorative bar beside them is gone', (tester) async {
      await pumpSection(tester, title: 'Team A');

      // The bar was a short rounded block in `MatchStage.accent`, and it was
      // the only thing in the section drawn in a solid accent fill — the
      // section's own border is the same colour at 35% and is a border rather
      // than a fill. So: no box in the heading area whose fill is the accent.
      final decorated = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(MatchStageSection),
          matching: find.byType(DecoratedBox),
        ),
      );
      final accentFilled = decorated.where((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.color == MatchStage.accent;
      });

      expect(accentFilled, isEmpty,
          reason: 'the Team A/B heading bar was withdrawn and nothing '
              'replaces it');
    });

    testWidgets('and so is the gap that held it off the words', (tester) async {
      // Removing the block and leaving its 15px spacer would have moved the
      // heading without anybody seeing why. The share heading row holds exactly
      // one child, and holds it bare.
      await pumpSection(tester, title: 'Team A');

      final row = tester.widget<Row>(
        find.descendant(
          of: find.byType(MatchStageSection),
          matching: find.byType(Row),
        ),
      );
      expect(row.children, hasLength(1));
      expect(row.children.single, isA<Text>());
    });

    testWidgets('the phone heading names its side, and the share one does not',
        (tester) async {
      // What replaces the withdrawn bar on the phone is not a bar: the phone
      // section has no dark card around it any more, so the heading carries a
      // small mark saying which side this is — emerald for A, neutral grey for
      // B. It is a phone answer to a phone removal, and the share card, whose
      // card is still there, is still given the words alone.
      await pumpSection(
        tester,
        title: 'Team A',
        presentation: MatchStagePresentation.phone,
      );
      expect(find.byKey(const ValueKey('team-a-indicator')), findsOneWidget);
      final teamA = tester.widget<Container>(
        find.byKey(const ValueKey('team-a-indicator')),
      );
      final teamADecoration = teamA.decoration! as BoxDecoration;
      expect(teamADecoration.color, MatchStage.accent);
      expect(teamADecoration.boxShadow, isNotNull,
          reason: 'Team A carries the glow');

      await pumpSection(
        tester,
        title: 'Team B',
        team: TeamId.b,
        presentation: MatchStagePresentation.phone,
      );
      expect(find.byKey(const ValueKey('team-b-indicator')), findsOneWidget);
      final teamB = tester.widget<Container>(
        find.byKey(const ValueKey('team-b-indicator')),
      );
      final teamBDecoration = teamB.decoration! as BoxDecoration;
      expect(teamBDecoration.color, MatchStage.phoneTeamB);
      expect(teamBDecoration.boxShadow, isNull,
          reason: 'neither side is presented as the stronger one');

      for (final team in TeamId.values) {
        await pumpSection(tester, title: 'Team ${team.name}', team: team);
        expect(
            find.byKey(ValueKey('team-${team.name}-indicator')), findsNothing,
            reason: 'the share card is not given a mark it never had');
      }
    });

    testWidgets('the section itself is otherwise intact', (tester) async {
      // The removal was of a decoration, not a redesign. Both sides still
      // render, still key themselves the way the share card finds them by, and
      // still do so in either presentation.
      for (final presentation in MatchStagePresentation.values) {
        await pumpSection(
          tester,
          title: 'Team A',
          presentation: presentation,
        );
        expect(find.byKey(const ValueKey('team-a-section')), findsOneWidget,
            reason: '$presentation');

        await pumpSection(
          tester,
          title: 'Team B',
          team: TeamId.b,
          presentation: presentation,
        );
        expect(find.byKey(const ValueKey('team-b-section')), findsOneWidget,
            reason: '$presentation');
      }
    });
  });
}
