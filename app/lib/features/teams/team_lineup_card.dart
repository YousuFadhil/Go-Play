import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and
// it would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../profile/current_user.dart';
import 'formation.dart';
import 'pitch_view.dart';
import 'team_models.dart';

/// Everything the Team Lineup card draws, resolved before it is drawn.
///
/// **The lineup the reader is looking at, not a second read of it.** The Teams
/// screen has already loaded the stored assignments, the profiles behind them
/// and the name each player is shown under; all of that arrives here and
/// nothing is looked up again.
///
/// **The match is context, never the subject.** A lineup card is about a
/// community's teams; the fixture that produced them earns one quiet line
/// beneath the name, and only where it exists. Nothing here is a placeholder —
/// a field that is null is a line that is not drawn.
///
/// [names] is the resolved display name per participant, and it is passed
/// rather than derived on purpose. The screen's rule — the profile first, the
/// registration second, a dash for somebody neither knows — is `KB-017`
/// reasoning about a player who left after the lineup was stored, and a card
/// that re-derived it could disagree with the pitch behind it.
@immutable
class TeamLineupCardData {
  const TeamLineupCardData({
    required this.lineup,
    required this.players,
    required this.names,
    required this.hasNaturalGoalkeeper,
    this.communityName,
    this.startAt,
    this.endAt,
    this.location,
  });

  /// The stored lineup, both sides, exactly as the screen holds it.
  final List<TeamAssignment> lineup;

  /// The profiles behind the assignments. A player with no entry left the match
  /// after the lineup was stored and is still drawn — `KB-017` records that
  /// they played — from the assignment alone.
  final Map<String, PlayerCoreInputs> players;

  /// Participant id to the name the screen shows for them.
  final Map<String, String> names;

  /// Whether the squad holds anybody who keeps goal (§10.1). Decides whether a
  /// goal row is drawn at all, and is the screen's own answer.
  final bool hasNaturalGoalkeeper;

  /// Whose teams these are — the card's subject and its largest text.
  ///
  /// Nullable because `Match.communityName` is: it is filled by the read that
  /// joins the community, which is the read the Teams screen makes, but the
  /// type admits absence. Where it is absent the heading is simply not drawn
  /// rather than filled with something invented.
  final String? communityName;

  /// The fixture, for the one context line under the name. Any of these may be
  /// missing, and each missing piece is left out rather than stood in for.
  final DateTime? startAt;
  final DateTime? endAt;
  final String? location;

  List<TeamAssignment> of(TeamId team) => [
        for (final assignment in lineup)
          if (assignment.team == team) assignment,
      ];

  /// Whether there is a lineup to picture at all.
  ///
  /// An empty lineup is not a card. The Teams screen shows "not generated yet"
  /// in that state and there is nothing on it to send, so the Share action is
  /// not offered and this is what says so.
  bool get isShareable => lineup.isNotEmpty;
}

/// The Team Lineup share card: a football poster with a real pitch inside it.
///
/// **Editorial first, tactical second — and both, not one of them.** The card
/// before this one drew a correct tactical board and nothing else, and a
/// correct tactical board still reads as a piece of an application. What a
/// football graphic has that a board does not is a *composition*: a masthead, a
/// subject set at poster scale, one quiet line of context, a dominant image and
/// a signature at the foot. The lineup is the image. Everything here is that
/// arrangement.
///
/// **A cinematic ground rather than a panel.** The card is painted before
/// anything is laid on it — a near-black base, a low emerald pool where the
/// pitch sits, one soft light from above, a vignette and a fine grain. It is
/// deliberately not a flat colour: a flat colour is what makes an image look
/// like a screen rather than a print, and the grain is what stops a phone's
/// gradient from banding once a messaging app has re-compressed it.
///
/// **The pitch has no frame.** Its markings are drawn straight onto the ground
/// and fade towards the two goal ends, so the eye reads a pitch receding into
/// the composition instead of a bordered widget sitting on top of it. The
/// geometry is a real pitch's, in a real pitch's proportions; the fade is the
/// only liberty taken with it.
///
/// **The two sides are told apart by colour, not by a caption.** Team A is the
/// brand's green and Team B is ice, on the ring around every player, on their
/// rating and on the label naming their half. One glance answers "who is on
/// which side", which is a question a lineup graphic exists to answer.
///
/// **The community is the subject and Go Play is the signature.** The largest
/// text on the card names whose teams these are; the product signs the bottom
/// edge at a quarter of that size. The fixture, where it exists, is one line
/// between them, set as a ledger of day, clock and place rather than as a row
/// out of a database.
///
/// **Composed at card scale.** The card is built in the engine's own 1080×1920
/// units, so a 5px line is 5px in the file that leaves the phone — thick enough
/// to survive what a messaging app does to a picture. Nothing measures the
/// device it was composed on.
///
/// **The formation is the app's, the presentation is the card's.**
/// [buildFormation] decides the rows, the wrapping and who is drawn out of
/// their line — none of that is restated here. What the card does not reuse is
/// `PlayerCard` or `PlayerAvatar`: both belong to the Teams screen, are built
/// for a phone and carry Material's own look, which is the exact look a shared
/// picture must not have. The card composes its own player mark from the same
/// formation data rather than changing a shared widget.
///
/// **Presentation only.** It takes [TeamLineupCardData] and draws it: no
/// repository, no formation decision of its own, no statistic invented.
class TeamLineupCard extends StatelessWidget {
  const TeamLineupCard({super.key, required this.data});

  final TeamLineupCardData data;

  // --- the palette ------------------------------------------------------------

  /// Reserved for Team A, the rating it carries and the brand's own mark.
  static const _accent = Color(0xFF3DDC84);

