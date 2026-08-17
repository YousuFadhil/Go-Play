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

  /// The quietest thing on the card that is still meant to be read. The fixture
  /// has three ranks now — day, then clock and place — and a hierarchy needs a
  /// third tone as much as it needs a third size.
  static const _inkDim = Color(0x66FFFFFF);

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
          // Deeper at both ends than a print margin needs to be. This picture
          // is looked at in a Story, where the app that shows it puts its own
          // furniture across the top and the bottom of the frame; the kicker
          // and the signature are the two things that would sit under it.
          padding: const EdgeInsets.only(top: 84, bottom: 76),
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
        // The masthead: the shape of the match at one end of a rule, the clock
        // at the other, and the width of the page between them. It is a
        // newspaper's device and it does three things at once — it puts a top
        // edge on the picture, it carries the two pieces of fixture that are
        // shortest, and it leaves the middle of the header for the subject.
        _Masthead(format: format, clock: clock),
        const SizedBox(height: 30),
        if (name case final String name) ...[
          _Subject(name: name),
          // A clear step down before the rest of the fixture. The subject needs
          // air beneath it more than the line under it needs to be close: the
          // gap is what tells the eye where the headline ends.
          const SizedBox(height: 20),
        ],
        if (day != null || place != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (day case final String day) Flexible(child: _Aside(text: day)),
              if (day != null && place != null) const _Diamond(),
              if (place case final String place)
                Flexible(child: _Aside(text: place)),
            ],
          ),
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
        color: TeamLineupCard._inkDim,
        fontSize: 27,
        fontWeight: FontWeight.w500,
        height: 1.25,
      ),
    );
  }
}

/// The masthead: the format at the start of a rule, the clock at the end.
///
/// **A newspaper's device, doing a newspaper's job.** The rule puts a top edge
/// on the picture without a heading having to; the two shortest pieces of
/// fixture ride it, which keeps them out of the way of the subject; and the
/// format sits where a reader looks first — strong enough to be read at a
/// glance, small enough that it never competes with the name underneath.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.format, required this.clock});

  final String? format;
  final List<String> clock;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (format case final String format) ...[
          Text(
            format,
            // Digits against digits: it reads the same way in both languages.
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: TeamLineupCard._accent,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 22),
        ],
        const Expanded(
          child: SizedBox(
            height: 3,
            child: CustomPaint(painter: _MastheadRulePainter()),
          ),
        ),
        if (clock.isNotEmpty) ...[
          const SizedBox(width: 22),
          _Clock(parts: clock),
        ],
      ],
    );
  }
}

/// The rule itself: brightest where the format leaves it and quietest where the
/// clock picks it up, so the line reads as one movement across the page.
class _MastheadRulePainter extends CustomPainter {
  const _MastheadRulePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          const [Color(0x8A3DDC84), Color(0x1FFFFFFF), Color(0x14FFFFFF)],
          const [0.0, 0.32, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _MastheadRulePainter oldDelegate) => false;
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

/// The product's signature: a hairline, then a play mark and the name, once,
/// at the foot.
///
/// **A signature, not a logo.** The card is the community's, and the product
/// signs it the way a studio signs a poster — small, at the bottom edge, in the
/// same accent that runs through the rest of the picture. The mark beside the
/// name is a play triangle: the shape the product is named for, drawn rather
/// than fetched, so nothing here is an asset that could belong to somebody
/// else.
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
        const SizedBox(height: 22),
        // The mark and the name are one thing and it reads left to right, so
        // the row is pinned rather than inherited: an Arabic card would
        // otherwise put the triangle after the name and point it backwards.
        Row(
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 17,
              height: 19,
              child: CustomPaint(painter: _PlayMarkPainter()),
            ),
            const SizedBox(width: 15),
            Text(
              label.toUpperCase(),
              // A name, not a sentence: it reads left to right in both
              // languages, and Latin capitals are the one place tracking is
              // safe.
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: TeamLineupCard._inkFaint,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The play triangle that signs the card.
class _PlayMarkPainter extends CustomPainter {
  const _PlayMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = TeamLineupCard._accent);
  }

