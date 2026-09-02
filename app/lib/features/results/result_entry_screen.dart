import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/club_task.dart';
import 'package:flutter/services.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../communities/community_models.dart';
import '../matches/match_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../members/member_repository.dart';
import '../profile/player_identity.dart';
import '../teams/team_models.dart';
import '../teams/team_repository.dart';
import 'result_models.dart';
import 'result_repository.dart';

/// The result of one match: the score, who scored it, and who was best on the
/// pitch.
///
/// Only an owner or admin gets here, and the screen is a form rather than a
/// report: what a recorded result *did* — the ratings, the counters — belongs to
/// the players it happened to, and this phase surfaces none of it.
///
/// The rules live in `result_models.dart` and in the database, not here. What
/// this screen does with them is arithmetic for the organizer's benefit: the
/// running total of goals is shown against the score so the mismatch is visible
/// before the save rather than after it.
///
/// A result already recorded arrives filled in, and saving it again is a
/// correction — the reversal of the previous ratings and counters and the
/// application of the new ones happen together, inside one transaction, below
/// this screen.
class ResultEntryScreen extends StatefulWidget {
  const ResultEntryScreen({
    super.key,
    required this.matchId,
    this.resultRepository,
    this.teamRepository,
    this.matchService,
    this.memberRepository,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  /// Left null the screen builds the production ones, so nothing here knows what
  /// a data provider is.
  final ResultRepository? resultRepository;
  final TeamRepository? teamRepository;
  final MatchService? matchService;
  final MemberRepository? memberRepository;

  @override
  State<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<ResultEntryScreen> {
  late final ResultRepository _results =
      widget.resultRepository ?? ResultRepository();
  late final TeamRepository _teams = widget.teamRepository ?? TeamRepository();
  late final MatchService _matches = widget.matchService ?? MatchService();
  late final MemberRepository _members =
      widget.memberRepository ?? MemberRepository();

  late Future<_ResultView> _future;

  /// What the organizer has entered so far. Null until the first load has said
  /// what the match already holds; from then on this is what the screen renders
  /// and what a save sends.
  _ResultDraft? _draft;

  /// True from the moment a save is asked for until it has finished, so a second
  /// tap cannot start another one.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ResultView> _load() async {
    final match = await _matches.fetchMatch(widget.matchId);
    final results = await Future.wait([
      _matches.fetchRegistrations(widget.matchId),
      _members.fetchMyRole(match.communityId),
      _teams.fetchLineup(widget.matchId),
      _results.fetchResult(widget.matchId),
    ]);
    final registrations = results[0] as List<MatchRegistration>;
    final lineup = results[2] as List<TeamAssignment>;
    final recorded = results[3] as MatchResult?;

    final view = _ResultView(
      match: match,
      role: results[1] as CommunityRole?,
      lineup: lineup,
      players: {for (final r in registrations) r.participantId: r},
      recorded: recorded,
    );
    _draft = _ResultDraft.from(recorded);
    return view;
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The sentence a refused save gets.
  ///
  /// The branch is on the failure *type*, as OP-5 requires; the reason only
  /// picks which of the validation sentences applies, because the organizer has
  /// to know which number to correct.
  String _saveError(AppLocalizations l10n, Failure failure) {
    if (failure is AuthorizationFailure) return l10n.errNotAuthorized;
    if (failure is ValidationFailure) {
      return switch (failure.reason) {
        FailureReason.goalsDoNotMatchScore => l10n.errGoalsDoNotMatchScore,
        FailureReason.mvpNotParticipant => l10n.errMvpNotParticipant,
        FailureReason.scorerNotParticipant => l10n.errScorerNotParticipant,
        FailureReason.lineupRequired => l10n.errResultNeedsLineup,
        FailureReason.invalidScore ||
        FailureReason.invalidGoals =>
          l10n.errInvalidResultNumbers,
        _ => l10n.errInvalidResultNumbers,
      };
    }
    return l10n.genericError;
  }

  Future<void> _save(_ResultView view) async {
    if (_busy) return;
    final draft = _draft;
    if (draft == null) return;
    final l10n = context.l10n;

    // Correcting a recorded result rewrites what it did to every participant's
    // rating and counters, so it is asked for rather than assumed from a tap.
    if (view.recorded != null && !await _confirmReplace(l10n)) return;
    if (_busy || !mounted) return;
    setState(() => _busy = true);

    final navigator = Navigator.of(context);

    try {
      await _results.recordResult(
        matchId: widget.matchId,
        teamAScore: draft.teamAScore,
        teamBScore: draft.teamBScore,
        mvpUserId: draft.mvpUserId,
        goals: draft.tallies,
        lineup: view.lineup,
      );
      // Done: this form has nothing left to say. It closes and reports the save
      // to the match, which is the screen that can show what the save actually
      // did — the confirmation belongs beside the result rather than over the
      // form that produced it.
      //
      // Reported by returning true rather than announced here, and only on
      // success: a refused save stays on the form with the organizer's numbers
      // still in it, because there is a correction to make and nowhere else to
      // make it.
      if (mounted) navigator.pop(true);
      return;
    } on Failure catch (failure) {
      _showMessage(_saveError(l10n, failure));
    } catch (_) {
      _showMessage(l10n.genericError);
    }

    if (mounted) {
      setState(() => _busy = false);
      // Only reached when the save was refused. What is shown next comes from a
      // fresh read: a save that failed part-way leaves a state only the database
      // knows.
      _reload();
    }
  }

  Future<bool> _confirmReplace(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editResultConfirmTitle),
        content: Text(l10n.editResultConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.saveResultButton),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<_ResultView>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _taskScaffold(const LoadingState());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _taskScaffold(ErrorState(onRetry: _reload));
        }

        final view = snapshot.data!;
        if (!view.canRecord) {
          return _taskScaffold(_notice(l10n.resultOrganizersOnly));
        }
        if (view.lineup.isEmpty) {
          return _taskScaffold(_notice(l10n.errResultNeedsLineup));
        }

        final draft = _draft!;
        return Scaffold(
          appBar: ClubTaskBar(title: l10n.matchResultTitle),
          body: ClubTaskBody(child: _form(l10n, view)),
          bottomNavigationBar: ClubActionBar(
            child: FilledButton(
              onPressed: _busy || !draft.isComplete ? null : () => _save(view),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Layout.buttonHeight),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.saveResultButton),
            ),
          ),
        );
      },
    );
  }

  Widget _taskScaffold(Widget body) => Scaffold(
        appBar: ClubTaskBar(title: context.l10n.matchResultTitle),
        body: ClubTaskBody(child: body),
      );

  Widget _notice(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );

  Widget _form(AppLocalizations l10n, _ResultView view) {
    final draft = _draft!;
    final balanced = draft.recordedGoals == draft.totalScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, Gap.sm),
          child: Text(
            view.match.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _scoreRow(l10n, draft),
        // Only while the goals add up. When they do not, the banner below says
        // this same sentence in the same words, and printing it twice — once
        // in red here and once in the banner — states the fault twice without
        // making it any clearer.
        if (balanced)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, Gap.sm, 4, 0),
            child: Text(
              l10n.goalsRecordedNote(draft.recordedGoals, draft.totalScore),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!balanced)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Gap.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Gap.md,
                  Gap.sm + 3,
                  Gap.md,
                  Gap.sm + 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: Gap.sm + 1),
                    Expanded(
                      child: Text(
                        l10n.goalsRecordedNote(
                          draft.recordedGoals,
                          draft.totalScore,
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Said once, above both sides. The star in each row is the control, and
        // without this the only way to learn it is optional is to try saving
        // without it.
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            4,
            Layout.sectionAbove,
            4,
            Layout.sectionBelow,
          ),
          child: Text(
            l10n.mvpOptionalNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        ..._teamSection(l10n, view, draft, l10n.teamAName, TeamId.a),
        ..._teamSection(l10n, view, draft, l10n.teamBName, TeamId.b),
      ],
    );
  }

  /// The two scores, side by side. `A` and `B` distinguish the sides and carry
  /// nothing else (`KB-D6`), so neither is presented as the home team.
  Widget _scoreRow(AppLocalizations l10n, _ResultDraft draft) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Layout.cardInner - 2,
          Layout.cardInner,
          Layout.cardInner - 2,
          Layout.cardInner,
        ),
        decoration: BoxDecoration(
          color: GoColors.primaryDeep,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Directionality(
          // A score is a neutral-first run. It is always Team A, then Team B,
          // regardless of the surrounding Arabic paragraph direction.
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _scoreField(
                  label: l10n.teamAName,
                  value: draft.teamAScore,
                  key: const Key('teamAScore'),
                  onChanged: (value) =>
                      setState(() => draft.teamAScore = value),
                ),
              ),
              const Padding(
                padding: EdgeInsetsDirectional.symmetric(horizontal: Gap.md),
                child: Text(
                  '–',
                  style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    // Was white at 40%, which on this ground is a grey smudge
                    // between two numbers. It is punctuation, so it stays
                    // quieter than the scores — but it has to be legible to
                    // read as a dash rather than as an artefact.
                    color: Color.fromRGBO(255, 255, 255, 0.75),
                  ),
                ),
              ),
              Expanded(
                child: _scoreField(
                  label: l10n.teamBName,
                  value: draft.teamBScore,
                  key: const Key('teamBScore'),
                  onChanged: (value) =>
                      setState(() => draft.teamBScore = value),
                ),
              ),
            ],
          ),
        ),
      );

  /// One side's score: a tile the number sits in, with the team named above it.
  ///
  /// **The field is opted out of the app's own input decoration, deliberately.**
  /// `buildAppTheme` fills every text field with `surfaceContainerLow` — a
  /// near-white — which is right everywhere a field sits on a page and wrong
  /// here, where the row's ground is `primaryDeep`. This field only ever
  /// overrode the *borders*, so the fill stayed, and a white numeral was being
  /// drawn on a near-white box: the score was there, at 38 points, and could not
  /// be read. That is the defect this fixes.
  ///
  /// The tile is kept rather than removed. A score wants a container — it is
  /// what says these two numbers belong together and are the thing being
  /// entered — so the fill is stated explicitly as white and the numeral is set
  /// in the app's own ink on it. Dark on white is the strongest pair the palette
  /// has, and it reads at a glance on the deep-green slab that frames it.
  ///
  /// The team's name moves out of the decoration and above the tile. As a
  /// floating `labelText` it would sit inside the white box in the white it was
  /// styled with, which is the same defect one layer down.
  ///
  /// Unchanged: a score still cannot express a negative number, because the
  /// keyboard is digits only and the formatter drops everything else.
  Widget _scoreField({
    required Key key,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Color.fromRGBO(255, 255, 255, 0.92),
            ),
          ),
          const SizedBox(height: Gap.sm),
          TextFormField(
            key: key,
            initialValue: '$value',
            decoration: InputDecoration(
              // Stated in full, so none of it is inherited from a theme built
              // for fields on a pale page.
              filled: true,
              fillColor: GoColors.surfaceContainerLowest,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                // The one place a border earns its keep: which of the two
                // numbers is being edited.
                borderSide: const BorderSide(
                  color: GoColors.primaryMid,
                  width: 3,
                ),
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            // The caret and the selection are the theme's `primary` otherwise,
            // which on white is legible but reads as a different green from
            // everything else on this row.
            cursorColor: GoColors.primaryDeep,
            style: const TextStyle(
              fontSize: 40,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
              color: GoColors.onSurface,
            ),
            onChanged: (text) => onChanged(int.tryParse(text) ?? 0),
          ),
        ],
      );

  /// One side of the lineup: every player on it, with their goals and the
  /// control that names them best on the pitch.
  List<Widget> _teamSection(
    AppLocalizations l10n,
    _ResultView view,
    _ResultDraft draft,
    String title,
    TeamId team,
  ) {
    final assignments = [
      for (final assignment in view.lineup)
        if (assignment.team == team) assignment,
    ];

    return [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          4,
          Layout.sectionAbove,
          4,
          Layout.sectionBelow,
        ),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (index, assignment) in assignments.indexed) ...[
              _playerRow(l10n, view, draft, assignment),
              if (index < assignments.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _playerRow(
    AppLocalizations l10n,
    _ResultView view,
    _ResultDraft draft,
    TeamAssignment assignment,
  ) {
    final participantId = assignment.participantId;
    final registration = view.players[participantId];
    final scored = draft.goalsOf(participantId);

    // The goal stepper, for whoever this row belongs to.
    //
    // Built once and used by both branches because scoring is the one thing a
    // Professional Guest does on exactly the same terms as anybody else: the
    // goals recorded have to add up to the score, and a guest's goal is part of
    // that sum or the arithmetic refuses a true result. The tally carries which
    // kind of participant scored it, which is the whole of what the two cases
    // differ by here.
    Widget goalStepper() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('goalMinus_$participantId'),
              tooltip: l10n.removeGoalLabel,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _busy || scored == 0
                  ? null
                  : () => setState(() => draft.setGoals(
                        participantId,
                        scored - 1,
                        isProfessionalGuest: assignment.isProfessionalGuest,
                      )),
            ),
            Text('$scored'),
            IconButton(
              key: Key('goalPlus_$participantId'),
              tooltip: l10n.addGoalLabel,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _busy
                  ? null
                  : () => setState(() => draft.setGoals(
                        participantId,
                        scored + 1,
                        isProfessionalGuest: assignment.isProfessionalGuest,
                      )),
            ),
          ],
        );

    // A Professional Guest played, and this screen says so — the guest avatar in
    // the leading slot and the guest wording below the name, as before.
    //
    // What it now also does is let them be named as a scorer, which
    // `record_match_result` has accepted since migration `0049` and which the
    // score arithmetic depends on. What it still does not do is offer the MVP
    // star: the leading slot stays the guest's avatar rather than becoming a
    // star, and naming a guest best on the pitch is not this cycle's work. No
    // profile link either — a guest holds no account to open.
    if (assignment.isProfessionalGuest) {
      return ListTile(
        key: Key('player_$participantId'),
        leading: const PlayerAvatar(isProfessionalGuest: true),
        title: Text(
          registration == null
              ? l10n.professionalGuestLabel
              : participantLabel(l10n, registration),
        ),
        subtitle: Text(l10n.professionalGuestLabel),
        trailing: goalStepper(),
      );
    }

    final userId = assignment.userId!;

    return ListTile(
      key: Key('player_$userId'),
      // The face sits in the title rather than the leading slot, because the
      // leading slot is the MVP star and the trailing one is the goal stepper.
      // Both are why an organizer opened this screen; neither gives way to a
      // profile link.
      //
      // A lineup row names a player id; the roster is what turns it into a name.
      // A player who left the match after the lineup was stored has no roster
      // row left, and is shown without one rather than dropped.
      title: PlayerIdentityTap(
        key: Key('identity_$userId'),
        userId: userId,
        enabled: !_busy,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Row(
          children: [
            PlayerAvatar(
              avatarUrl: registration?.avatarUrl,
              fullName: registration?.fullName,
              radius: 14,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                registration?.fullName ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      subtitle: Text(l10n.goalsScoredLabel(scored)),
      leading: IconButton(
        key: Key('mvp_$userId'),
        tooltip: l10n.mvpLabel,
        icon: Icon(
          draft.mvpUserId == userId ? Icons.star : Icons.star_border,
          color: draft.mvpUserId == userId
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        // At most one MVP per match: naming somebody is naming them instead of
        // whoever held it, never as well as — and tapping the lit star gives it
        // back to nobody.
        onPressed: _busy ? null : () => setState(() => draft.toggleMvp(userId)),
      ),
      trailing: goalStepper(),
    );
  }
}

/// Everything one build of the screen needs, read in one pass.
class _ResultView {
  const _ResultView({
    required this.match,
    required this.role,
    required this.lineup,
    required this.players,
    required this.recorded,
  });

  final Match match;

  /// The viewer's role in the match's community, or null when they hold none.
  final CommunityRole? role;

  /// Who played (`KB-017`); empty when no lineup was stored.
  final List<TeamAssignment> lineup;

  /// The roster by player id — the only place a name comes from.
  final Map<String, MatchRegistration> players;

  /// The result already recorded, or null when this is the first one.
  final MatchResult? recorded;

  /// Whether to offer the form at all.
  ///
  /// `PD-07`: management is a community role, never a creator privilege, and
  /// `record_match_result` gates the write on the same `admin` role through
  /// `is_match_community_admin`. The database remains what enforces it; this
  /// only decides what is shown.
  bool get canRecord => role?.atLeast(CommunityRole.admin) ?? false;
}

/// What the organizer has entered, before it is a result.
///
/// Mutable on purpose: it is the form's state, and the immutable [MatchResult]
/// is what a save produces from it. Goals live in a map keyed by player so the
/// steppers can reach one directly; a player at zero is absent from it, which is
/// the same shape [MatchResult] keeps.
class _ResultDraft {
  _ResultDraft({
    required this.teamAScore,
    required this.teamBScore,
    required this.mvpUserId,
    required Map<String, GoalTally> goals,
  }) : _goals = goals;

  /// The draft a screen opens with: an empty one, or the result already
  /// recorded, so that correcting it starts from what it says.
  factory _ResultDraft.from(MatchResult? recorded) => _ResultDraft(
        teamAScore: recorded?.teamAScore ?? 0,
        teamBScore: recorded?.teamBScore ?? 0,
        mvpUserId: recorded?.mvpUserId,
        goals: {
          for (final tally in recorded?.goals ?? const <GoalTally>[])
            tally.participantId: tally,
        },
      );

  int teamAScore;
  int teamBScore;

  /// Null until somebody is named, and null again if the organizer clears them.
  /// A result saves either way — this is "at most one MVP per match" seen from
  /// the form.
  String? mvpUserId;

  /// Names [userId] best on the pitch, or clears the choice when they already
  /// hold it.
  ///
  /// Tapping the star that is already lit is the only way back to nobody, and it
  /// has to exist: an organizer who named the wrong player and then decided to
  /// leave it blank would otherwise be stuck with the mistake. Naming somebody
  /// else still replaces rather than adds — there is at most one.
  void toggleMvp(String userId) {
    mvpUserId = mvpUserId == userId ? null : userId;
  }

  /// Keyed by `participantId`, holding the tally itself rather than a bare
  /// count.
  ///
  /// The key is the participant and not the user because a Professional Guest
  /// scores too, and the two identities live in different columns: keying on
  /// user id had nowhere to put a guest, and a shared key space with the wrong
  /// key would let a guest and a player collide. Holding the [GoalTally] rather
  /// than an `int` is what carries *which* of the two identities this is, so a
  /// tally is built once, where the answer is known, instead of being inferred
  /// at save time from a map that never recorded it.
  final Map<String, GoalTally> _goals;

  int get totalScore => teamAScore + teamBScore;

  int get recordedGoals =>
      _goals.values.fold(0, (total, tally) => total + tally.goals);

  int goalsOf(String participantId) => _goals[participantId]?.goals ?? 0;

  /// A participant at zero is removed rather than stored as a zero: a tally
  /// asserts that somebody scored, and the saved result carries no zeroes.
  void setGoals(
    String participantId,
    int goals, {
    bool isProfessionalGuest = false,
  }) {
    if (goals <= 0) {
      _goals.remove(participantId);
      return;
    }
    _goals[participantId] = isProfessionalGuest
        ? GoalTally.professionalGuest(guestId: participantId, goals: goals)
        : GoalTally(userId: participantId, goals: goals);
  }

  List<GoalTally> get tallies => _goals.values.toList();

  /// Whether the save button is worth offering.
  ///
  /// One rule now, not two: the goals have to add up. Naming a best player used
  /// to be the other, and is not — a result with no MVP is a result the database
  /// accepts, so refusing to send it here would be the screen inventing a rule
  /// the product no longer has.
  ///
  /// Everything else is checked where the rules are stated. The point of this is
  /// to stop a round trip that is certain to be refused, not to become a third
  /// copy of them.
  bool get isComplete => recordedGoals == totalScore;
}