  /// Team B. Not a second hue competing with the brand — the same graphic
  /// language in a cold neutral, so the two sides separate without the card
  /// gaining a colour it does not own.
  static const _ice = Color(0xFFDDE9F1);

  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xC2FFFFFF);
  static const _inkFaint = Color(0x8AFFFFFF);

  /// The safe margin the type is set against. Everything the reader must
  /// *read* lives inside it.
  static const _margin = 72.0;

  static const _page = EdgeInsets.symmetric(horizontal: _margin);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: _AtmospherePainter()),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 58, bottom: 52),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The header is centred, and the pitch beneath it is symmetrical
              // about the same axis: one centre line through the whole card is
              // what makes a poster look composed rather than assembled.
              Padding(
                padding: _page,
                child: _Header(
                  name: data.communityName,
                  day: _day(context),
                  clock: _clock(context),
                  place: _place(),
                  format: _format(),
                ),
              ),
              const SizedBox(height: 24),
              // No horizontal padding: the pitch is the width of the picture.
              Expanded(child: _PitchStage(data: data)),
              const SizedBox(height: 22),
              Padding(padding: _page, child: _Signature(label: l10n.appName)),
            ],
          ),
        ),
      ],
    );
  }

  /// The day, in the app's own wording, so a lineup card and a match card
  /// cannot describe the same fixture two different ways.
  String? _day(BuildContext context) {
    final start = data.startAt;
    return start == null ? null : formatMatchDay(context, start);
  }

  /// The clock, in the pieces the header sets separately.
  ///
  /// **One meridiem where one will do.** The shared helper writes each end with
  /// its own and isolates the pair, which is right for a list of matches and
  /// wrong on a poster: set in Arabic it puts two "م" in one short line and
  /// leaves the reader working out which one is the kick-off. So a match that
  /// starts and ends in the same half of the day is written "8:00–10:00 م", and
  /// only one that crosses noon or midnight is written with both — the one time
  /// the second one carries information. Twelve-hour either way, which is the
  /// product's decision and not the device's.
  ///
  /// **Two pieces, never one string.** A range with a meridiem at each end
  /// cannot be written as one run of text and laid out reliably: the neutral
  /// dash between an Arabic "ص" and the digits after it joins the wrong side,
  /// and the line comes out as "11:00 م 1:00 – ص" whichever direction the
  /// paragraph is given. Handing the header two pieces and letting it place
  /// them left to right is not a workaround for that — it is the only way to
  /// state an order that the text itself does not carry.
  List<String> _clock(BuildContext context) {
    final start = data.startAt;
    if (start == null) return const [];

    final locale = Localizations.localeOf(context).toString();
    final clock = DateFormat('h:mm', locale);
    final half = DateFormat('a', locale);

    final end = data.endAt;
    if (end == null) return ['${clock.format(start)} ${half.format(start)}'];
    if (half.format(start) == half.format(end)) {
      // Safe as one piece: the meridiem is at the end, where an LTR line puts
      // it anyway, and there is nothing neutral between two directions.
      return ['${clock.format(start)}–${clock.format(end)} ${half.format(end)}'];
    }
    return [
      '${clock.format(start)} ${half.format(start)}',
      '${clock.format(end)} ${half.format(end)}',
    ];
  }

  /// Where it is.
  String? _place() {
    final place = data.location?.trim();
    return (place == null || place.isEmpty) ? null : place;
  }

  /// "5 V 5" — the shape of the match, read off the lineup being drawn.
  ///
  /// Counted from what the card actually puts on the pitch rather than from the
  /// stored lineup, because a squad with nobody in goal has its keepers left
  /// out (§10.1) and a line disagreeing with the picture beneath it is worse
  /// than no line. Null where a side is empty: there is no format to name.
  String? _format() {
    int drawn(TeamId team) => data
        .of(team)
        .where((a) =>
            data.hasNaturalGoalkeeper || a.assignedPosition != Position.gk)
        .length;

    final a = drawn(TeamId.a);
    final b = drawn(TeamId.b);
    if (a == 0 || b == 0) return null;
    return '$a V $b';
  }
}

/// The head of the card: who, when, where, and what shape of match.
///
/// **Centred, and the pitch below it shares the axis.** One centre line runs
/// through the whole picture — the kicker, the community, the dateline, the
/// centre circle, the signature — which is the difference between a composed
/// poster and a stack of left-aligned rows.
///
/// **Hierarchy by scale, not by chrome.** The community is set at poster size;
/// the day is a clear line under it; the clock and the venue are one quiet line
/// under that; and the format rides above everything as a kicker, small and
/// tracked, between two short rules. Nothing here is boxed, chipped or filled:
/// a container around any of it would put the application back on the card.
///
/// Every part is optional and nothing is stood in for. A card with no fixture
/// is a community and a lineup, and the header is simply shorter.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.day,
    required this.clock,
    required this.place,
    required this.format,
  });

  final String? name;
  final String? day;
  final List<String> clock;
  final String? place;
  final String? format;

  @override
  Widget build(BuildContext context) {
    final place = this.place;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (format case final String format) ...[
          _Kicker(label: format),
          const SizedBox(height: 26),
        ],
        if (name case final String name) ...[
          _Subject(name: name),
          const SizedBox(height: 18),
        ],
        if (day case final String day)
          Text(
            day,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TeamLineupCard._inkMuted,
              fontSize: 34,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        if (clock.isNotEmpty || place != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (clock.isNotEmpty) _Clock(parts: clock),
              if (clock.isNotEmpty && place != null) const _Diamond(),
              if (place != null) Flexible(child: _Aside(text: place)),
            ],
          ),
        ],
      ],
    );
  }
}

/// The clock: kick-off, a dash, and the end of the match.
///
/// Laid out as separate pieces in a row that is pinned left to right, so the
/// start is on the left of the dash in every language. A match runs
/// start-then-end whatever the reader's script does, and this is the only
/// arrangement that says so without depending on how a bidirectional paragraph
/// happens to resolve a neutral character between two directions.
class _Clock extends StatelessWidget {
  const _Clock({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: _Aside(text: '–', direction: TextDirection.ltr),
            ),
          _Aside(text: part, direction: TextDirection.ltr),
        ],
      ],
    );
  }
}