  @override
  bool shouldRepaint(covariant _PlayMarkPainter oldDelegate) => false;
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

/// Where a point on the pitch lands once the camera is behind the near goal.
///
/// **One projection, and everything on the card obeys it.** The touchlines, the
/// boxes, the mown bands, the two goals and every player are placed through
/// this, which is what makes the depth read as a camera rather than as a
/// drawing with a few slanted lines in it.
///
/// [u] runs 0 at the left touchline to 1 at the right; [v] runs 0 at the far
/// goal to 1 at the near one. Nothing outside this class knows how the picture
/// is projected.
@immutable
class _Camera {
  const _Camera({required this.size});

  final Size size;

  /// How much smaller the far end of the pitch is drawn than the near end.
  ///
  /// **Enough depth to be a camera, not enough to be a hierarchy.** Further
  /// down the scale — a third, a half — the two sides stop being two sides of a
  /// match and become a foreground team and a background team, which is not
  /// what a lineup is. At 0.78 the recession is unmistakable and the far eleven
  /// is still, plainly, an eleven.
  static const _farScale = 0.78;

  /// The near end runs wider than the frame, so the touchlines nearest the
  /// camera leave the picture instead of stopping inside it.
  static const _nearPitch = 1.13;

  /// The band the players stand in, which is not the width of the pitch: nobody
  /// is drawn on the touchline, and this is what keeps the outermost name
  /// inside the margin the type is set to.
  static const _nearPlayers = 0.87;

  double get _centre => size.width / 2;

  /// Depth eases as it recedes, so rows bunch towards the far goal the way they
  /// do down a real camera's barrel.
  double _depth(double v) => math.pow(v.clamp(0.0, 1.0), 1.07).toDouble();

  double scaleAt(double v) => _farScale + (1 - _farScale) * _depth(v);

  /// The goal lines stand off the ends of the stage: the far one clear of the
  /// fixture above it, the near one clear of the signature below.
  static const _padFar = 52.0;
  /// The near end takes the deeper margin: it is the end whose keeper carries
  /// a name under them, and the end the signature sits below.
  static const _padNear = 62.0;

  double yAt(double v) =>
      _padFar + (size.height - _padFar - _padNear) * _depth(v);

  double pitchWidthAt(double v) => size.width * _nearPitch * scaleAt(v);

  double playerBandAt(double v) => size.width * _nearPlayers * scaleAt(v);

  Offset project(double u, double v) =>
      Offset(_centre + (u - 0.5) * pitchWidthAt(v), yAt(v));

  /// Where the [index]th of [count] players in a row at depth [v] stands.
  double playerX(int index, int count, double v) {
    final band = playerBandAt(v);
    return _centre - band / 2 + band * (index + 0.5) / count;
  }
}

/// The room the pitch is given, and the pitch built to fill it.
///
/// The stage takes the whole width of the picture and whatever height the
/// composition leaves it — a community with a two-line name leaves less — and
/// the camera works in those units. Nothing here is a fixed drawing squeezed
/// into a variable box.
class _PitchStage extends StatelessWidget {
  const _PitchStage({required this.data});

  final TeamLineupCardData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return _Pitch(data: data, camera: _Camera(size: size));
      },
    );
  }
}

