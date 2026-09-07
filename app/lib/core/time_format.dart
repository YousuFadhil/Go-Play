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

/// The day on one short line — "Sat 8 Aug".
///
/// For the compact card, where the stacked tile's three lines cost more height
/// than a card in a column has to give. The same three parts from the same
/// locale, laid along instead of down; stated here beside them rather than
/// assembled inside the card, for the reason the range below is here.
String formatDayShort(BuildContext context, DateTime day) =>
    '${formatWeekdayShort(context, day)} ${formatDayNumber(context, day)} '
    '${formatMonthShort(context, day)}';

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

/// The Muscat wall clock behind an instant an award period was resolved at.
///
/// Team of Period boundaries are resolved by the database in Asia/Muscat --
/// `statistics_period_zone()`, which migration `0028` marks FROZEN -- and
/// arrive here as instants. A week that begins at Muscat midnight on Monday is
/// the instant 20:00 UTC on Sunday, so formatting the instant's own calendar
/// fields would name the day before and the award would read as starting a day
/// early.
///
/// **This decides no period.** Which week the award is about was settled by the
/// database and is never recomputed here; this only turns the instants it
/// returned into the calendar days a reader in Oman would call them.
///
/// Oman has observed UTC+04:00 without daylight saving for the whole life of
/// any data this reads, which is why the offset is stated rather than carried
/// in a time-zone package -- the same reasoning, and the same constant,
/// `StatisticsPeriodWindow` states on the infrastructure side. If that ever
/// stops being true, all three move together and the database is the authority.
const _muscatOffset = Duration(hours: 4);

DateTime muscatDayOf(DateTime instant) =>
    instant.toUtc().add(_muscatOffset);

/// The week an award covers, as the days a reader would name.
///
/// [endExclusive] is the instant the period ends, which is the start of the
/// next one: the last day the award actually covers is the day before it. A
/// range drawn to the exclusive bound would claim a Monday the football never
/// happened on.
///
/// Isolated left-to-right for the reason [formatTimeRange] is: the range runs
/// start-then-end in every language, and without the isolate an Arabic layout
/// reverses the two so the week appears to end before it began.
String formatAwardWeek(
  BuildContext context,
  DateTime start,
  DateTime endExclusive,
) {
  final locale = Localizations.localeOf(context).toString();
  final from = muscatDayOf(start);
  final to = muscatDayOf(endExclusive).subtract(const Duration(days: 1));
  final format = DateFormat.MMMd(locale);
  // Each date is isolated on its own, rather than the pair being forced
  // left-to-right as a whole.
  //
  // The old form wrapped the entire range in an LTR isolate, which laid the
  // Arabic fragments out left-to-right and pulled them apart: "31 \u0623\u063a\u0633\u0637\u0633" came
  // back reordered, because the number and the month name were being placed by
  // a direction that is not the text's. A First Strong Isolate around each date
  // lets each resolve its own direction internally \u2014 day then month, as Arabic
  // writes it \u2014 while the separator and the order of the two follow the
  // paragraph they sit in. An Arabic reader gets the start first in their
  // reading order; an English one gets it on the left.
  //
  // An en dash rather than a hyphen: this is a range, and that is the mark a
  // range is written with.
  return '${_isolate(format.format(from))} \u2013 ${_isolate(format.format(to))}';
}

/// U+2068 FIRST STRONG ISOLATE \u2026 U+2069 POP DIRECTIONAL ISOLATE.
///
/// "First strong" rather than an explicit direction, so a date carries whatever
/// direction its own locale gives it instead of one this function guessed.
String _isolate(String text) => '\u2068$text\u2069';

/// The month an award covers -- "August 2026".
String formatAwardMonth(BuildContext context, DateTime start) =>
    DateFormat.yMMMM(Localizations.localeOf(context).toString())
        .format(muscatDayOf(start));