/// One piece of the quiet line under the day.
class _Aside extends StatelessWidget {
  const _Aside({required this.text, this.direction});

  final String text;

  /// Set only where the piece has an order of its own that the paragraph must
  /// not decide — which is the clock, and nothing else.
  final TextDirection? direction;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      textDirection: direction,
      style: const TextStyle(
        color: TeamLineupCard._inkFaint,
        fontSize: 30,
        fontWeight: FontWeight.w500,
        height: 1.25,
      ),
    );
  }
}

/// The shape of the match, set as the kicker over the whole card.
///
/// A poster's overline: small, tracked, in the brand's colour, with a short
/// rule running out of each side of it. It is the one place tracking is safe —
/// two digits and a Latin V — and it puts the format where a reader looks
/// first without letting it compete with the name underneath.
class _Kicker extends StatelessWidget {
  const _Kicker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _KickerRule(fadeTowardsStart: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            label,
            // Digits against digits: it reads the same way in both languages.
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: TeamLineupCard._accent,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
              height: 1.0,
            ),
          ),
        ),
        const _KickerRule(fadeTowardsStart: false),
      ],
    );
  }
}

/// One of the two rules beside the kicker, fading away from it.
class _KickerRule extends StatelessWidget {
  const _KickerRule({required this.fadeTowardsStart});

  final bool fadeTowardsStart;

  @override
  Widget build(BuildContext context) {
    const solid = Color(0x8A3DDC84);
    const gone = Color(0x003DDC84);

    return Container(
      width: 116,
      height: 4,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: fadeTowardsStart
              ? const [gone, solid]
              : const [solid, gone],
        ),
      ),
    );
  }
}

/// Whose teams these are. The largest thing on the card.
class _Subject extends StatelessWidget {
  const _Subject({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    // Wrapped at the page width first and scaled down second: a long community
    // name becomes two lines of poster type rather than one line of small type.
    // No letter-spacing — the name may be Arabic, where tracking breaks the
    // cursive joins.
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1080 - TeamLineupCard._margin * 2,
          ),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TeamLineupCard._ink,
              fontSize: 108,
              fontWeight: FontWeight.w800,
              height: 1.02,
            ),
          ),
        ),
      ),
    );
  }
}

/// The punctuation between two pieces of context.
class _Diamond extends StatelessWidget {
  const _Diamond();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 9,
          height: 9,
          color: TeamLineupCard._accent.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// The product's signature: a hairline, then the name, once, at the foot.
class _Signature extends StatelessWidget {
  const _Signature({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          height: 2,
          child: CustomPaint(painter: _HairlinePainter()),
        ),
        const SizedBox(height: 20),
        // The mark and the tick beside it are one thing and it reads left to
        // right, so the row is pinned rather than inherited: an Arabic card
        // would otherwise put the tick after the name.
        Row(
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: TeamLineupCard._accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label.toUpperCase(),
              // A name, not a sentence: it reads left to right in both
              // languages, and Latin capitals are the one place tracking is
              // safe.
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: TeamLineupCard._inkFaint,
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: 7,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A rule that fades out at both ends, so the foot of the card closes without
/// a line that stops dead.
class _HairlinePainter extends CustomPainter {
  const _HairlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            const Color(0x00FFFFFF),
            const Color(0x24FFFFFF),
            const Color(0x24FFFFFF),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.22, 0.78, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HairlinePainter oldDelegate) => false;
}

// --- the pitch ----------------------------------------------------------------

/// The room the pitch is given, and the pitch built to fill it.
///
/// The proportions are held and the size is not: the stage takes the height the
/// composition leaves it — a community with a two-line name leaves less — and
/// derives the width from that. Everything drawn inside is measured from the
/// resolved size rather than from a constant, so the pitch is never a fixed
/// drawing squeezed into a variable box.
class _PitchStage extends StatelessWidget {
  const _PitchStage({required this.data});

  final TeamLineupCardData data;

  /// The widest the pitch is allowed to be drawn, as width over height.
  ///
  /// **The pitch takes the whole width of the picture and gives on the other
  /// axis.** A pitch held to a fixed proportion leaves a gutter down both sides
  /// of the card, and a gutter is what turns a drawing into a panel sitting on
  /// a background. So the stage fills the frame edge to edge and lets the
  /// proportion float: at 0.86 the touchlines are past the edge of the picture
  /// and the pitch simply carries on out of frame, which is what "bleed" means
  /// and what no bordered container can do.
  ///
  /// A real pitch runs anywhere from about 0.57 to 0.9 wide against long, so
  /// nothing in this band is a pitch a reader would not recognise, and the
  /// markings inside it stay in their own true proportions either way.
  static const _maxRatio = 0.86;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = math.min(constraints.maxWidth, height * _maxRatio);
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: _Pitch(data: data, size: Size(width, height)),
          ),
        );
      },
    );
  }
}