/// One pitch, both teams, facing each other down the length of it.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.data, required this.camera});

  final TeamLineupCardData data;
  final _Camera camera;

  /// The depths the two sides occupy. Team A defends the far goal and Team B
  /// the near one, and neither reaches its goal line or the halfway line: a
  /// keeper stands off their line, and two attacks do not stand on top of each
  /// other.
  static const _aFrom = 0.06;
  static const _aTo = 0.42;
  static const _bFrom = 0.58;
  static const _bTo = 0.94;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final a = _Half.of(data, TeamId.a, towardsTop: true);
    final b = _Half.of(data, TeamId.b, towardsTop: false);

    final rows = <_Row>[
      ..._depths(a.rows, _aFrom, _aTo, TeamLineupCard._accent, a.movedFrom),
      ..._depths(b.rows, _bFrom, _bTo, TeamLineupCard._ice, b.movedFrom),
    ];

    final composition = _Composition.solve(
      context: context,
      camera: camera,
      rows: rows,
      names: [
        for (final row in rows)
          for (final assignment in row.players)
            data.names[assignment.participantId] ?? '—',
      ],
    );

    return CustomPaint(
      painter: _PitchPainter(camera: camera),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final row in rows)
            for (final (index, assignment) in row.players.indexed)
              _place(composition, row, index, assignment),
          // The team key: one solid swatch of the side's colour on the grass it
          // defends, at the corner the type margin allows.
          _label(l10n.teamAName, TeamLineupCard._accent, _aFrom, top: true),
          _label(l10n.teamBName, TeamLineupCard._ice, _bTo, top: false),
        ],
      ),
    );
  }

  /// The rows of a half, each pinned to its own depth.
  List<_Row> _depths(
    List<List<TeamAssignment>> rows,
    double from,
    double to,
    Color tint,
    Map<String, Position> movedFrom,
  ) {
    return [
      for (final (index, players) in rows.indexed)
        _Row(
          players: players,
          tint: tint,
          movedFrom: movedFrom,
          v: rows.length == 1
              ? (from + to) / 2
              : from + (to - from) * index / (rows.length - 1),
        ),
    ];
  }

  Widget _place(
    _Composition composition,
    _Row row,
    int index,
    TeamAssignment assignment,
  ) {
    final metrics = composition.at(row.v, hinted: row.hinted);
    final x = camera.playerX(index, row.players.length, row.v);
    final player = data.players[assignment.participantId];

    return Positioned(
      left: x - composition.slotAt(row.v) / 2,
      top: camera.yAt(row.v) - metrics.radius,
      width: composition.slotAt(row.v),
      child: Align(
        alignment: Alignment.topCenter,
        child: TeamLineupPlayerMark(
          // Resolved by the screen. A dash for somebody neither the profiles
          // nor the roster knows.
          name: data.names[assignment.participantId] ?? '—',
          radius: metrics.radius,
          nameSize: metrics.nameSize,
          nameWidth: metrics.nameWidth,
          nameHeight: metrics.nameHeight,
          nameLines: composition.nameLines,
          ratingSize: metrics.ratingSize,
          hintSize: metrics.hintSize,
          // The initials come from the **profile**, never from the resolved
          // name: somebody who left the match after the lineup was stored has
          // no profile and a dash for a name, and lettering a disc with a dash
          // is not initials.
          fullName: player?.fullName,
          avatarUrl: player?.avatarUrl,
          rating: player?.overallRating,
          isProfessionalGuest: assignment.isProfessionalGuest,
          movedFrom: row.movedFrom[assignment.participantId],
          tint: row.tint,
        ),
      ),
    );
  }

  Widget _label(String label, Color tint, double v, {required bool top}) {
    // Inside the touchline at that depth, but never inside the margin the type
    // is set to: the far end of the pitch is narrower than the near end and the
    // corner moves with it.
    final inset = math.max(
      TeamLineupCard._margin,
      (camera.size.width - camera.pitchWidthAt(v)) / 2 + 18,
    );
    return PositionedDirectional(
      start: inset,
      top: top ? math.max(0.0, camera.yAt(v) - 78) : null,
      bottom:
          top ? null : math.max(0.0, camera.size.height - camera.yAt(v) - 10),
      child: _TeamLabel(label: label, tint: tint),
    );
  }
}

/// One line of a formation, at the depth the camera puts it.
@immutable
class _Row {
  const _Row({
    required this.players,
    required this.tint,
    required this.movedFrom,
    required this.v,
  });

