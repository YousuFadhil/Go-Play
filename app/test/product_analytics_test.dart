import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/build_info.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/analytics/analytics_adapter.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';

/// One recorded event, as the fake port saw it.
class RecordedEvent {
  const RecordedEvent(this.event, this.communityId, this.matchId);

  final ProductEvent event;
  final String? communityId;
  final String? matchId;
}

/// An analytics port that remembers, and fails on demand.
class FakeAnalyticsAdapter implements AnalyticsAdapter {
  FakeAnalyticsAdapter({this.thrown});

  /// What [record] should throw instead of succeeding.
  Object? thrown;

  final List<RecordedEvent> recorded = [];

  List<ProductEvent> get events => [for (final e in recorded) e.event];

  @override
  Future<void> record(
    ProductEvent event, {
    String? communityId,
    String? matchId,
  }) async {
    if (thrown != null) throw thrown!;
    recorded.add(RecordedEvent(event, communityId, matchId));
  }
}

void main() {
  group('the event model matches the database', () {
    final sql = File(
      '../supabase/migrations/0067_platform_admin_product_analytics.sql',
    ).readAsStringSync();

    test('there are exactly ten events', () {
      expect(ProductEvent.values.length, 10);
    });

    test('every wire name is one the database accepts', () {
      // Both the CHECK constraint and the writer's own restatement of it, so a
      // name that satisfies the table but not the function cannot slip past.
      final check = sql.substring(
        sql.indexOf('product_events_event_name_check'),
        sql.indexOf('community_id uuid,'),
      );
      final guard = sql.substring(
        sql.indexOf('if p_event_name is null or p_event_name not in ('),
        sql.indexOf("raise exception 'INVALID_ANALYTICS_EVENT'"),
      );

      for (final event in ProductEvent.values) {
        expect(check, contains("'${event.wireName}'"));
        expect(guard, contains("'${event.wireName}'"));
      }
    });

    test('the names are snake_case, as the column stores them', () {
      for (final event in ProductEvent.values) {
        expect(event.wireName, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
      }
    });
  });

  group('the build the app reports about itself', () {
    test('the version matches pubspec', () {
      // The one thing a hand-maintained constant needs: something that notices
      // when the release moves and the constant does not.
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final declared = pubspec
          .firstWhere((line) => line.startsWith('version:'))
          .split(':')[1]
          .trim();
      expect(BuildInfo.appVersion, declared);
    });

    test('the platform is one the database accepts', () {
      // Under test this is neither web nor Android, so the honest answer is
      // null -- which the column and the CHECK both admit.
      expect(BuildInfo.platform, anyOf(isNull, 'web', 'android'));
    });
  });

  group('the adapter asks for the right thing', () {
    // A static review of the adapter's source. The alternative would be a fake
    // SupabaseClient, which would assert that a mock behaves the way the mock
    // was written; what actually matters here is the RPC name, the parameter
    // names, and the absence of a user id -- all of which are in the text.
    final source = File(
      'lib/infrastructure/supabase/supabase_analytics_adapter.dart',
    ).readAsStringSync();

    test('calls record_product_event', () {
      expect(source, contains("_client.rpc('record_product_event'"));
    });

    test('sends the event, the context, the platform and the version', () {
      expect(source, contains("'p_event_name': event.wireName"));
      expect(source, contains("'p_community_id': communityId"));
      expect(source, contains("'p_match_id': matchId"));
      expect(source, contains("'p_platform': BuildInfo.platform"));
      expect(source, contains("'p_app_version': BuildInfo.appVersion"));
    });

    test('never sends a user id', () {
      // The server reads auth.uid(). A client-supplied actor would be a way to
      // write activity against somebody else.
      expect(source, isNot(contains('p_user_id')));
      expect(source, isNot(contains('currentUser')));
    });

    test('goes through the failure mapper like every other adapter', () {
      expect(source, contains('guarded('));
      expect(source, contains("operation: 'rpc record_product_event'"));
    });
  });

  group('analytics never reaches the caller', () {
    test('a recorded event arrives at the port intact', () async {
      final adapter = FakeAnalyticsAdapter();
      await AnalyticsRepository(adapter).track(
        ProductEvent.matchRegistered,
        matchId: 'm1',
        communityId: 'c1',
      );

      expect(adapter.recorded.single.event, ProductEvent.matchRegistered);
      expect(adapter.recorded.single.matchId, 'm1');
      expect(adapter.recorded.single.communityId, 'c1');
    });

    test('a mapped failure is swallowed', () async {
      final adapter = FakeAnalyticsAdapter(thrown: const NetworkFailure());
      // Completes. Does not throw. This is the whole contract.
      await AnalyticsRepository(adapter).track(ProductEvent.sessionStarted);
    });

    test('so is anything else the port can throw', () async {
      // Not just `on Failure`: an uninitialised Supabase client, a missing
      // platform channel, a bug in the adapter. A product flow must not be able
      // to tell the difference.
      for (final thrown in <Object>[
        StateError('Supabase has not been initialised'),
        ArgumentError('bad'),
        Exception('anything at all'),
      ]) {
        final adapter = FakeAnalyticsAdapter(thrown: thrown);
        await AnalyticsRepository(adapter).track(ProductEvent.shareUsed);
      }
    });

    test('the service does not wait for the record either', () {
      final adapter = FakeAnalyticsAdapter(thrown: const NetworkFailure());
      final analytics =
          ProductAnalytics(repository: AnalyticsRepository(adapter));

      // `track` returns void, so there is no future for a caller to await and
      // nothing for a failing one to surface into.
      analytics.track(ProductEvent.communityViewed, communityId: 'c1');
    });
  });

  group('a session is recorded once', () {
    late FakeAnalyticsAdapter adapter;
    late ProductAnalytics analytics;

    setUp(() {
      adapter = FakeAnalyticsAdapter();
      analytics = ProductAnalytics(repository: AnalyticsRepository(adapter));
    });

    test('entering the app as an active account records one', () async {
      analytics.startSession();
      await pumpEventQueue();

      expect(adapter.events, [ProductEvent.sessionStarted]);
    });

    test('asking again does not record a second', () async {
      // This is what a rebuild looks like, and what a resume looks like: the
      // gate re-checks the account and calls again. Neither is a new session.
      analytics.startSession();
      analytics.startSession();
      analytics.startSession();
      await pumpEventQueue();

      expect(adapter.events, [ProductEvent.sessionStarted]);
    });

    test('signing out and back in records a genuinely new one', () async {
      analytics.startSession();
      analytics.endSession();
      analytics.startSession();
      await pumpEventQueue();

      expect(adapter.events, [
        ProductEvent.sessionStarted,
        ProductEvent.sessionStarted,
      ]);
    });

    test('ending a session records nothing of its own', () async {
      analytics.startSession();
      analytics.endSession();
      await pumpEventQueue();

      // There is no `session_ended` in the approved ten, and a session's length
      // is not something this cycle measures.
      expect(adapter.events, [ProductEvent.sessionStarted]);
    });
  });
}
