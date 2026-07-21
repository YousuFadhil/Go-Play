import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/auth/auth_service.dart';

void main() {
  group('AuthService.normalizePhone', () {
    test('strips spaces, plus sign, and dashes', () {
      expect(AuthService.normalizePhone('+966 50-123-4567'), '966501234567');
    });

    test('keeps digits unchanged', () {
      expect(AuthService.normalizePhone('966501234567'), '966501234567');
    });

    test('returns empty string for non-numeric input', () {
      expect(AuthService.normalizePhone('abc'), '');
    });
  });

  group('AuthService.isValidPhone', () {
    test('accepts a valid international number', () {
      expect(AuthService.isValidPhone('966501234567'), isTrue);
    });

    test('rejects numbers that are too short', () {
      expect(AuthService.isValidPhone('12345'), isFalse);
    });

    test('rejects numbers starting with zero', () {
      expect(AuthService.isValidPhone('0501234567'), isFalse);
    });

    test('rejects empty input', () {
      expect(AuthService.isValidPhone(''), isFalse);
    });
  });
}
