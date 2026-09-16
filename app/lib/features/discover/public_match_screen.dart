import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/states.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import 'discover_models.dart';
import 'discover_repository.dart';
import 'discover_widgets.dart';

/// A match, as a visitor sees it before signing in.
///
/// **What a `/match/{id}` link opens for somebody with no account**, and the
/// counterpart of [PublicCommunityScreen]: it asks the one question a guest is
/// entitled to ask and answers it completely, rather than being a member's
/// match screen with most of it hidden.
///
/// What is on it is what public discovery already publishes about a match —
/// when, where, whose, and how many places are left. There is no roster, no
/// lineup and no result: `0057` keeps who played and what happened behind a
/// session, and a link is not a way around that. A match that has been played
/// therefore has no public page at all, and the reader is offered an account
/// instead of a score.
///
/// Registering still requires one. The button opens the same sign-in sheet
/// every other guest action opens; nothing here registers anybody.
class PublicMatchScreen extends StatefulWidget {
  const PublicMatchScreen({
    super.key,
    required this.matchId,
    this.repository,
    this.authService,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final DiscoverRepository? repository;
  final AuthService? authService;

  @override
  State<PublicMatchScreen> createState() => _PublicMatchScreenState();
}

class _PublicMatchScreenState extends State<PublicMatchScreen> {
  late final DiscoverRepository _repository =
      widget.repository ?? DiscoverRepository();

  late Future<PublicMatch?> _future = _repository.fetchMatch(widget.matchId);

  void _refresh() {
    setState(() {
      _future = _repository.fetchMatch(widget.matchId);
    });
  }

  Future<void> _promptSignIn(String reason) => requireSignIn(
        context,
        reason: reason,
        authService: widget.authService,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      // A plain AppBar and not the AppHeader, for the reason the public
      // community page uses one: that bar carries the signed-in player's face,
      // and there is nobody here to name.
      appBar: AppBar(title: Text(l10n.matchDetailsTitle)),
      body: FutureBuilder<PublicMatch?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _MatchSkeleton();
          }
          if (snapshot.hasError) {
            return ErrorState(onRetry: _refresh);
          }

          final match = snapshot.data;
          // **Not an error, and not offered a retry.** No match here means the
          // link points at something this reader may not open — played,
          // withdrawn, or never real. Retrying would fail again for the same
          // reason, so the reader is told plainly and given the one thing that
          // might actually help.
          if (match == null) {
            return Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  EmptyState(
                    icon: Icons.link_off,
                    title: l10n.publicContentUnavailableTitle,
                    message: l10n.publicContentUnavailable,
                  ),
                  const SizedBox(height: Gap.lg),
                  FilledButton(
                    onPressed: () =>
                        _promptSignIn(l10n.authRequiredRegisterMatch),
                    child: Text(l10n.loginTitle),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xxl),
              children: [
                // The same card the Discover page and the public community
                // page draw a match with. One match is not a different kind of
                // thing because it arrived through a link.
                PublicMatchCard(
                  match: match,
                  actionLabel: l10n.joinMatchButton,
                  onAction: () => _promptSignIn(l10n.authRequiredRegisterMatch),
                ),
                FootNote(l10n.discoverMatchesSubtitle),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The shape of the page, before it arrives.
class _MatchSkeleton extends StatelessWidget {
  const _MatchSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonFade(
      child: Padding(
        padding: EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
        child: Column(
          children: [
            MatchCardSkeleton(),
          ],
        ),
      ),
    );
  }
}
