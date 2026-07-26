import 'package:flutter/material.dart';

/// How the app writes clock times.
///
/// Neither 12- nor 24-hour is hardcoded: `TimeOfDay.format` reads the device's
/// own preference through `MediaQuery.alwaysUse24HourFormat` and formats for
/// the active locale, so a phone set to 24-hour keeps showing 20:30 and one set
/// to 12-hour shows 8:30 PM (or ٨:٣٠ م in Arabic).
String formatTime(BuildContext context, DateTime time) =>
    TimeOfDay.fromDateTime(time).format(context);

/// A start-to-end range.
///
/// The range is isolated left-to-right because its internal order is not the
/// reader's: it runs start-then-end in every language. Without the isolate an
/// Arabic layout reverses the two, and a match appears to end before it began.
String formatTimeRange(BuildContext context, DateTime start, DateTime end) =>
    // U+2066 LEFT-TO-RIGHT ISOLATE ... U+2069 POP DIRECTIONAL ISOLATE.
    '\u2066${formatTime(context, start)} - ${formatTime(context, end)}\u2069';