/// One pitch, both teams, facing each other across the halfway line.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.data, required this.size});

  final TeamLineupCardData data;
  final Size size;

  /// Room between the edge of the picture and the outermost player. Wider than
  /// it needs to be for the markings' sake: the pitch runs out of frame now, so
  /// this is what keeps the players and their names inside the safe margin the
  /// type is set to.
  static const _insetX = 66.0;
  static const _insetY = 46.0;

  /// The halfway line's own room. Without it the two attacks meet exactly on
  /// the line — no overlap, but no air either, and the one place on the card
  /// where the two teams touch is the place that most needs to be legible.
  static const _midGutter = 16.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final a = _Half.of(data, TeamId.a, towardsTop: true);
    final b = _Half.of(data, TeamId.b, towardsTop: false);

    final rows = math.max(1, math.max(a.rows.length, b.rows.length));
    final columns = math.max(
      1,
      [...a.rows, ...b.rows].fold(1, (m, row) => math.max(m, row.length)),
    );

    final cellWidth = (size.width - _insetX * 2) / columns;
    final rowHeight =
        (size.height - _insetY * 2 - _midGutter * 2) / 2 / rows;
    final hasHint = a.hasHint || b.hasHint;

    var metrics = _MarkMetrics.resolve(
      cellWidth: cellWidth,
      rowHeight: rowHeight,
      hasHint: hasHint,
      nameLines: 1,
    );

    // **A second line is bought, not assumed.** Room for one is room taken off
    // every photograph on the card, so it is only reserved where a name on
    // *this* lineup cannot be set on one line without being shrunk past what a
    // reader can take in — and then it is reserved for every mark, because one
    // size for everybody is what stops the drawing looking accidental. A five
    // a side of ordinary names resolves exactly as it did before this existed.
    if (_PlayerName.anyNeedsTwoLines(context, _drawnNames(a, b), metrics)) {
      final roomier = _MarkMetrics.resolve(
        cellWidth: cellWidth,
        rowHeight: rowHeight,
        hasHint: hasHint,
        nameLines: 2,
      );
      // Unless there is no room to buy it with: a lineup already at the
      // smallest face the card draws keeps its one line and its ellipsis
      // rather than running over the row below.
      if (roomier.height <= rowHeight) metrics = roomier;
    }

    return CustomPaint(
      painter: const _PitchPainter(),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _insetX,
              vertical: _insetY,
            ),
            child: Column(
              children: [
                // Team A defends the top goal, so its rows run the other way:
                // the goal first and the attack last, meeting Team B's attack
                // at the halfway line.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _midGutter),
                    child: a.build(data, metrics, TeamLineupCard._accent),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: _midGutter),
                    child: b.build(data, metrics, TeamLineupCard._ice),
                  ),
                ),
              ],
            ),
          ),
          // On the grass and clear of it: inside the touchline, outside the
          // penalty areas — which occupy the middle 59% of each end — and above
          // the goal rows, which are centred.
          PositionedDirectional(
            start: _insetX,
            top: 18,
            child: _TeamLabel(
              label: l10n.teamAName,
              tint: TeamLineupCard._accent,
            ),
          ),
          PositionedDirectional(
            start: _insetX,
            bottom: 18,
            child: _TeamLabel(
              label: l10n.teamBName,
              tint: TeamLineupCard._ice,
            ),
          ),
        ],
      ),
    );
  }

  /// Every name the card is about to draw, both halves.
  Iterable<String> _drawnNames(_Half a, _Half b) sync* {
    for (final half in [a, b]) {
      for (final row in half.rows) {
        for (final assignment in row) {
          yield data.names[assignment.participantId] ?? '—';
        }
      }
    }
  }
}

/// One team's half of the pitch, already arranged into rows.
///
/// [towardsTop] is which goal the team defends. It reverses the row order and
/// nothing else: the formation itself — who is in attack, how the midfield
/// wraps, who is drawn out of their line — is [buildFormation]'s and is not
/// touched.
class _Half {
  const _Half({required this.rows, required this.movedFrom});

  final List<List<TeamAssignment>> rows;
  final Map<String, Position> movedFrom;

  bool get hasHint => movedFrom.isNotEmpty;

  static _Half of(
    TeamLineupCardData data,
    TeamId team, {
    required bool towardsTop,
  }) {
    final formation = buildFormation(
      data.of(team),
      // A stable order, so a row does not reshuffle between builds.
      order: (a, b) => (data.names[a.participantId] ?? '')
          .compareTo(data.names[b.participantId] ?? ''),
    );

    // `buildFormation` returns rows top-down for a team attacking upwards:
    // attack, midfield, defence, goal.
    final lines = <List<TeamAssignment>>[
      if (formation.attack.isNotEmpty) formation.attack,
      ...formation.midfieldRows,
      if (formation.defence.isNotEmpty) formation.defence,
      if (data.hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
        formation.goalkeepers,
    ];

    return _Half(
      rows: towardsTop ? lines.reversed.toList() : lines,
      movedFrom: formation.movedFrom,
    );
  }

  Widget build(TeamLineupCardData data, _MarkMetrics metrics, Color tint) {
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: _PitchRow(
              row: row,
              data: data,
              metrics: metrics,
              movedFrom: movedFrom,
              tint: tint,
            ),
          ),
      ],
    );
  }
}

/// One line of the pitch. The players spread evenly across it, so the shape of
/// the row is the shape of the line.
class _PitchRow extends StatelessWidget {
  const _PitchRow({
    required this.row,
    required this.data,
    required this.metrics,
    required this.movedFrom,
    required this.tint,
  });

  final List<TeamAssignment> row;
  final TeamLineupCardData data;
  final _MarkMetrics metrics;
  final Map<String, Position> movedFrom;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final assignment in row)
          SizedBox(
            width: metrics.cellWidth,
            child: Center(
              child: TeamLineupPlayerMark(
                // Resolved by the screen. A dash for somebody neither the
                // profiles nor the roster knows.
                name: data.names[assignment.participantId] ?? '—',
                radius: metrics.radius,
                nameSize: metrics.nameSize,
                nameWidth: metrics.nameWidth,
                nameHeight: metrics.nameHeight,
                nameLines: metrics.nameLines,
                ratingSize: metrics.ratingSize,
                hintSize: metrics.hintSize,
                // The initials come from the **profile**, never from the
                // resolved name: somebody who left the match after the lineup
                // was stored has no profile and a dash for a name, and
                // lettering a disc with a dash is not initials.
                fullName: data.players[assignment.participantId]?.fullName,
                avatarUrl: data.players[assignment.participantId]?.avatarUrl,
                rating: data.players[assignment.participantId]?.overallRating,
                isProfessionalGuest: assignment.isProfessionalGuest,
                movedFrom: movedFrom[assignment.participantId],
                tint: tint,
              ),
            ),
          ),
      ],
    );
  }
}

