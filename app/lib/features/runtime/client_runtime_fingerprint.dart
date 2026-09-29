import 'package:flutter/foundation.dart' show visibleForTesting;

/// How an uncaught error is summarised before anything leaves the device.
///
/// **The error's message is never read.** Only its type and the *shape* of the
/// top of its stack are used, and only locally: they are folded into a fixed
/// 16-hex-digit fingerprint, and the fingerprint is the only part of them that
/// is sent. Nothing here is stored.

/// How many stack frames shape a fingerprint.
const int _fingerprintFrames = 5;

/// A deterministic 16-lowercase-hex-digit fingerprint of [error] and [stack].
///
/// The same failure at the same place produces the same fingerprint on every
/// device and platform build, which is what lets errors be grouped by
/// fingerprint, version and platform.
String clientErrorFingerprint(Object error, StackTrace? stack) {
  final material = StringBuffer(error.runtimeType.toString());
  for (final frame in normalizedTopFrames(stack)) {
    material
      ..write('\n')
      ..write(frame);
  }
  return fingerprintOf(material.toString());
}

/// A short, sanitized, non-personal code for [error]: its type name, reduced to
/// `[A-Za-z0-9_]` and at most 64 characters. Never the message.
String clientErrorContextCode(Object error) {
  final sanitized =
      error.runtimeType.toString().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (sanitized.isEmpty) return 'unknown';
  return sanitized.length > 64 ? sanitized.substring(0, 64) : sanitized;
}

/// The top frames of [stack], with the parts that vary between otherwise
/// identical failures removed: the frame index, any URL origin, and line and
/// column numbers.
@visibleForTesting
List<String> normalizedTopFrames(StackTrace? stack) {
  if (stack == null) return const [];
  return stack
      .toString()
      .split('\n')
      .map(_normalizeFrame)
      .where((frame) => frame.isNotEmpty)
      .take(_fingerprintFrames)
      .toList();
}

String _normalizeFrame(String line) => line
    .trim()
    .replaceFirst(RegExp(r'^#\d+\s+'), '')
    .replaceAll(RegExp(r'[a-z][a-z0-9+.-]*://[^/\s)]*'), '')
    .replaceAll(RegExp(r':\d+(:\d+)?'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// 16 lowercase hex digits from two independent 31-bit polynomial hashes.
///
/// Written out rather than imported: no dependency is added for it, and every
/// intermediate value stays below 2^53, so the result is identical under the
/// Dart VM and compiled to JavaScript for the web.
@visibleForTesting
String fingerprintOf(String material) {
  const modulusA = 2147483647; // 2^31 - 1
  const modulusB = 2147483629; // 2^31 - 19
  var a = 0;
  var b = 0;
  for (final unit in material.codeUnits) {
    a = (a * 31 + unit) % modulusA;
    b = (b * 131 + unit + 7) % modulusB;
  }
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}
