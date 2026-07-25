import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/groups/group_models.dart';

void main() {
  group('CommunityRole.fromDb', () {
    test('reads the three stored roles', () {
      expect(CommunityRole.fromDb('owner'), CommunityRole.owner);
      expect(CommunityRole.fromDb('admin'), CommunityRole.admin);
      expect(CommunityRole.fromDb('player'), CommunityRole.player);
    });

    test('maps the legacy member value to player', () {
      expect(CommunityRole.fromDb('member'), CommunityRole.player);
    });

    test('falls back to player for an unknown value', () {
      expect(CommunityRole.fromDb('superuser'), CommunityRole.player);
      expect(CommunityRole.fromDb(''), CommunityRole.player);
    });
  });

  group('CommunityRole.atLeast', () {
    test('owner covers every role', () {
      expect(CommunityRole.owner.atLeast(CommunityRole.owner), isTrue);
      expect(CommunityRole.owner.atLeast(CommunityRole.admin), isTrue);
      expect(CommunityRole.owner.atLeast(CommunityRole.player), isTrue);
    });

    test('admin covers admin and player but not owner', () {
      expect(CommunityRole.admin.atLeast(CommunityRole.owner), isFalse);
      expect(CommunityRole.admin.atLeast(CommunityRole.admin), isTrue);
      expect(CommunityRole.admin.atLeast(CommunityRole.player), isTrue);
    });

    test('player covers only player', () {
      expect(CommunityRole.player.atLeast(CommunityRole.owner), isFalse);
      expect(CommunityRole.player.atLeast(CommunityRole.admin), isFalse);
      expect(CommunityRole.player.atLeast(CommunityRole.player), isTrue);
    });
  });

  test('CommunityMember.isOwner reflects the role', () {
    CommunityMember member(CommunityRole role) => CommunityMember(
          userId: 'u1',
          fullName: 'Player One',
          position: 'MID',
          role: role,
        );

    expect(member(CommunityRole.owner).isOwner, isTrue);
    expect(member(CommunityRole.admin).isOwner, isFalse);
    expect(member(CommunityRole.player).isOwner, isFalse);
  });
}