  final List<TeamAssignment> players;
  final Color tint;
  final Map<String, Position> movedFrom;
  final double v;

  bool get hinted =>
      players.any((p) => movedFrom.containsKey(p.participantId));
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
}

/// What one mark measures at one depth.
@immutable
class _Metrics {
  const _Metrics({
    required this.radius,
    required this.nameSize,
    required this.nameHeight,
    required this.nameWidth,
    required this.ratingSize,
    required this.hintSize,
  });

  final double radius;
  final double nameSize;
  final double nameHeight;
  final double nameWidth;
  final double ratingSize;
  final double hintSize;

  /// The whole mark, top of the photograph to the foot of the last line.
  double get height => radius * 2 + radius * 0.16 + nameHeight + hintSize * 1.5;
}

/// How large the players are drawn, solved once for the whole card.
///
/// **One size, seen from one camera.** Every mark is the same player-sized
/// object; what differs between them is how far away they are. So a single base
/// size is solved here against every row at once — the tightest gap on the card
/// decides it — and each mark is drawn at that size times its own depth.
///
/// **Two things refuse to recede.** A rating and a name are read rather than
/// looked at, so both are compensated against the projection and floored: the
/// far eleven's numbers stay legible on a phone even though the far eleven's
/// faces are smaller. The compensation is partial on purpose — take it all the
/// way and the depth stops reading; leave it out and eleven a side loses its
/// numbers.
@immutable
class _Composition {
  const _Composition({
    required this.camera,
    required this.baseRadius,
    required this.columns,
    required this.nameLines,
  });

  final _Camera camera;

  /// The size of a mark at the near end of the pitch, where the camera is.
  final double baseRadius;

  /// How many players stand in the widest row on the card.
  final int columns;

  final int nameLines;

  /// A face this large stops reading as a photograph on a poster.
  static const _maxRadius = 62.0;

  /// And below this it stops reading as a face at all.
  static const _minRadius = 20.0;

  /// The name's leading, and the one place it is stated.
  static const _lineHeight = 1.2;

  /// The room one mark is given across at depth [v] — its share of the band the
  /// players stand in, which narrows with the pitch.
  double slotAt(double v) => camera.playerBandAt(v) / columns;

  /// The room a name is given at the far end, which is the tightest on the
  /// card and the width the two-line question is asked against.
  double get nameWidth => slotAt(0) - 30 * camera.scaleAt(0);

  /// [hinted] is whether this row carries anybody drawn out of their line. Only
  /// those rows reserve the note beneath the name: a card where one midfielder
  /// moved should not spend a line of every other row on it, and the rows are
  /// measured against the space in front of them one at a time anyway.
  _Metrics at(double v, {bool hinted = false}) {
    final scale = camera.scaleAt(v);
    final radius = baseRadius * scale;
    final nameSize = (baseRadius * 0.58 * (0.74 + 0.26 * scale))
        .clamp(19.0, 37.0)
        .toDouble();
    final ratingSize = (baseRadius * 0.52 * (0.62 + 0.38 * scale))
        .clamp(20.0, 34.0)
        // Never wider than the face it is set into.
        .clamp(0.0, radius * 0.70)
        .toDouble();
    return _Metrics(
      radius: radius,
      nameSize: nameSize,
      nameHeight: (nameSize * _lineHeight).ceilToDouble() * nameLines,
      nameWidth: slotAt(v) - 30 * scale,
      ratingSize: ratingSize,
      hintSize:
          hinted ? (radius * 0.34).clamp(13.0, 21.0).toDouble() : 0.0,
    );
  }