/// How large a player is drawn, decided once for the whole card.
///
/// **One size for everybody, chosen by the densest row.** A per-player
/// `scaleDown` — what the card did before — gives a five-a-side keeper a
/// different size from the defender beside them, and a graphic whose elements
/// are almost the same size is a graphic that looks accidental. So the size is
/// solved once against the tightest cell either team produces, and every mark
/// on the card is that size.
///
/// **Five-a-side and eleven-a-side are not the same drawing.** Nothing here is
/// a scale factor applied to a fixed design: fewer rows and shorter rows leave
/// a larger cell, which resolves to a larger face, a larger name and a larger
/// rating. A crowded lineup resolves the other way and stays inside its row.
@immutable
class _MarkMetrics {
  const _MarkMetrics({
    required this.radius,
    required this.nameSize,
    required this.ratingSize,
    required this.hintSize,
    required this.cellWidth,
    required this.nameLines,
  });

  final double radius;
  final double nameSize;
  final double ratingSize;
  final double hintSize;
  final double cellWidth;

  /// How many lines of name the card has reserved room for, on every mark.
  final int nameLines;

  /// A face this large stops reading as a photograph on a poster. Five a side
  /// reaches it; eleven a side never comes close.
  static const _maxRadius = 66.0;

  /// And below this it stops reading as a face at all. A lineup denser than the
  /// engine can produce is drawn at this size and allowed to be tight rather
  /// than shrunk into illegibility.
  static const _minRadius = 22.0;

  /// The rating tag is set into the corner of the photograph and hangs a little
  /// below it.
  double get badgeHeight => ratingSize * 1.44;
  double get badgeOverhang => badgeHeight * 0.34;

  /// The room a name is given: its own cell, less a gutter wide enough to read
  /// as a gap. Two long names in neighbouring cells both trim to their own
  /// share and the space between them is what tells the reader they are two
  /// names rather than one long one.
  double get nameWidth => cellWidth - 34;

  /// The room the name is given, whether or not this particular name uses all
  /// of it. Reserved rather than measured per player so that every photograph
  /// in a row sits at the same height: a mark that grew a line would otherwise
  /// push its own face up out of line with the four beside it.
  ///
  /// Rounded up per line, because that is what the text engine does: a line box
  /// of 33.06 × 1.2 is laid out as 40 pixels, not 39.67, and two of them
  /// overrun a block reserved at the exact arithmetic by two thirds of a pixel
  /// — which is a real overflow, and which the engine paints a stripe over.
  double get nameHeight =>
      (nameSize * _lineHeight).ceilToDouble() * nameLines;

  /// The whole mark, top of the photograph to the foot of the last line.
  double get height =>
      radius * 2 + badgeOverhang + radius * 0.16 + nameHeight + hintSize * 1.5;

  /// The name's leading, and the one place it is stated.
  static const _lineHeight = 1.2;

  factory _MarkMetrics.resolve({
    required double cellWidth,
    required double rowHeight,
    required bool hasHint,
    required int nameLines,
  }) {
    // Largest first, and the first size that fits both ways wins. A whole
    // pixel at a time: the answer feeds a photograph's diameter, and a
    // fractional radius buys nothing a reader can see.
    for (var radius = _maxRadius; radius > _minRadius; radius -= 1) {
      final candidate = _at(radius, cellWidth, hasHint, nameLines);
      if (candidate.height <= rowHeight && radius * 2 + 12 <= cellWidth) {
        return candidate;
      }
    }
    return _at(_minRadius, cellWidth, hasHint, nameLines);
  }

  static _MarkMetrics _at(
    double radius,
    double cellWidth,
    bool hasHint,
    int nameLines,
  ) {
    return _MarkMetrics(
      radius: radius,
      nameSize: (radius * 0.58).clamp(19.0, 37.0).toDouble(),
      ratingSize: (radius * 0.44).clamp(16.0, 27.0).toDouble(),
      hintSize: hasHint ? (radius * 0.34).clamp(13.0, 21.0).toDouble() : 0.0,
      cellWidth: cellWidth,
      nameLines: nameLines,
    );
  }
}

/// One player on the pitch: their face, their name and what they are rated.
///
/// **A graphic element, not a list row.** The card's own mark rather than
/// `PlayerCard` or `PlayerAvatar`: those are the Teams screen's, are built for
/// a phone and carry Material's colours, which is the look a shared picture
/// must not have. What is here instead is a photograph in a hairline of its
/// team's colour, lifted off the grass by a shadow, with the rating set into
/// the corner of it as a small square tag — the way a football graphic has
/// always written a number on a player.
///
/// **Three things, one shape.** Photograph, rating, name: the rating is cut
/// into the corner of the face rather than floated under it, so the mark is a
/// single object with a number on it instead of three stacked components. It is
/// also the reason the tag is square-cornered on a round photograph — a rounded
/// pill under a circle is the silhouette of a chip, which is the one thing this
/// must not look like.
///
/// **The rating stays.** It is the one figure this product has that a lineup
/// graphic can carry, and the tag is filled solid in the team's colour so it
/// survives whatever photograph is behind it.
///
/// **A player without a photograph is not a lesser player.** The same hairline,
/// the same shadow, the same tag; their initials in their team's colour where
/// their profile gives initials, and the game's own mark where it does not. A
/// dash is never lettered into a disc: somebody who left the match after the
/// lineup was stored has no profile to take initials from.
class TeamLineupPlayerMark extends StatelessWidget {
  const TeamLineupPlayerMark({
    super.key,
    required this.name,
    required this.tint,
    required this.radius,
    required this.nameSize,
    required this.nameWidth,
    required this.ratingSize,
    required this.hintSize,
    this.nameHeight,
    this.nameLines = 1,
    this.fullName,
    this.avatarUrl,
    this.rating,
    this.isProfessionalGuest = false,
    this.movedFrom,
  });

  /// The name the screen resolved, drawn under the face.
  final String name;

  /// The name on the **profile**, and the only source of initials. Null for
  /// somebody with no profile, and never read for a Professional Guest.
  final String? fullName;

  final String? avatarUrl;
  final double? rating;
  final bool isProfessionalGuest;

  /// Set where the drawing put a player in a line their position does not name.
  final Position? movedFrom;

