import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import '../profile/player_identity.dart';
import '../results/match_result_card.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import '../teams/match_stage.dart';
import '../teams/match_stage_board.dart';
import 'completed_match_presentation.dart';
import 'football_models.dart';
import 'football_repository.dart';

/// A completed match, as anybody signed in may read it.
///
/// **Read only, and structurally so.** There is no register button, no team
/// generation, no result entry, no roster arrangement and no delete — not
/// hidden behind a role check, but absent from the file. A reader who is not in
/// this community reaches this screen from Discover, and viewing football that
/// has been played must not be a way to acquire a capability that membership
/// grants. The screen holds a [FootballRepository] and the Share Card Engine's
/// two ports, and nothing else; there is no write path in reach of it. That
/// stays true for an owner who arrives here: this route offers what it offers
/// to everybody, and managing a match lives on the member-only Teams screen
/// where the role that permits it is read.
///
/// **The drawing is the product's, not this screen's.** A match looks the same
/// whether a member is looking at their own on the Teams screen or a visitor is
/// looking at somebody else's here: the same dark ground, the same score
/// header, the same two team blocks with the players standing where they
/// played. None of that is restated in this file — [MatchStageBoard] owns it,
/// and both screens hand it a lineup. What differs between them is what may be
/// *done*, which is the difference that ought to differ.
class FootballMatchScreen extends StatefulWidget {
  const FootballMatchScreen({
    super.key,
    required this.matchId,
    this.repository,
    this.renderer,
    this.shareService,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final FootballRepository? repository;

  /// The Share Card Engine's two ports, passed straight through to
  /// [presentShareCard]. Supplied only by tests; this screen composes no card
  /// of its own and adds no renderer, preview or share service.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

  @override
  State<FootballMatchScreen> createState() => _FootballMatchScreenState();
}

class _FootballMatchScreenState extends State<FootballMatchScreen> {
  late final FootballRepository _football =
      widget.repository ?? FootballRepository();

  late Future<_MatchView> _future;

  /// The match as it is on screen, or null while one is loading. What the Share
  /// button pictures, and the reason tapping it reads nothing: the adaptation
  /// happened when the match arrived.
  _MatchView? _shown;

  @override
  void initState() {
    super.initState();
    _future = _track(_load());
  }

  Future<_MatchView> _load() async {
    final detail = await _football.fetchMatchDetail(widget.matchId);
    return _MatchView(
      detail: detail,
      presentation: CompletedMatchPresentation.of(detail),
    );
  }

  /// Whether this screen has already recorded that a saved result was shown.
  /// One per screen instance; a refresh is not a second viewing.
  bool _resultViewRecorded = false;

  /// Keeps [_shown] in step with whichever load is current.
  Future<_MatchView> _track(Future<_MatchView> load) {
    load.then(
      (view) {
        if (!mounted || _future != load) return;
        _recordResultView(view);
        setState(() => _shown = view);
      },
      // Already reported by the builder, which shows the retry.
      onError: (_) {
        if (!mounted || _future != load) return;
        setState(() => _shown = null);
      },
    );
    return load;
  }

  /// Records that a written-up match was actually put in front of the reader.
  ///
  /// **`hasResult` is the whole condition.** This screen shows a completed
  /// match whether or not anybody has written it up; one that has not is a
  /// lineup and a "result pending" note, which is a match viewed and not a
  /// result viewed.
  ///
  /// A reader who is not signed in records nothing, and that is guaranteed
  /// below this line rather than here: `record_product_event` refuses a call
  /// with no session, and the repository swallows the refusal.
  void _recordResultView(_MatchView view) {
    if (_resultViewRecorded || !view.detail.match.hasResult) return;
    _resultViewRecorded = true;
    ProductAnalytics.instance.track(
      ProductEvent.resultViewed,
      matchId: widget.matchId,
      communityId: view.detail.match.communityId,
    );
  }

  void _refresh() {
    final load = _load();
    setState(() {
      _future = load;
      _shown = null;
    });
    _track(load);
  }

  /// Whether there is a lineup to picture right now.
  ///
  /// A match with no stored lineup has nothing on it to send, so the action is
  /// offered but not armed — exactly as it is on the Teams screen before a
  /// lineup exists.
  bool get _canShare => _shown?.presentation.hasLineup ?? false;

  /// Composes the card for what is on screen and hands it to the engine.
  ///
  /// **The same card the Teams screen sends.** [MatchResultCard] is the one
  /// picture of a match the product makes; this reuses it rather than inventing
  /// a public variant, so a result shared from Discover and the same result
  /// shared by a member are the same image.
  ///
  /// **Nothing here reads a repository.** Every value was resolved by
  /// [CompletedMatchPresentation.of] when the match loaded, and the names are
  /// the ones the pitch is already showing.
  Future<void> _shareResult() async {
    final view = _shown;
    if (view == null || !view.presentation.hasLineup) return;

    final presentation = view.presentation;
    final match = view.detail.match;

    // The faces are fetched before the card is composed, not while it is —
    // the same step, and the same helper, that the Teams screen's share takes.
    await precacheShareCardFaces(context, presentation.avatarUrls);
    if (!mounted) return;

    final data = MatchResultCardData(
      lineup: presentation.lineup,
      players: presentation.players,
      names: presentation.names,
      teamAScore: match.teamAScore,
      teamBScore: match.teamBScore,
      goals: presentation.goals,
      mvpParticipantId: presentation.mvpParticipantId,
      communityName: match.communityName,
      matchTitle: match.displayName,
      playedAt: match.startAt,
      hasNaturalGoalkeeper: presentation.hasNaturalGoalkeeper,
    );

    await presentShareCard(
      context,
      template: (context) => MatchResultCard(data: data),
      // Already loaded and already on screen; nothing is read for these.
      matchId: widget.matchId,
      communityId: match.communityId,
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenScale = matchStageScreenScale(context);

    // Dark, because a lineup is a pitch and the Match Stage is where the
    // product draws one. The Club task shell is not used here, for the same
    // reason it is not used on the Teams screen.
    return Scaffold(
      backgroundColor: MatchStage.ground,
      appBar: matchStageAppBar(
        context,
        key: const ValueKey('football-match-app-bar'),
        title: l10n.footballMatchTitle,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: IconButton(
              key: const ValueKey('shareCompletedMatchButton'),
              icon: Icon(Icons.ios_share, size: 34 * screenScale),
              tooltip: l10n.shareTeamLineupAction,
              onPressed: _canShare ? _shareResult : null,
            ),
          ),
        ],
      ),
      body: FutureBuilder<_MatchView>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _refresh);
          }

          final view = snapshot.data!;
          return MatchStageGround(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 20),
              children: view.presentation.hasLineup
                  ? _board(l10n, view)
                  : _withoutLineup(l10n, view),
            ),
          );
        },
      ),
    );
  }

  /// The match, drawn the way the product draws a match.
  List<Widget> _board(AppLocalizations l10n, _MatchView view) {
    final match = view.detail.match;
    final presentation = view.presentation;

    return [
      MatchStageBoard(
        lineup: presentation.lineup,
        players: presentation.players,
        nameOf: presentation.nameOf,
        hasNaturalGoalkeeper: presentation.hasNaturalGoalkeeper,
        communityName: match.communityName,
        matchTitle: match.displayName,
        playedAt: match.startAt,
        teamAScore: match.teamAScore,
        teamBScore: match.teamBScore,
        goalsOf: presentation.goalsOf,
        isMvpOf: presentation.isMvpOf,
        // The public-football identity rule, and the whole of what tapping a
        // player does on this route. A registered player opens their hardened
        // football profile; a Professional Guest has no account and opens
        // nothing. There is no management sheet to reach instead — this screen
        // has none, for any reader.
        onTapPlayer: (assignment) {
          final userId = assignment.userId;
          if (userId != null) openPlayerProfile(context, userId);
        },
      ),
      ..._matchFacts(l10n, view),
    ];
  }

  /// When and where it was played, and whether anybody has written it up yet.
  ///
  /// The header already carries the community, the match and the date; this is
  /// the rest of what a reader who was not there needs, set in the stage's own
  /// muted ink so it belongs to the surface rather than to a document pasted
  /// onto it.
  List<Widget> _matchFacts(AppLocalizations l10n, _MatchView view) {
    final match = view.detail.match;

    return [
      if (!match.hasResult)
        _StageNote(
          l10n.resultPendingLabel,
          color: MatchStage.ink,
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.sm,
            kPageMargin,
            0,
          ),
        ),
      _StageNote(
        formatDayAndTimeRange(context, match.startAt, match.endAt),
        padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.sm, kPageMargin, 0),
      ),
      if (match.location.isNotEmpty)
        _StageNote(
          match.location,
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.xs,
            kPageMargin,
            0,
          ),
        ),
    ];
  }

  /// A completed match whose lineup did not survive.
  ///
  /// **No pitch.** An empty one would report that nobody turned up, which is a
  /// different claim from "the teams were not saved". So this state keeps the
  /// roster it has always kept and says plainly why there is no lineup; nothing
  /// assembles two sides out of a roster to fill the space, because who played
  /// beside whom is exactly what was lost.
  List<Widget> _withoutLineup(AppLocalizations l10n, _MatchView view) {
    final match = view.detail.match;

    return [
      const SizedBox(height: Gap.md),
      MatchStageHeader(
        community: match.communityName,
        title: match.displayName,
        playedAt: match.startAt,
        teamAScore: match.teamAScore,
        teamBScore: match.teamBScore,
      ),
      ..._matchFacts(l10n, view),
      if (match.mvp != null) ...[
        const SizedBox(height: Gap.lg),
        _StageHeading(l10n.mvpLabel),
        _ParticipantRow(participant: match.mvp!),
      ],
      const SizedBox(height: Gap.lg),
      _StageHeading(l10n.rosterTitle),
      _StageNote(
        l10n.lineupUnavailable,
        padding: const EdgeInsets.fromLTRB(kPageMargin, 0, kPageMargin, Gap.sm),
        align: TextAlign.start,
      ),
      if (view.detail.roster.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.lg,
            kPageMargin,
            0,
          ),
          child: Text(
            l10n.latestResultsEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MatchStage.ink),
          ),
        )
      else
        for (final entry in view.detail.roster)
          _ParticipantRow(participant: entry.participant),
    ];
  }
}

