import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// How the app writes clock times.
///
/// Twelve-hour, everywhere, by product decision. This used to follow the
/// device's `alwaysUse24HourFormat` preference, which meant the same match read
/// "20:30" on one phone and "8:30 PM" on another — and the Product Owner wants
/// one answer rather than the device's.
///
/// The locale still decides everything else: `DateFormat.jm` gives "8:30 PM" in
/// English and "٨:٣٠ م" in Arabic, with Arabic-Indic digits and the localized
/// meridiem, so this is a fixed *format* rather than a fixed *language*.
String formatTime(BuildContext context, DateTime time) =>
    DateFormat.jm(Localizations.localeOf(context).toString()).format(time);

/// A start-to-end range.
///
/// The range is isolated left-to-right because its internal order is not the
/// reader's: it runs start-then-end in every language. Without the isolate an
/// Arabic layout reverses the two, and a match appears to end before it began.
String formatTimeRange(BuildContext context, DateTime start, DateTime end) =>
    // U+2066 LEFT-TO-RIGHT ISOLATE ... U+2069 POP DIRECTIONAL ISOLATE.
    '\u2066${formatTime(context, start)} - ${formatTime(context, end)}\u2069';

/// The day a match falls on, in the active locale \u2014 "Sat, 8 Aug 2026".
String formatMatchDay(BuildContext context, DateTime day) =>
    DateFormat.yMMMEd(Localizations.localeOf(context).toString()).format(day);

/// The parts of a date, for the tile that fronts a match card.
///
/// Split rather than formatted into one string because the tile stacks them at
/// different sizes \u2014 the number large, the month small above it. Both come from
/// the active locale, so an Arabic layout gets Arabic numerals and month names
/// rather than a transliteration.
String formatDayNumber(BuildContext context, DateTime day) =>
    DateFormat.d(Localizations.localeOf(context).toString()).format(day);

String formatMonthShort(BuildContext context, DateTime day) =>
    DateFormat.MMM(Localizations.localeOf(context).toString()).format(day);

String formatWeekdayShort(BuildContext context, DateTime day) =>
    DateFormat.E(Localizations.localeOf(context).toString()).format(day);

/// The day and the clock range together, which is how a match has always been
/// written on a card. Stated here rather than in one of the cards that shows it,
/// so the public and the signed-in listings cannot drift into two formats for
/// the same fact.
String formatDayAndTimeRange(
  BuildContext context,
  DateTime start,
  DateTime end,
) =>
    '${formatMatchDay(context, start)} \u2022 '
    '${formatTimeRange(context, start, end)}';
