import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/invitations/invite_link.dart';

void main() {



  // Row-to-model mapping moved to the Adapter Layer; its tests live in
  // test/mappers_test.dart.

  group('InviteLink', () {
    // A join code is a number of up to four digits (migration `0030`).
    const code = '4829';

    test('shares the web form, so it survives the domain landing', () {
      expect(InviteLink.format(code), 'https://goplay.app/join/$code');
    });

    test('the app scheme is what opens the app today', () {
      expect(InviteLink.appLink(code), 'goplay://join/$code');
    });

    test('reads a code back out of either link shape', () {
      expect(InviteLink.parse('https://goplay.app/join/$code'), code);
      expect(InviteLink.parse('goplay://join/$code'), code);
    });

    test('accepts a bare code, since a link can arrive flattened to text', () {
      expect(InviteLink.parse(code), code);
    });

    test('finds the link inside a pasted message', () {
      expect(
        InviteLink.parse('Join us on Go Play:\nhttps://goplay.app/join/$code\n'),
        code,
      );
    });

    test('a shorter code is read, because the column accepts one', () {
      // `generate_join_code` issues 1000..9999, and the column accepts one to
      // four digits. Reading a shorter code is what keeps this parser from
      // being stricter than the constraint it stands in front of.
      expect(InviteLink.parse('482'), '482');
    });

    test('rejects anything that is not a code', () {
      expect(InviteLink.parse(null), isNull);
      expect(InviteLink.parse('   '), isNull);
      expect(InviteLink.parse('ABCD'), isNull, reason: 'a code is digits');
      expect(InviteLink.parse('48291'), isNull, reason: 'five is too many');
      // An unrelated URL must not have a code read out of its path.
      expect(InviteLink.parse('https://example.com/4829'), isNull);
      // Nor may a longer number in a join path have its first four taken.
      expect(InviteLink.parse('https://goplay.app/join/48291'), isNull);
    });
  });


  group('PendingInvite', () {
    tearDown(PendingInvite.instance.clear);

    test('holds a code offered as a link', () {
      PendingInvite.instance.offer('https://goplay.app/join/4829');
      expect(PendingInvite.instance.code.value, '4829');
    });

    test('ignores a route that is not an invitation', () {
      PendingInvite.instance.offer('/');
      expect(PendingInvite.instance.code.value, isNull);
    });

    test('keeps the previous code when handed nonsense', () {
      PendingInvite.instance.offer('4829');
      PendingInvite.instance.offer('nonsense');
      expect(PendingInvite.instance.code.value, '4829',
          reason: 'an unrelated route must not cancel a real invitation');
    });
  });



  // Reading an RPC's refusal moved to the Adapter Layer; its tests live in
  // test/failure_mapping_test.dart. Repository behaviour is covered in
  // test/repository_behaviour_test.dart.
}
