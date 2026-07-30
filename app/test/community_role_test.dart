import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/communities/community_models.dart';

void main() {
  // Reading a stored role moved to the Adapter Layer; its tests live in
  // test/mappers_test.dart. What the role *means* stays here.

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
