/// The pieces the product's match surfaces are built from.
///
/// Everything here was already in the app, written out separately on each
/// screen that needed it: four status chips in four files, two identical role
/// chips, a capacity that was a slash between two numbers, and a registration
/// panel private to Match Details. None of those differences meant anything —
/// they were what whoever wrote the screen reached for — and the cost was that
/// the same state looked like a different state depending on where a reader met
/// it.
///
/// One of each, used everywhere, drawn from the frozen Club tokens.
///
/// **Nothing here decides anything.** A chip is told which tone to be, a
/// capacity bar is told how many places are taken, and the registration view is
/// told what the reader's position in the match already is. Every one of those
/// answers is the screen's to work out, because working it out is the product's
/// business and drawing it is not. That separation is what lets these be
/// reskinned later without anybody having to re-read the rules.
library;

import 'package:flutter/material.dart';

import 'design.dart';
import 'l10n.dart';
import 'tokens.dart';
import '../features/matches/match_models.dart';

// --- status and role --------------------------------------------------------

/// What a chip is reporting.
///
/// A tone, not a status: the same [open] chip reports an open match on one
/// screen and an open community on another, and a component that took a
/// [MatchStatus] could not be used for the second.
enum GoChipTone { open, full, completed, reserve, neutral, danger, onHero }

/// A pill that reports state.
///
/// Never interactive. A chip in this product is a reading rather than a
/// control, and the moment one becomes tappable a reader starts trying to tap
/// the others.
class GoStatusChip extends StatelessWidget {
  const GoStatusChip({
    super.key,
    required this.label,
    this.tone = GoChipTone.neutral,
    this.icon,
  });

  final String label;
  final GoChipTone tone;

  /// A glyph before the label — the padlock on a locked match, and little else.
  final IconData? icon;

  ({Color background, Color foreground}) get _skin => switch (tone) {
        GoChipTone.open => (
            background: GoColors.statusOpenBg,
            foreground: GoColors.statusOpenFg,
          ),
        GoChipTone.full => (
            background: GoColors.statusFullBg,
            foreground: GoColors.statusFullFg,
          ),
        GoChipTone.completed => (
            background: GoColors.rowTintDeep,
            foreground: GoColors.onSurfaceVariant,
          ),
        GoChipTone.reserve => (
            background: GoColors.tertiaryContainer,
            foreground: GoColors.onTertiaryContainer,
          ),
        GoChipTone.neutral => (
            background: GoColors.rowTintLight,
            foreground: GoColors.onSurfaceVariant,
          ),
        GoChipTone.danger => (
            background: GoColors.errorContainer,
            foreground: GoColors.onErrorContainer,
          ),
        GoChipTone.onHero => (
            background: const Color.fromRGBO(255, 255, 255, 0.16),
            foreground: const Color(0xFFFFFFFF),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final skin = _skin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: skin.background,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: IconSize.chip, color: skin.foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: GoType.chip.copyWith(color: skin.foreground),
          ),
        ],
      ),
    );
  }
}

/// A person's role, marked as a square.
///
/// A role is a property of a person; a status is a property of a thing. They
/// appear beside each other often enough that the shape has to carry the
/// difference, which is why this is not a [GoStatusChip] with a different
/// colour.
///
/// It draws a label and nothing else. Which label, and whether a reader is
/// allowed to see it at all, stays where it was — this widget has no idea what
/// an owner may do that an admin may not.
class GoRoleChip extends StatelessWidget {
  const GoRoleChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: GoColors.rowTintLight,
        borderRadius: BorderRadius.circular(Radii.roleChip),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        softWrap: false,
        style: GoType.roleChip.copyWith(color: GoColors.onSurfaceVariant),
      ),
    );
  }
}

// --- match state ------------------------------------------------------------

/// How a match's state looks. Not what it *is* — [MatchStatus] and
/// `effectiveStatus` decide that and are untouched.
///
/// Amber rather than grey for a full match is the one judgement encoded here,
/// and it is the direction's: grey said "disabled", and a match that has filled
/// up is a healthy match rather than a broken one.
extension MatchStatePresentation on MatchStatus {
  /// The chip tone that reports this state.
  GoChipTone get chipTone => switch (this) {
        MatchStatus.open => GoChipTone.open,
        MatchStatus.full => GoChipTone.full,
        MatchStatus.completed => GoChipTone.completed,
      };

