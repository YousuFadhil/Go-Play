import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_insights_adapter.dart';
import 'package:go_play/features/communities/community_insights_repository.dart';
import 'package:go_play/features/communities/community_insights_screen.dart';

void main() {
  const insights = CommunityInsights(
    eligibleMembers: 34,
    activeMembers30d: 30,
    participationRate30d: 88.2,
    matches30d: 9,
    matchesPerWeek: 2.10,
    avgCapacityUtilization: 98.4,
    guestDependency: 6.9,
  );

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    CommunityInsights value = insights,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: CommunityInsightsScreen(
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        repository: CommunityInsightsRepository(
          _FakeCommunityInsightsAdapter(value),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows only the five approved organizer metrics', (tester) async {
    await pump(tester);

    expect(find.text('Community insights'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('30 / 34'), findsOneWidget);
    expect(find.text('88.2%'), findsOneWidget);
    expect(find.text('2.10'), findsOneWidget);
    expect(find.text('98.4%'), findsOneWidget);
    expect(find.text('6.9%'), findsOneWidget);

    expect(find.text('Active members'), findsOneWidget);
    expect(find.text('Participation rate'), findsOneWidget);
    expect(find.text('Match frequency'), findsOneWidget);
    expect(find.text('Capacity utilization'), findsOneWidget);
    expect(find.text('Guest dependency'), findsOneWidget);

    // Football statistics already live in the community Statistics tab.
    expect(find.text('Goals'), findsNothing);
    expect(find.text('Leaderboards'), findsNothing);
  });

  testWidgets('explains that participation evidence is provisional',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('saved match line-ups'), findsOneWidget);
  });

  testWidgets('unavailable percentages render as an em dash, not zero',
      (tester) async {
    await pump(
      tester,
      value: const CommunityInsights(
        eligibleMembers: 0,
        activeMembers30d: 0,
        participationRate30d: null,
        matches30d: 0,
        matchesPerWeek: 0,
        avgCapacityUtilization: null,
        guestDependency: null,
      ),
    );

    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('Arabic uses the same compact surface', (tester) async {
    await pump(tester, locale: const Locale('ar'));

    expect(find.text('رؤى المجتمع'), findsOneWidget);
    expect(find.text('آخر 30 يومًا'), findsOneWidget);
    expect(find.text('الأعضاء النشطون'), findsOneWidget);
    expect(find.text('نسبة المشاركة'), findsOneWidget);
    expect(find.text('استغلال السعة'), findsOneWidget);
  });
}

class _FakeCommunityInsightsAdapter implements CommunityInsightsAdapter {
  const _FakeCommunityInsightsAdapter(this.value);

  final CommunityInsights value;

  @override
  Future<CommunityInsights> fetch(String communityId) async => value;
}
