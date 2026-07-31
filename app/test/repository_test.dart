import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/invitations/invite_link.dart';

void main() {



  // Row-to-model mapping moved to the Adapter Layer; its tests live in
  // test/mappers_test.dart.

  group('InviteLink', () {
    // Twelve characters from the join-code alphabet, which omits I, L, O, 0
    // and 1 because people mistype them.
    const code = 'ABCDEFGH2345';

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

    test('normalises case, so a code read aloud and retyped still works', () {
      expect(InviteLink.parse(code.toLowerCase()), code);
    });

    test('rejects anything that is not a code', () {
      expect(InviteLink.parse(null), isNull);
      expect(InviteLink.parse('   '), isNull);
      expect(InviteLink.parse('ABC'), isNull, reason: 'too short');
      // An unrelated URL must not have a code read out of its path.
      expect(InviteLink.parse('https://example.com/ABCDEFGH2345'), isNull);
      // The excluded glyphs are not in the alphabet.
      expect(InviteLink.parse('ABCDEFGHI011'), isNull);
    });
  });


  group('PendingInvite', () {
    tearDown(PendingInvite.instance.clear);

    test('holds a code offered as a link', () {
      PendingInvite.instance.offer('https://goplay.app/join/ABCDEFGH2345');
      expect(PendingInvite.instance.code.value, 'ABCDEFGH2345');
    });

    test('ignores a route that is not an invitation', () {
      PendingInvite.instance.offer('/');
      expect(PendingInvite.instance.code.value, isNull);
    });

    test('keeps the previous code when handed nonsense', () {
      PendingInvite.instance.offer('ABCDEFGH2345');
      PendingInvite.instance.offer('nonsense');
      expect(PendingInvite.instance.code.value, 'ABCDEFGH2345',
          reason: 'an unrelated route must not cancel a real invitation');
    });
  });



  // Reading an RPC's refusal moved to the Adapter Layer; its tests live in
  // test/failure_mapping_test.dart. Repository behaviour is covered in
  // test/repository_behaviour_test.dart.
}
