import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/home/home_create_match_button.dart';

class _ManagedCommunitiesPort implements CommunityAdapter {
  _ManagedCommunitiesPort(this.communities, {this.error});

  final List<Community> communities;
  final Object? error;
  int calls = 0;

  @override
  Future<List<Community>> fetchManagedCommunities() async {
    calls++;
    if (error != null) throw error!;
    return communities;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Community _community(String id, String name) => Community(
      id: id,
      ownerId: 'owner',
      name: name,
      joinPolicy: JoinPolicy.open,
    );

Future<void> _pump(
  WidgetTester tester,
  _ManagedCommunitiesPort port, {
  VoidCallback? onCreated,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: HomeCreateMatchButton(
        communityRepository: CommunityRepository(port),
        onCreated: onCreated ?? () {},
        matchScreenBuilder: (id) => Scaffold(
          appBar: AppBar(title: Text('Match in $id')),
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save match'),
            ),
          ),
        ),
        communityScreenBuilder: () => const Scaffold(
          body: Center(child: Text('New community screen')),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('one managed community opens match form directly',
      (tester) async {
    final port = _ManagedCommunitiesPort([_community('one', 'One')]);
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('homeCreateMatch')));
    await tester.pumpAndSettle();

    expect(find.text('Match in one'), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(port.calls, 1);
  });

  testWidgets('multiple communities require explicit selection',
      (tester) async {
    final port = _ManagedCommunitiesPort([
      _community('one', 'One'),
      _community('two', 'Two'),
    ]);
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('homeCreateMatch')));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Match in two'), findsOneWidget);
  });

  testWidgets('no eligible community offers creating one', (tester) async {
    final port = _ManagedCommunitiesPort([]);
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('homeCreateMatch')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('New community screen'), findsNothing);

    await tester.tap(find.text('Create community').last);
    await tester.pumpAndSettle();
    expect(find.text('New community screen'), findsOneWidget);
  });

  testWidgets('successful match creation refreshes upcoming matches',
      (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      _ManagedCommunitiesPort([_community('one', 'One')]),
      onCreated: () => refreshed++,
    );
    await tester.tap(find.byKey(const Key('homeCreateMatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save match'));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('failed eligibility read shows an error, not no-community state',
      (tester) async {
    final port = _ManagedCommunitiesPort([], error: Exception('offline'));
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('homeCreateMatch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(port.calls, 1);
  });
}
