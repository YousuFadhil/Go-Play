import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/auth/auth_service.dart';

void main() {
  group('AuthService.digitsOnly', () {
    test('strips spaces and symbols', () {
      expect(AuthService.digitsOnly('9012 3456'), '90123456');
    });

    test('keeps digits unchanged', () {
      expect(AuthService.digitsOnly('90123456'), '90123456');
    });

    test('returns empty string for non-numeric input', () {
      expect(AuthService.digitsOnly('abc'), '');
    });
  });

  group('AuthService.isValidOmanLocalPhone', () {
    test('accepts exactly 8 digits', () {
      expect(AuthService.isValidOmanLocalPhone('90123456'), isTrue);
    });

    test('accepts 8 digits with spaces', () {
      expect(AuthService.isValidOmanLocalPhone('9012 3456'), isTrue);
    });

    test('rejects fewer than 8 digits', () {
      expect(AuthService.isValidOmanLocalPhone('9012345'), isFalse);
    });

    test('rejects more than 8 digits', () {
      expect(AuthService.isValidOmanLocalPhone('901234567'), isFalse);
    });

    test('rejects empty input', () {
      expect(AuthService.isValidOmanLocalPhone(''), isFalse);
    });
  });

  group('AuthService.toOmanE164', () {
    test('prefixes +968 to an 8-digit local number', () {
      expect(AuthService.toOmanE164('90123456'), '+96890123456');
    });

    test('strips separators before prefixing', () {
      expect(AuthService.toOmanE164('9012 3456'), '+96890123456');
    });
  });

  group('AuthService.isValidEmail', () {
    test('accepts a normal email', () {
      expect(AuthService.isValidEmail('player@example.com'), isTrue);
    });

    test('accepts an email with surrounding whitespace', () {
      expect(AuthService.isValidEmail('  player@example.com '), isTrue);
    });

    test('rejects an email without a domain dot', () {
      expect(AuthService.isValidEmail('player@example'), isFalse);
    });

    test('rejects an email without @', () {
      expect(AuthService.isValidEmail('player.example.com'), isFalse);
    });

    test('rejects empty input', () {
      expect(AuthService.isValidEmail(''), isFalse);
    });
  });
}