  /// Their team's colour.
  final Color tint;

  /// The measurements the card solved for this lineup — the same for every
  /// player on it, so no two marks are drawn at different sizes.
  final double radius;
  final double nameSize;
  final double nameWidth;
  final double ratingSize;

  /// The room reserved for the name, and how many lines of it the card decided
  /// this lineup needs. Both are the same on every mark, so the faces in a row
  /// stay in line whether or not a particular name uses the second line.
  final double? nameHeight;
  final int nameLines;

  /// Zero where no player on this card was moved out of their line, which is
  /// what keeps a row from reserving space for a hint nobody needs.
  final double hintSize;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: radius * 2 + ratingSize * 0.9,
          height: radius * 2 + ratingSize * 0.49,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              _Face(
                radius: radius,
                tint: tint,
                avatarUrl: avatarUrl,
                fullName: fullName,
                isProfessionalGuest: isProfessionalGuest,
              ),
              // The trailing corner, which is the leading edge of nothing:
              // in Arabic it moves to the other side of the face with the rest
              // of the reading order.
              if (rating != null)
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: _RatingTag(
                    rating: rating,
                    tint: tint,
                    size: ratingSize,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: radius * 0.16),
        // The name and what qualifies it are one block, given the room the card
        // reserved and filled from the top. A name that takes one line where
        // the card reserved two leaves the slack at the foot of the block
        // rather than between itself and its own hint.
        SizedBox(
          height: nameHeight == null
              ? null
              : nameHeight! + (hintSize > 0 ? hintSize * 1.5 : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlayerName(
                text: name,
                maxWidth: nameWidth,
                size: nameSize,
                lines: nameLines,
              ),
              if (movedFrom case final Position position)
                if (hintSize > 0)
                  _MovedFromHint(
                    position: position,
                    tint: tint,
                    size: hintSize,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The photograph, ringed and lifted off the grass.
class _Face extends StatelessWidget {
  const _Face({
    required this.radius,
    required this.tint,
    required this.avatarUrl,
    required this.fullName,
    required this.isProfessionalGuest,
  });

  final double radius;
  final Color tint;
  final String? avatarUrl;
  final String? fullName;
  final bool isProfessionalGuest;

  /// What sits behind a photograph that has not loaded, and under one that has.
  static const _base = Color(0xFF0D1614);

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _base,
        // A hairline rather than a ring. The heavy ring the card had before
        // drew a second circle around every photograph, and twenty-two of those
        // is a page of targets; this states the team and gets out of the way,
        // leaving the rating tag to carry the colour.
        border: Border.all(
          color: tint.withValues(alpha: 0.62),
          width: (radius * 0.045).clamp(2.0, 3.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xBF000000),
            blurRadius: radius * 0.6,
            offset: Offset(0, radius * 0.18),
          ),
        ],
      ),
      child: ClipOval(child: _content(diameter)),
    );
  }

  Widget _content(double diameter) {
    final fallback = _Fallback(
      radius: radius,
      tint: tint,
      initials: isProfessionalGuest ? null : _initials(),
      isProfessionalGuest: isProfessionalGuest,
    );

    final url = avatarUrl;
    if (isProfessionalGuest || url == null) return fallback;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          // A picture that will not load is not an error and not a hole: it is
          // the same player, drawn the way a player without one is drawn.
          errorBuilder: (_, __, ___) => fallback,
          frameBuilder: (_, child, frame, wasSynchronous) =>
              frame == null && !wasSynchronous ? fallback : child,
        ),
        // A scrim across the foot, so the tag cut into the corner keeps its
        // edge whatever the photograph happens to be.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x8C000000), Color(0x00000000)],
                stops: [0.0, 0.45],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Initials, or nothing.
  ///
  /// [initialsOf] is the product's rule — first word and last — and is reused
  /// rather than restated. What is added here is the refusal: a "name" holding
  /// no letter and no digit yields no initials, which is what stops a player
  /// the screen could only call "—" from being lettered with a dash.
  String? _initials() {
    final name = fullName;
    if (name == null) return null;
    final initials = initialsOf(name);
    final hasLetter = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(initials);
    return hasLetter ? initials : null;
  }
}

/// What fills a face with no photograph behind it.
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.radius,
    required this.tint,
    required this.initials,
    required this.isProfessionalGuest,
  });

  final double radius;
  final Color tint;
  final String? initials;
  final bool isProfessionalGuest;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: 0.20),
            tint.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: switch ((isProfessionalGuest, initials)) {
          // A guest is marked as a guest, never lettered: they have no account
          // and no name of their own on this card.
          (true, _) => Icon(
              Icons.workspace_premium_outlined,
              size: radius * 0.95,
              color: tint.withValues(alpha: 0.92),
            ),
          (false, final String initials) => Text(
              initials,
              maxLines: 1,
              // No tracking: these initials are Arabic as often as not.
              style: TextStyle(
                color: tint,
                fontSize: radius * 0.74,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          // No profile, so no initials — the game's own mark rather than a
          // figure borrowed from an address book.
          (false, null) => Icon(
              Icons.sports_soccer,
              size: radius * 0.85,
              color: tint.withValues(alpha: 0.55),
            ),
        },
      ),
    );
  }
}

/// The rating, as a solid tag cut into the corner of the photograph.
class _RatingTag extends StatelessWidget {
  const _RatingTag({
    required this.rating,
    required this.tint,
    required this.size,
  });