  /// The date tile's fill, and the ground a status chip sits on.
  Color get stateBackground => switch (this) {
        MatchStatus.open => GoColors.statusOpenBg,
        MatchStatus.full => GoColors.statusFullBg,
        MatchStatus.completed => GoColors.rowTintLight,
      };

  /// What is legible on [stateBackground].
  Color get stateForeground => switch (this) {
        MatchStatus.open => GoColors.primaryDeep,
        MatchStatus.full => GoColors.onWarnContainer,
        MatchStatus.completed => GoColors.outline,
      };

  /// The quieter second colour on a date tile: the weekday and the month.
  Color get stateSoftForeground => switch (this) {
        MatchStatus.open => GoColors.primaryMid,
        MatchStatus.full => GoColors.onWarnContainer,
        MatchStatus.completed => GoColors.outline,
      };

  /// The colour a taken starting place is drawn in.
  Color get capacityFill => switch (this) {
        MatchStatus.open => GoColors.primaryMid,
        MatchStatus.full => GoColors.warn,
        MatchStatus.completed => GoColors.capacityCompleted,
      };
}

// --- capacity ---------------------------------------------------------------

/// How full a match is, as a run of segments.
///
/// One segment per place, so the bar answers the question a player is actually
/// asking — *is there room, and if not how deep is the queue* — which a ring or
/// a continuous bar cannot: at this size neither can show where the starting
/// places end and the reserve begins. That boundary is the 6px gap.
///
/// It is handed four numbers and draws them. It does not know what a reserve
/// is for, when registration closes, or whether the reader has a place; asking
/// it to would be putting the roster rules in a widget that exists to be looked
/// at.
class SegmentedCapacityIndicator extends StatelessWidget {
  const SegmentedCapacityIndicator({
    super.key,
    required this.registered,
    required this.starting,
    this.reserve = 0,
    this.status = MatchStatus.open,
    this.showLabel = true,
    this.compact = false,
  });

  /// How many places are taken, starting and reserve together.
  final int registered;

  /// The playing capacity. Not the registration cap — that is [starting] plus
  /// [reserve].
  final int starting;

  /// The reserve allowance sitting after the starting places.
  final int reserve;

  /// Which colour a taken starting place is drawn in.
  final MatchStatus status;

  /// The `taken/starting` figure at the end. Isolated left-to-right, because a
  /// ratio inside an Arabic line is a neutral-first run and would otherwise be
  /// reordered into nonsense.
  final bool showLabel;

  /// Thinner, for a bar that sits inside a card in a list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 5.0 : 7.0;

    // Clamped rather than trusted. These are counts read from a roster and the
    // widget is the last place that should throw because one of them is a
    // place larger than the match: a bar that draws nothing is a bad bar, and
    // a crash is a bad screen.
    final places = starting < 0 ? 0 : starting;
    final spare = reserve < 0 ? 0 : reserve;
    final taken = registered < 0 ? 0 : registered;

    final filledStart = taken < places ? taken : places;
    final filledReserve = switch (taken - places) {
      final int over when over <= 0 => 0,
      final int over when over > spare => spare,
      final int over => over,
    };

