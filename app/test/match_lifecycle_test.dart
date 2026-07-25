import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_settings.dart';
import 'package:go_play/features/matches/match_models.dart';

Match buildMatch({
  required DateTime startAt,
  required DateTime endAt,
  MatchStatus status = MatchStatus.open,
  int startingPlayers = 18,
  int maxRegistration = 24,
  String? title,
}) {
  return Match(
    id: 'm1',
    communityId: 'g1',
    createdBy: 'u1',
    location: 'Main pitch',
    startAt: startAt,
    endAt: endAt,
    startingPlayers: startingPlayers,
    maxRegistration: maxRegistration,
    status: status,
    title: title,
  );
}

void main() {
  final now = DateTime.now();

  group('AppSettings capacity', () {
    test('maximum registration is starting players plus reserve', () {
      expect(AppSettings.reservePlayers, AppSettings.fallbackReservePlayers);
      expect(AppSettings.maxRegistrationFor(18),
          18 + AppSettings.reservePlayers);
    });

    test('default reserve is 6, so 18 starting players allow 24', () {
      expect(AppSettings.fallbackReservePlayers, 6);
      expect(AppSettings.maxRegistrationFor(18), 24);
    });
  });

  group('Match lifecycle', () {
    test('a future match is open for changes and not locked', () {
      final match = buildMatch(
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 4)),
      );
      expect(match.effectiveStatus, MatchStatus.open);
      expect(match.isLocked, isFalse);
      expect(match.isCompleted, isFalse);
      expect(match.isOpenForChanges, isTrue);
    });

    test('a started match is locked and closed for changes', () {
      final match = buildMatch(
        startAt: now.subtract(const Duration(minutes: 30)),
        endAt: now.add(const Duration(hours: 1)),
      );
      expect(match.isLocked, isTrue);
      expect(match.isCompleted, isFalse);
      expect(match.isOpenForChanges, isFalse);
      // Locking does not change the stored status.
      expect(match.effectiveStatus, MatchStatus.open);
    });

    test('a full match keeps its status until it ends', () {
      final match = buildMatch(
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        status: MatchStatus.full,
      );
      expect(match.effectiveStatus, MatchStatus.full);
      expect(match.isOpenForChanges, isTrue);
    });

    test('a match past its end time is completed, not locked', () {
      final match = buildMatch(
        startAt: now.subtract(const Duration(hours: 3)),
        endAt: now.subtract(const Duration(hours: 1)),
      );
      expect(match.effectiveStatus, MatchStatus.completed);
      expect(match.isCompleted, isTrue);
      expect(match.isLocked, isFalse);
      expect(match.isOpenForChanges, isFalse);
    });

    test('completion is derived even when the stored status is stale', () {
      final match = buildMatch(
        startAt: now.subtract(const Duration(hours: 3)),
        endAt: now.subtract(const Duration(hours: 1)),
        status: MatchStatus.full,
      );
      expect(match.effectiveStatus, MatchStatus.completed);
    });
  });

  group('Match display name', () {
    test('falls back to the location when there is no title', () {
      final match = buildMatch(
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 2)),
      );
      expect(match.displayName, 'Main pitch');
    });

    test('prefers the title when set', () {
      final match = buildMatch(
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 2)),
        title: 'Friday derby',
      );
      expect(match.displayName, 'Friday derby');
    });
  });
}