  final double rating;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.30,
        vertical: size * 0.22,
      ),
      decoration: BoxDecoration(
        color: tint,
        // Barely rounded: enough that it is drawn rather than cut out, not so
        // much that it becomes a pill.
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: const [
          BoxShadow(
            color: Color(0xA6000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        rating.toStringAsFixed(1),
        // Western digits, as everywhere a rating is written in this product.
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: const Color(0xFF04140C),
          fontSize: size,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

/// The position a player actually holds, on a mark the drawing has moved.
///
/// The same statement `PitchView` makes on the phone, at the card's scale and
/// without its container: a caret and a word, because a pill around two small
/// words is the kind of chrome that makes a picture look like an interface.
class _MovedFromHint extends StatelessWidget {
  const _MovedFromHint({
    required this.position,
    required this.tint,
    required this.size,
  });

  final Position position;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.arrow_upward_rounded,
          size: size * 1.05,
          color: tint.withValues(alpha: 0.9),
        ),
        SizedBox(width: size * 0.2),
        Flexible(
          child: Text(
            positionLabelOf(l10n, position),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: TeamLineupCard._inkMuted,
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1.1,
              shadows: const [
                Shadow(blurRadius: 6, color: Color(0xCC000000)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A player's name, set as large as its own cell allows.
///
/// **One line at full size, then a smaller line, then two lines, then — and
/// only then — an ellipsis.** In that order, because that is the order a
/// typesetter would try. A name is stepped down a point at a time while it
/// still reads comfortably; a name that cannot be set on one line even then is
/// broken over two rather than shrunk into the floor or cut off, because
/// "عبدالرحمن بن سليمان الحارثي" over two lines is a player a reader can
/// identify and "عبدالرحمن بن سليمان الحـ…" is not. Only a name that will not
/// fit the room reserved for it, at the smallest size this card will set, is
/// trimmed — and it is trimmed rather than allowed to run into the player
/// beside it.
///
/// **The room is fixed and the name sits at the top of it.** The mark reserves
/// the same block on every player, so whether this particular name takes one
/// line or two, a two-line name never pushes its own photograph out of line
/// with the players either side of it.
///
/// Nothing is tracked out or capitalised: a name here is Arabic as often as it
/// is Latin, and the line the text engine breaks is the one the reader's script
/// asks for.
class _PlayerName extends StatelessWidget {
  const _PlayerName({
    required this.text,
    required this.maxWidth,
    required this.size,
    this.lines = 1,
  });

  final String text;
  final double maxWidth;
  final double size;

  /// How many lines this card reserved room for.
  final int lines;

  /// Below this a name stops being readable in a picture somebody will look at
  /// on a phone, so it ellipsizes instead of shrinking further.
  static const _floor = 18.0;

  /// How far a name may be shrunk before a second line is the better answer.
  /// Much past this and one name is visibly smaller than the ten around it,
  /// which reads as a mistake rather than as a fit.
  static const _comfort = 0.82;

  /// The name's own style at [at], merged onto whatever the card is set in, so
  /// that a measurement and the text it measures cannot disagree.
  static TextStyle styleAt(BuildContext context, double at) =>
      DefaultTextStyle.of(context).style.merge(
            TextStyle(
              color: TeamLineupCard._ink,
              fontSize: at,
              fontWeight: FontWeight.w700,
              height: 1.2,
              shadows: const [Shadow(blurRadius: 8, color: Color(0xCC000000))],
            ),
          );

  /// Whether [text] fits [maxLines] lines of [maxWidth] at [at].
  static bool _fits(
    BuildContext context,
    String text,
    double at,
    double maxWidth,
    int maxLines,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: styleAt(context, at)),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines && painter.width <= maxWidth;
  }

  /// Whether any of these names would have to be cut, or shrunk past comfort,
  /// to be set on the one line [metrics] currently reserves.
  ///
  /// The question the pitch asks before it decides whether to buy a second line
  /// for the whole card.
  static bool anyNeedsTwoLines(
    BuildContext context,
    Iterable<String> names,
    _MarkMetrics metrics,
  ) {
    final comfort = math.max(_floor, metrics.nameSize * _comfort);
    for (final name in names) {
      if (!_fits(context, name, comfort, metrics.nameWidth, 1)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var chosen = size;
    var used = 1;

    if (!_fits(context, text, size, maxWidth, 1)) {
      // Smaller, a point at a time, while one line still reads as one of the
      // card's names rather than as a footnote.
      final comfort = math.max(_floor, size * _comfort);
      var settled = false;
      for (var at = size - 1; at >= comfort; at -= 1) {
        if (_fits(context, text, at, maxWidth, 1)) {
          chosen = at;
          settled = true;
          break;
        }
      }

      if (!settled && lines >= 2) {
        // Two lines, as large as two lines can be set here.
        for (var at = size; at >= _floor; at -= 1) {
          if (_fits(context, text, at, maxWidth, 2)) {
            chosen = at;
            used = 2;
            settled = true;
            break;
          }
        }
      }

      // Nothing fits: the floor, the reserved lines, and an ellipsis.
      if (!settled) {
        chosen = math.min(size, comfort);
        used = lines;
      }
    }

    return SizedBox(
      width: maxWidth,
      child: Text(
        text,
        maxLines: used,
        softWrap: used > 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: styleAt(context, chosen),
      ),
    );
  }
}

/// Which side a half belongs to, written in the corner of the grass.
class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 30, color: tint),
        const SizedBox(width: 12),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: TeamLineupCard._ink.withValues(alpha: 0.92),
            fontSize: 31,
            fontWeight: FontWeight.w800,
            height: 1.1,
            // No tracking: `teamAName` is "الفريق أ" in Arabic.
            shadows: const [Shadow(blurRadius: 8, color: Color(0xCC000000))],
          ),
        ),
      ],
    );
  }
}

/// The ground the whole card is printed on.
///
/// Four things, in order: a near-black base that is warmer at the top than at
/// the foot; a light from above the frame; a pool of emerald under the pitch;
/// and a vignette drawing the corners down. Then a fine grain over all of it —
/// which is what keeps a gradient this large from banding once a messaging app
/// has re-compressed the picture, and what stops the ground reading as a flat
/// fill. The grain is seeded, so the same lineup makes the same file twice.
class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [Color(0xFF0C1215), Color(0xFF070B0E), Color(0xFF04070A)],
          const [0.0, 0.52, 1.0],
        ),
    );

    // The light: above the frame and slightly cool, the way a floodlight falls.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, -size.height * 0.06),
          size.height * 0.52,
          const [Color(0x2A9FE9C6), Color(0x00000000)],
        ),
    );

    // The grass. Painted here rather than inside the pitch, and wider and
    // taller than the pitch is, so the field the players stand on has no edge
    // anywhere: it is brightest where the centre circle is and gone by the time
    // it reaches the type.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, size.height * 0.62),
          size.height * 0.60,
          const [Color(0x4712B36E), Color(0x2612B36E), Color(0x00000000)],
          const [0.0, 0.55, 1.0],
        ),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.height * 0.62,
          const [Color(0x00000000), Color(0x00000000), Color(0x99000000)],
          const [0.0, 0.55, 1.0],
        ),
    );

    final grain = math.Random(20260816);
    final paint = Paint();
    for (var i = 0; i < 2200; i++) {
      paint.color = Color.fromRGBO(
        255,
        255,
        255,
        0.008 + grain.nextDouble() * 0.022,
      );
      canvas.drawCircle(
        Offset(
          grain.nextDouble() * size.width,
          grain.nextDouble() * size.height,
        ),
        1.2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) => false;
}