    Widget segment(Color colour) => Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );

    final bars = <Widget>[];
    void add(int count, Color colour) {
      for (var i = 0; i < count; i++) {
        if (bars.isNotEmpty) bars.add(const SizedBox(width: 2.5));
        bars.add(segment(colour));
      }
    }

    add(filledStart, status.capacityFill);
    add(places - filledStart, GoColors.capacityTrack);
    if (spare > 0) {
      // The one gap that means something: everything after it is a queue
      // rather than a place on the pitch.
      bars.add(const SizedBox(width: 6));
      add(filledReserve, GoColors.tertiary);
      add(spare - filledReserve, GoColors.capacityTrackReserve);
    }

    return Row(
      children: [
        Expanded(child: Row(children: bars)),
        if (showLabel) ...[
          const SizedBox(width: Gap.md),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '$taken/$places',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w600,
                color: GoColors.onSurfaceVariant,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// --- registration -----------------------------------------------------------

/// Where this player stands in this match, and the one action that follows.
///
/// Lifted out of Match Details unchanged. Every condition it branches on is
/// still worked out by the screen and handed over as a `bool`: whether the
/// reader holds a registration, whether the match has hit its cap, whether the
/// starting places have gone. That is deliberate to the point of being awkward
/// — it would read better if this widget took the roster and worked it out —
/// and it is awkward on purpose, because those three answers are the roster
/// rules and the roster rules are not a widget's to hold.
///
/// The signed-out reader and the Professional Guest never reach this widget as
/// a registration: the screen's own guard is what decides that a seat with no
/// account is nobody's, and moving that guard in here is exactly the mistake
/// this arrangement prevents.
class RegistrationStateView extends StatelessWidget {
  const RegistrationStateView({
    super.key,
    required this.myRegistration,
    required this.registrationClosed,
    required this.startingFull,
    required this.busy,
    required this.onJoin,
    required this.onWithdraw,
    required this.confirmedCount,
    required this.startingPlayers,
    required this.reserveAllowance,
    this.status = MatchStatus.open,
  });

  /// The reader's own registration, or null when they hold none.
  final MatchRegistration? myRegistration;

  /// The cap has been reached: nobody else may register, reserve included.
  final bool registrationClosed;

  /// The starting places have gone, so a sign-up now joins the queue.
  final bool startingFull;

  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onWithdraw;

  /// What the capacity bar draws. Counts, already worked out by the screen.
  final int confirmedCount;
  final int startingPlayers;
  final int reserveAllowance;

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final registration = myRegistration;

    final children = <Widget>[];

    // The branch order below is the one this screen has always used, kept
    // exactly: holding a registration outranks everything, a closed match is
    // reported before an open one is offered, and the full note is a line above
    // the join button rather than a replacement for it.
    if (registration != null) {
      final isConfirmed = registration.status == RegistrationStatus.confirmed;
      children.addAll([
        _Head(
          icon: isConfirmed ? Icons.check_circle : Icons.hourglass_top,
          // The direction's own colours. A hard-coded hue ignores the theme
          // and, on a tinted surface, lands somewhere the palette never goes.
          colour: isConfirmed
              ? GoColors.statusConfirmedFg
              : GoColors.statusReserveFg,
          title: isConfirmed ? l10n.youAreConfirmed : l10n.youAreReserve,
        ),
        const SizedBox(height: Gap.lg),
        // Withdrawing is not the screen's purpose, so it is outlined rather
        // than filled — but it is the only action here, so it spans the card.
        OutlinedButton.icon(
          onPressed: busy ? null : onWithdraw,
          icon: const Icon(Icons.logout, size: IconSize.row),
          label: Text(l10n.withdrawMatchButton),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(Layout.buttonHeightCompact),
          ),
        ),
      ]);
    } else if (registrationClosed) {
      children.add(_Head(
        icon: Icons.lock_outline,
        colour: GoColors.outline,
        title: l10n.errRegistrationClosed,
      ));
    } else {
      if (startingFull) {
        children.addAll([
          Text(
            l10n.matchFullNote,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: GoColors.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.md),
        ]);
      }
      children.add(FilledButton.icon(
        onPressed: busy ? null : onJoin,
        icon: busy
            ? const SizedBox(
                height: IconSize.row,
                width: IconSize.row,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add, size: IconSize.row),
        label: Text(l10n.joinMatchButton),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Layout.buttonHeightCompact),
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.sm,
        kPageMargin,
        Gap.sm,
      ),
      child: Card(
        // Outlined: this is the one next action on the screen, and the border
        // is what says so without the card having to be a different colour
        // from every other card.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: const BorderSide(color: GoColors.borderCardOutlined, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              const SizedBox(height: Gap.md),
              SegmentedCapacityIndicator(
                registered: confirmedCount,
                starting: startingPlayers,
                reserve: reserveAllowance,
                status: status,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon and sentence at the top of the registration card.
class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.colour, required this.title});

  final IconData icon;
  final Color colour;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: colour),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
