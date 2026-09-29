import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/communities/create_community_screen.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';

import 'wilayat_fixtures.dart';

/// Creating a community: a Wilayat is required, in the app.
///
/// The database keeps the column nullable so an installed build that predates it
/// still creates communities; this is the other half -- that the current build
/// cannot create one without saying where it plays.
void main() {
  final wilayat = find.byKey(const Key('createCommunityWilayat'));
  final createButton = find.widgetWithText(FilledButton, 'Create community');

  Future<_Port> pump(
    WidgetTester tester, {
    Object? failure,
    Locale locale = const Locale('en'),
    WilayatRepository? wilayats,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final port = _Port(failure: failure);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreateCommunityScreen(
                  repository: CommunityRepository(port),
                  wilayatRepository:
                      wilayats ?? WilayatRepository(FakeWilayatAdapter()),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return port;
  }

  Future<void> nameIt(WidgetTester tester,
      [String name = 'Sohar Stars']) async {
    await tester.enterText(find.byType(TextFormField).first, name);
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, int code) async {
    await tester.ensureVisible(wilayat);
    await tester.tap(wilayat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('wilayat_$code')));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
  }

  testWidgets('the form asks where the community plays', (tester) async {
    await pump(tester);

    expect(wilayat, findsOneWidget);
    expect(find.text('Wilayat'), findsOneWidget);
    expect(
        find.descendant(of: wilayat, matching: find.text('Choose a Wilayat')),
        findsOneWidget);
  });

  testWidgets('it cannot be submitted without one', (tester) async {
    final port = await pump(tester);
    await nameIt(tester);

    await submit(tester);

    // The field says what is missing, and nothing reached the port.
    expect(find.text('Choose a Wilayat'), findsWidgets);
    expect(port.created, isEmpty);
    expect(find.byType(CreateCommunityScreen), findsOneWidget);
  });

  testWidgets('a Wilayat alone is not enough either', (tester) async {
    final port = await pump(tester);
    await choose(tester, 7);

    await submit(tester);

    expect(port.created, isEmpty);
    expect(find.text('Community name is required'), findsOneWidget);
  });

  testWidgets('with one chosen, the community is created there',
      (tester) async {
    final port = await pump(tester);
    await nameIt(tester);
    await choose(tester, 7);

    expect(find.descendant(of: wilayat, matching: find.text('Sohar')),
        findsOneWidget);
    await submit(tester);

    expect(port.created, [(name: 'Sohar Stars', wilayatCode: 7)]);
    // The screen closed: creation succeeded.
    expect(find.byType(CreateCommunityScreen), findsNothing);
  });

  testWidgets('the choice can be changed before submitting', (tester) async {
    final port = await pump(tester);
    await nameIt(tester);
    await choose(tester, 7);
    await choose(tester, 51);

    await submit(tester);

    expect(port.created.single.wilayatCode, 51);
  });

  testWidgets('a refused creation keeps the form and says so', (tester) async {
    final port = await pump(tester, failure: const ValidationFailure());
    await nameIt(tester);
    await choose(tester, 7);

    await submit(tester);

    expect(port.created, isEmpty);
    expect(find.byType(CreateCommunityScreen), findsOneWidget);
    expect(find.text('Failed to create the community. Please try again.'),
        findsOneWidget);
  });

  testWidgets('a Wilayat that is retired is not offered', (tester) async {
    await pump(tester);
    await tester.ensureVisible(wilayat);
    await tester.tap(wilayat);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wilayat_55')), findsNothing);
    expect(find.byKey(const Key('wilayat_51')), findsOneWidget);
  });

  testWidgets('the requirement reads in Arabic', (tester) async {
    final port = await pump(tester, locale: const Locale('ar'));
    await tester.enterText(find.byType(TextFormField).first, 'نجوم صحار');
    await tester.pump();

    final button = find.byType(FilledButton).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('اختر الولاية'), findsWidgets);
    expect(port.created, isEmpty);
  });
}

/// Records what is created, and refuses when told to. Everything else on the
/// port is out of scope and says so.
class _Port implements CommunityAdapter {
  _Port({this.failure});

  final Object? failure;
  final created = <({String name, int wilayatCode})>[];

  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
    required int wilayatCode,
  }) async {
    if (failure != null) throw failure!;
    created.add((name: name, wilayatCode: wilayatCode));
    return 'new-community';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