/// The pitch itself, drawn onto the ground rather than into a frame.
///
/// Real markings in real proportions, taken from a 68 × 105 metre pitch: the
/// penalty area is 40.3 × 16.5, the goal area 18.3 × 5.5, the centre circle
/// 9.15 in radius and the penalty spot 11 from the goal line. Getting these
/// right is most of what separates a football graphic from a rectangle with a
/// circle in it.
///
/// **No box and no fill.** The line work fades towards both goal ends, so the
/// pitch dissolves into the composition instead of ending at a border, and the
/// only fill is a breath of emerald with no edge to it. Strokes are 4–6px in
/// the engine's own units, which is what survives a messaging app's
/// re-compression; a hairline would not.
class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final field = (Offset.zero & size).deflate(3);
    final w = field.width;
    final h = field.height;

    // No grass is painted here. The green belongs to the ground the whole card
    // is printed on — a pitch that fills the frame and is *also* filled with a
    // tone of its own gains an edge exactly where the fill stops, which is the
    // border this drawing spent two passes getting rid of. The atmosphere
    // paints one glow across the lower half of the card instead, and the pitch
    // is line work over it.

    /// White, at [alpha] through the middle of the pitch and weaker towards
    /// both goals. The fade is what removes the frame: the four corners of the
    /// touchline arrive at the edge of the card already half gone.
    Shader fade(double alpha) => ui.Gradient.linear(
          Offset(0, field.top),
          Offset(0, field.bottom),
          [
            Colors.white.withValues(alpha: alpha * 0.18),
            Colors.white.withValues(alpha: alpha * 0.80),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha * 0.80),
            Colors.white.withValues(alpha: alpha * 0.18),
          ],
          const [0.0, 0.20, 0.5, 0.80, 1.0],
        );

    /// The same thing across the pitch, for the two lines that run that way.
    Shader across(double alpha) => ui.Gradient.linear(
          Offset(field.left, 0),
          Offset(field.right, 0),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
          const [0.0, 0.22, 0.78, 1.0],
        );

    final touchline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..shader = fade(0.42);

    final goalLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..shader = across(0.42);

    final marking = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..shader = fade(0.32);

    final dot = Paint()..shader = fade(0.32);

    // Four lines rather than a rectangle, each fading out towards its own two
    // ends. A rectangle closes, and anything that closes around a picture is a
    // border; four lines that dissolve before they meet are a pitch that
    // carries on past the frame.
    canvas.drawLine(field.topLeft, field.bottomLeft, touchline);
    canvas.drawLine(field.topRight, field.bottomRight, touchline);
    canvas.drawLine(field.topLeft, field.topRight, goalLine);
    canvas.drawLine(field.bottomLeft, field.bottomRight, goalLine);

    // The halfway line and the centre circle, where the two teams meet — and
    // the strongest line on the pitch, because the fade is at its full value
    // there.
    final middle = field.center.dy;
    canvas.drawLine(
      Offset(field.left, middle),
      Offset(field.right, middle),
      marking,
    );
    canvas.drawCircle(Offset(field.center.dx, middle), w * 0.135, marking);
    canvas.drawCircle(Offset(field.center.dx, middle), 6, dot);

    // Both ends: penalty area, goal area, penalty spot, the arc off the box,
    // and the goal itself outside the touchline.
    final penaltyWidth = w * 0.59;
    final penaltyDepth = h * 0.157;
    final goalAreaWidth = w * 0.27;
    final goalAreaDepth = h * 0.052;
    final goalWidth = w * 0.108;
    final spotFromLine = h * 0.105;

    for (final top in [true, false]) {
      final edge = top ? field.top : field.bottom;
      final sign = top ? 1.0 : -1.0;

      Rect box(double boxWidth, double depth) => Rect.fromLTWH(
            field.center.dx - boxWidth / 2,
            top ? edge : edge - depth,
            boxWidth,
            depth,
          );

      canvas.drawRect(box(penaltyWidth, penaltyDepth), marking);
      canvas.drawRect(box(goalAreaWidth, goalAreaDepth), marking);

      final spot = Offset(field.center.dx, edge + sign * spotFromLine);
      canvas.drawCircle(spot, 6, dot);

      // The D: the part of the centre-circle-sized arc that falls outside the
      // penalty area. Swept from the spot, clipped to beyond the box.
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(
          field.left,
          top ? edge + penaltyDepth : field.top,
          w,
          top ? h : h - penaltyDepth,
        ),
      );
      canvas.drawArc(
        Rect.fromCircle(center: spot, radius: w * 0.135),
        0,
        sign * math.pi,
        false,
        marking,
      );
      canvas.restore();

      // The goal, standing outside the touchline.
      canvas.drawRect(
        Rect.fromLTWH(
          field.center.dx - goalWidth / 2,
          top ? edge - 15 : edge,
          goalWidth,
          15,
        ),
        touchline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