/// One completed match and the presentation view built from it, held together
/// so a load delivers both or neither.
class _MatchView {
  const _MatchView({required this.detail, required this.presentation});

  final CompletedMatchDetail detail;
  final CompletedMatchPresentation presentation;
}

/// A heading on the dark ground.
class _StageHeading extends StatelessWidget {
  const _StageHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kPageMargin, 0, kPageMargin, Gap.sm),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: MatchStage.ink,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

/// A line of secondary text on the dark ground.
///
/// The stage's own foreground rather than the theme's: this is the one dark
/// surface in the product and the text theme it inherits is the light one, so a
/// colour left to default comes out near-black on deep green.
class _StageNote extends StatelessWidget {
  const _StageNote(
    this.text, {
    required this.padding,
    this.color = MatchStage.inkMuted,
    this.align = TextAlign.center,
  });

  final String text;
  final EdgeInsets padding;
  final Color color;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text,
          textAlign: align,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      );
}

/// A participant, drawn the one way the product draws participants off a pitch.
///
/// A registered player opens their hardened football profile; a Professional
/// Guest opens nothing. That distinction is not restated here — it is
/// [PlayerIdentityTap]'s, which renders its child untouched and unlabelled when
/// there is no user id. Passing `participant.userId` through is the whole of the
/// rule, and a guest's is null.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final FootballParticipant participant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGuest = participant.type == ParticipantType.professionalGuest;

    return PlayerIdentityTap(
      userId: participant.userId,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kPageMargin,
          vertical: Gap.sm,
        ),
        child: Row(
          children: [
            PlayerAvatar(
              avatarUrl: participant.avatarUrl,
              fullName: participant.displayName,
              isProfessionalGuest: isGuest,
              radius: 16,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                participant.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: MatchStage.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
