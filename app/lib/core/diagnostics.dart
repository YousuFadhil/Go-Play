import 'package:flutter/foundation.dart';

/// Development instrumentation for failures that reach the user as a sentence.
///
/// `OP-5` is the constraint this works around rather than against. Nothing above
/// the Adapter Layer may see a provider exception, a PostgreSQL code or a stack
/// trace, so when a screen shows "something went wrong" the thing that actually
/// went wrong has already been discarded — which is fine in production and
/// useless when a bug only reproduces in a built app.
///
/// So the original is kept **here**, in one place, and only while
/// [verboseErrors] is on. The Adapter Layer records what it caught before it
/// converts it; a screen may render that text instead of the generic sentence.
/// With the flag off nothing is recorded and nothing is shown, and the failure
/// language is exactly what `OP-5` describes.
///
/// This is a diagnostic, not a channel. Nothing branches on what is recorded —
/// behaviour still follows the failure type — and the recorded text is never
/// localized, because it is for whoever is debugging and not for a player.
class Diagnostics {
  const Diagnostics._();

  /// Whether the original failure is kept and shown.
  ///
  /// On in debug builds, and switchable in a release build so a bug that only
  /// appears in one can be read out of it:
  ///
  /// ```
  /// flutter build apk --release --dart-define=GOPLAY_VERBOSE_ERRORS=true
  /// ```
  ///
  /// It defaults to `kDebugMode`, so a plain release build carries no
  /// instrumentation and behaves exactly as before.
  static const bool verboseErrorsDefault =
      bool.fromEnvironment('GOPLAY_VERBOSE_ERRORS', defaultValue: kDebugMode);

  /// Settable so a test can pin both behaviours — the sentence a release build
  /// shows, and the detail an instrumented one replaces it with. Nothing in the
  /// application writes it.
  static bool verboseErrors = verboseErrorsDefault;

  /// The last original failure the Adapter Layer caught, as text.
  ///
  /// A notifier rather than a plain field so a screen can show it without
  /// having to be rebuilt by something else first.
  static final ValueNotifier<String?> lastAdapterFailure =
      ValueNotifier<String?>(null);

  /// Records [error] as what went wrong inside [operation].
  ///
  /// Called by the Adapter Layer at the one point where the original still
  /// exists. A no-op when [verboseErrors] is off, so the original is dropped on
  /// the floor exactly as `OP-5` intends.
  static void recordAdapterFailure(String? operation, Object error) {
    if (!verboseErrors) return;
    lastAdapterFailure.value =
        operation == null ? '$error' : '[$operation] $error';
  }

  /// Forgets what was recorded. Called when an operation starts, so a sentence
  /// shown for one failure cannot be attributed to the next.
  static void clear() {
    if (!verboseErrors) return;
    lastAdapterFailure.value = null;
  }

  /// What to show instead of [fallback] while instrumenting.
  ///
  /// [thrown] is what the screen caught — already a `Failure`, so it names the
  /// type — and the recorded text is what the adapter caught before converting
  /// it. Together they are the whole chain: the provider's own message, and the
  /// failure type the product turned it into.
  ///
  /// Returns [fallback] unchanged when the flag is off, which is what every
  /// release build does.
  static String describe(Object thrown, String fallback) {
    if (!verboseErrors) return fallback;
    final original = lastAdapterFailure.value;
    return original == null ? '$thrown' : '$thrown\n$original';
  }

  /// One tagged line per step of an instrumented flow.
  ///
  /// `debugPrint` reaches logcat in a release build too, so a flow instrumented
  /// this way can be read off a real device with
  /// `adb logcat -s flutter:V | grep GoPlay`.
  static void trace(String layer, String message) {
    if (!verboseErrors) return;
    debugPrint('[GoPlay][$layer] $message');
  }
}