  /// The largest base size at which no mark runs into the row in front of it,
  /// into the player beside it, or off either end of the pitch.
  static _Composition solve({
    required BuildContext context,
    required _Camera camera,
    required List<_Row> rows,
    required List<String> names,
  }) {
    final columns = math.max(
      1,
      rows.fold(1, (widest, row) => math.max(widest, row.players.length)),
    );
    _Composition candidate(double radius, int lines) => _Composition(
          camera: camera,
          baseRadius: radius,
          columns: columns,
          nameLines: lines,
        );

    bool fits(_Composition composition) {
      for (final (index, row) in rows.indexed) {
        final metrics = composition.at(row.v, hinted: row.hinted);
        final top = camera.yAt(row.v) - metrics.radius;

        // Off the far or the near end of the stage.
        if (top < 0) return false;
        if (index == rows.length - 1 &&
            top + metrics.height > camera.size.height) {
          return false;
        }

        // Into the row in front.
        if (index < rows.length - 1) {
          final next = rows[index + 1];
          final nextTop = camera.yAt(next.v) -
              composition.at(next.v, hinted: next.hinted).radius;
          if (top + metrics.height > nextTop) return false;
        }

        // Into the player alongside.
        final band = camera.playerBandAt(row.v);
        if (metrics.radius * 2 + 12 > band / row.players.length) return false;
      }
      return true;
    }

    // Largest first, and the first size that fits wins — with the second line
    // decided *at that size* rather than inherited from a larger one. The two
    // questions are not independent: a smaller face sets a smaller name, and a
    // smaller name is likelier to fit on one line. Asking them together is what
    // stops the card reserving a line no name on it ends up using, and paying
    // for that line out of every photograph.
    for (var radius = _maxRadius; radius > _minRadius; radius -= 1) {
      final oneLine = candidate(radius, 1);
      final needsTwo = _PlayerName.anyNeedsTwoLines(
        context,
        names,
        size: oneLine.at(rows.first.v).nameSize,
        maxWidth: oneLine.nameWidth,
      );
      final trial = needsTwo ? candidate(radius, 2) : oneLine;
      if (fits(trial)) return trial;
    }
    return candidate(_minRadius, 2);
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
        _Face(
          radius: radius,
          tint: tint,
          avatarUrl: avatarUrl,
          fullName: fullName,
          isProfessionalGuest: isProfessionalGuest,
          rating: rating,
          ratingSize: ratingSize,
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

/// The player's face: the photograph, their team's colour on it, and the number
/// they are rated, all inside one circle.
///
/// **The rating is on the picture, not beside it.** A chip hanging off the
/// corner of a photograph is a component; a figure reversed out of the foot of
/// the picture is what a broadcast graphic does with a number, and it is the
/// same move a shirt number makes. The dark foot of the circle is drawn to
/// carry it, so the number sits on the treatment rather than on whatever the
/// photograph happens to be.
///
/// **The team is on the picture too.** A wash of the side's colour over the
/// lower half of every face, and the ring around it — so a reader sorting
/// twenty-two players into two teams is reading the players themselves rather
/// than hunting for a legend.
class _Face extends StatelessWidget {
  const _Face({
    required this.radius,
    required this.tint,
    required this.avatarUrl,
    required this.fullName,
    required this.isProfessionalGuest,
    required this.rating,
    required this.ratingSize,
  });

  final double radius;
  final Color tint;
  final String? avatarUrl;
  final String? fullName;
  final bool isProfessionalGuest;
  final double? rating;
  final double ratingSize;

  /// What sits behind a photograph that has not loaded, and under one that has.
  static const _base = Color(0xFF0D1614);

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final rating = this.rating;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _base,
        // A ring, not a rim: enough of the team's colour to sort a player at a
        // glance, not so much that twenty-two of them become a page of targets.
        border: Border.all(
          color: tint.withValues(alpha: 0.85),
          width: (radius * 0.062).clamp(2.5, 4.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xC7000000),
            blurRadius: radius * 0.62,
            offset: Offset(0, radius * 0.2),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _content(diameter),
            // The team's colour laid over the foot of the face, and the dark
            // the number is read against. One gradient does both.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xF2000000),
                    const Color(0xB3000000),
                    tint.withValues(alpha: 0.20),
                    const Color(0x00000000),
                  ],
                  stops: const [0.0, 0.16, 0.34, 0.58],
                ),
              ),
            ),
            if (rating != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: radius * 0.08),
                  child: Text(
                    rating.toStringAsFixed(1),
                    // Western digits, as everywhere a rating is written in this
                    // product.
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: tint,
                      fontSize: ratingSize,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -0.5,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Color(0xE6000000)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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

    return Image.network(
      url,
      width: diameter,
      height: diameter,
      fit: BoxFit.cover,
      // A picture that will not load is not an error and not a hole: it is
      // the same player, drawn the way a player without one is drawn.
      errorBuilder: (_, __, ___) => fallback,
      frameBuilder: (_, child, frame, wasSynchronous) =>
          frame == null && !wasSynchronous ? fallback : child,
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
            tint.withValues(alpha: 0.18),
            tint.withValues(alpha: 0.04),
          ],
        ),
      ),
      // Above centre, because the foot of the circle belongs to the rating:
      // initials and the number have to share one round space, and letters
      // sitting on a figure is worse than either of them slightly off centre.
      child: Align(
        alignment: const Alignment(0, -0.22),
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
  /// to be set on one line of [maxWidth] at [size].
  ///
  /// The question the pitch asks before it decides whether to buy a second line
  /// for the whole card. It is asked at the far end of the projection, where
  /// the type is smallest: a name that fits back there fits everywhere.
  static bool anyNeedsTwoLines(
    BuildContext context,
    Iterable<String> names, {
    required double size,
    required double maxWidth,
  }) {
    final comfort = math.max(_floor, size * _comfort);
    for (final name in names) {
      if (!_fits(context, name, comfort, maxWidth, 1)) return true;
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
        // The team's colour, solid, at the size of the type beside it: the
        // label and the players it names are marked with the same swatch, which
        // is what turns a caption into a key.
        Container(width: 26, height: 26, color: tint),
        const SizedBox(width: 14),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: TeamLineupCard._ink.withValues(alpha: 0.95),
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
            // No tracking: `teamAName` is "الفريق أ" in Arabic.
            shadows: const [Shadow(blurRadius: 10, color: Color(0xD9000000))],
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

/// The pitch, drawn from behind the near goal.
///
/// Real markings in real proportions, every one of them run through the same
/// [_Camera] the players are: touchlines that converge, penalty and goal areas
/// that narrow with distance, a centre circle that flattens into an ellipse,
/// mown bands that compress as they recede, and a goal at each end drawn at its
/// own depth. Getting these right is most of what separates a football graphic
/// from a rectangle with a circle in it — and putting them in perspective is
/// what separates a matchday graphic from a tactics board.
///
/// **No box and no fill.** The grass belongs to the ground the whole card is
/// printed on; what is added here is the light behind each goal, painted past
/// the ends of the pitch so it falls off through the frame rather than at it,
/// and line work that fades towards both goals. Strokes are 3–5px in the
/// engine's own units at the near end, which is what survives a messaging app's
/// re-compression; a hairline would not.
class _PitchPainter extends CustomPainter {
  const _PitchPainter({required this.camera});

  final _Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final near = camera.pitchWidthAt(1);

    Offset at(double u, double v) => camera.project(u, v);

    // --- the light each side defends -----------------------------------------
    //
    // Painted well past both ends, so no edge of colour lands anywhere near the
    // end of the pitch.
    for (final (v, colour) in [
      (0.0, TeamLineupCard._accent),
      (1.0, TeamLineupCard._ice),
    ]) {
      canvas.drawRect(
        Rect.fromLTRB(-near, -size.height * 0.3, size.width + near,
            size.height * 1.3),
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(size.width / 2, camera.yAt(v)),
            size.height * 0.54,
            [colour.withValues(alpha: 0.13), colour.withValues(alpha: 0)],
          ),
      );
    }

    // --- the mow -------------------------------------------------------------
    //
    // Eight bands the length of the pitch. They are what tells the eye the
    // ground is receding rather than merely narrowing, and at this alpha they
    // are felt more than seen.
    for (var i = 0; i < 8; i += 2) {
      final v0 = i / 8, v1 = (i + 1) / 8;
      final band = Path()
        ..moveTo(at(0, v0).dx, camera.yAt(v0))
        ..lineTo(at(1, v0).dx, camera.yAt(v0))
        ..lineTo(at(1, v1).dx, camera.yAt(v1))
        ..lineTo(at(0, v1).dx, camera.yAt(v1))
        ..close();
      canvas.drawPath(
        band,
        Paint()..color = Colors.white.withValues(alpha: 0.017),
      );
    }

    // --- the line work -------------------------------------------------------

    /// White at [alpha] through the middle of the pitch and weaker towards both
    /// goals, so nothing ends in a corner.
    Shader fade(double alpha) => ui.Gradient.linear(
          Offset(0, camera.yAt(0)),
          Offset(0, camera.yAt(1)),
          [
            Colors.white.withValues(alpha: alpha * 0.28),
            Colors.white.withValues(alpha: alpha * 0.85),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha * 0.62),
          ],
          const [0.0, 0.3, 0.62, 1.0],
        );

    Paint stroke(double alpha, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..shader = fade(alpha);

    final touchline = stroke(0.34, 4.5);
    final marking = stroke(0.26, 3.5);

    void line(double u0, double v0, double u1, double v1, Paint paint) =>
        canvas.drawLine(at(u0, v0), at(u1, v1), paint);

    // Touchlines, converging towards the far goal. Drawn before the ends so the
    // ends sit on top of them.
    line(0, 0, 0, 1, touchline);
    line(1, 0, 1, 1, touchline);

    // The halfway line and the centre circle, flattened by the camera.
    line(0, 0.5, 1, 0.5, marking);
    canvas.drawOval(
      Rect.fromCenter(
        center: at(0.5, 0.5),
        width: camera.pitchWidthAt(0.5) * 0.27,
        height: (camera.yAt(0.62) - camera.yAt(0.38)) * 0.62,
      ),
      marking,
    );
    canvas.drawCircle(at(0.5, 0.5), 5, Paint()..shader = fade(0.26));

    // Both ends: the goal line, the penalty area, the goal area, the spot and
    // the goal itself, each at its own depth.
    for (final (goalV, boxV, areaV, spotV, sign) in [
      (0.0, 0.135, 0.045, 0.10, 1.0),
      (1.0, 0.865, 0.955, 0.90, -1.0),
    ]) {
      line(0, goalV, 1, goalV, touchline);

      void box(double halfWidth, double depthV) {
        final path = Path()
          ..moveTo(at(0.5 - halfWidth, goalV).dx, camera.yAt(goalV))
          ..lineTo(at(0.5 - halfWidth, depthV).dx, camera.yAt(depthV))
          ..lineTo(at(0.5 + halfWidth, depthV).dx, camera.yAt(depthV))
          ..lineTo(at(0.5 + halfWidth, goalV).dx, camera.yAt(goalV));
        canvas.drawPath(path, marking);
      }

      box(0.295, boxV);
      box(0.135, areaV);
      canvas.drawCircle(at(0.5, spotV), 4.5, Paint()..shader = fade(0.26));

      // The goal, standing off the line and away from the camera.
      final left = at(0.446, goalV);
      final right = at(0.554, goalV);
      final height = 34 * camera.scaleAt(goalV) * sign;
      final frame = Path()
        ..moveTo(left.dx, left.dy)
        ..lineTo(left.dx, left.dy - height)
        ..lineTo(right.dx, right.dy - height)
        ..lineTo(right.dx, right.dy);
      canvas.drawPath(frame, touchline);
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) =>
      oldDelegate.camera.size != camera.size;
}
