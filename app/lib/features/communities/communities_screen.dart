import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import 'create_community_screen.dart';
import 'community_details_screen.dart';
import 'community_models.dart';
import '../invitations/invite_link.dart';
import 'community_repository.dart';
import 'join_community_flow.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key, this.communityRepository});

  /// Supplying the repository is only for the screen's widget tests; production
  /// keeps using the same repository and overview read it always has.
  final CommunityRepository? communityRepository;

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

typedef _CommunitiesOverview = ({
  List<Community> mine,
  List<Community> discover
});

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  late final _communityRepository =
      widget.communityRepository ?? CommunityRepository();
  late Future<_CommunitiesOverview> _future;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _future = _communityRepository.fetchCommunitiesOverview();
  }

  void _refresh() {
    setState(() {
      _future = _communityRepository.fetchCommunitiesOverview();
    });
  }

  Future<void> _openCreateCommunity() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
    );
    if (created == true) _refresh();
  }

  /// Accepting an invitation adds a membership, so the list must reload.
  /// Fallback for an invitation that arrived as text rather than as a tap —
  /// some messaging apps will not make a `goplay://` link tappable. Handing the
  /// token to PendingInvite routes it exactly like a tapped link would.
  Future<void> _openInviteDialog() async {
    final token = await showDialog<String>(
      context: context,
      builder: (_) => const _OpenInviteDialog(),
    );
    if (token != null) PendingInvite.instance.offer(token);
  }

  Future<void> _openJoinDialog() async {
    // The dialog is fully self-contained (owns its controller and uses its
    // own context), so no parent BuildContext crosses into the dialog
    // subtree. It returns the joined community id, or null if cancelled.
    final joinedId = await showDialog<String>(
      context: context,
      builder: (_) => JoinCommunityDialog(repository: _communityRepository),
    );
    if (joinedId != null) _refresh();
  }

  /// Every community is listed, so Join means two different things: an OPEN
  /// community joins outright, and a CODE_REQUIRED one asks for its code first.
  /// Which of the two, and what each outcome means, lives in
  /// [runJoinCommunity] — Discover offers the same action and the two must not
  /// drift. What stays here is this screen's own business: the spinner on the
  /// row being joined, and reloading the list afterwards.
  Future<void> _join(Community community) async {
    setState(() => _joiningId = community.id);
    try {
      final joined = await runJoinCommunity(
        context,
        repository: _communityRepository,
        communityId: community.id,
        joinPolicy: community.joinPolicy,
      );
      if (joined && mounted) _refresh();
    } finally {
      if (mounted) setState(() => _joiningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ClubHero(
              bar: ClubHeroBar(
                title: l10n.communitiesTitle,
                // A shell screen, on the same rule as Discover and Home.
                showCurrentUserMenu: true,
                actions: [
                  IconButton(
                    tooltip: l10n.inviteOpenAction,
                    icon: const Icon(Icons.link),
                    color: Colors.white,
                    onPressed: _openInviteDialog,
                  ),
                ],
              ),
              identity: Text(
                l10n.myCommunitiesSection,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  color: Colors.white,
                ),
              ),
              action: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('communitiesCreate'),
                      onPressed: _openCreateCommunity,
                      icon: const Icon(Icons.add, size: IconSize.action),
                      label: Text(l10n.createCommunityButton),
                      style: ClubHeroButtons.filled,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('communitiesJoin'),
                      onPressed: _openJoinDialog,
                      icon: const Icon(Icons.key, size: IconSize.action),
                      label: Text(l10n.joinCommunityButton),
                      style: ClubHeroButtons.ghost,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClubSheet(
              child: FutureBuilder<_CommunitiesOverview>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LoadingState();
                  }
                  if (snapshot.hasError) {
                    return ErrorState(onRetry: _refresh);
                  }

                  final mine = snapshot.data?.mine ?? const [];
                  final discover = snapshot.data?.discover ?? const [];

                  if (mine.isEmpty && discover.isEmpty) {
                    return EmptyState(
                      icon: Icons.groups_outlined,
                      message: l10n.communitiesEmpty,
                      action: FilledButton.icon(
                        key: const Key('communitiesEmptyCreate'),
                        onPressed: _openCreateCommunity,
                        icon: const Icon(Icons.add, size: IconSize.action),
                        label: Text(l10n.createCommunityButton),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(200, kButtonHeight),
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Layout.sheetGutter,
                        Layout.sectionAbove,
                        Layout.sheetGutter,
                        Layout.listBottom,
                      ),
                      children: [
                        if (mine.isNotEmpty) ...[
                          _CommunitySection(
                            title: l10n.myCommunitiesSection,
                            count: mine.length,
                          ),
                          for (final community in mine) ...[
                            _CommunityCard(
                              community: community,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CommunityDetailsScreen(
                                    communityId: community.id,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: Layout.cardGap),
                          ],
                        ],
                        if (discover.isNotEmpty) ...[
                          _CommunitySection(
                            title: l10n.publicCommunitiesSection,
                            count: discover.length,
                          ),
                          for (final community in discover) ...[
                            _CommunityCard(
                              community: community,
                              trailing: _joiningId == community.id
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : SizedBox(
                                      width: 88,
                                      child: FilledButton.tonal(
                                        onPressed: _joiningId != null
                                            ? null
                                            : () => _join(community),
                                        child: Text(l10n.joinCommunityButton),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: Layout.cardGap),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunitySection extends StatelessWidget {
  const _CommunitySection({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        bottom: Layout.sectionBelow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: GoColors.outline,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    this.onTap,
    this.trailing,
  });

  final Community community;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Ink(
          padding: const EdgeInsetsDirectional.all(Layout.cardInner),
          decoration: const BoxDecoration(
            color: GoColors.surfaceCard,
            borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
            boxShadow: Elevations.card,
          ),
          child: Row(
            children: [
              CommunityCrest(
                name: community.name,
                logoUrl: community.logoUrl,
                size: 46,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            community.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoType.cardTitle.copyWith(
                              color: GoColors.onSurface,
                            ),
                          ),
                        ),
                        if (community.joinPolicy == JoinPolicy.codeRequired)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(start: Gap.xs),
                            child: Icon(
                              Icons.password,
                              size: IconSize.meta,
                              color: GoColors.outline,
                            ),
                          ),
                      ],
                    ),
                    if (community.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        community.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: GoColors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Gap.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Takes a pasted invitation link (or the bare token inside one) and returns
/// the token. Validation is local and deliberately shallow: whether the
/// invitation is still good is the landing screen's question to ask.
class _OpenInviteDialog extends StatefulWidget {
  const _OpenInviteDialog();

  @override
  State<_OpenInviteDialog> createState() => _OpenInviteDialogState();
}

class _OpenInviteDialogState extends State<_OpenInviteDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final token = InviteLink.parse(_controller.text);
    if (token == null) {
      setState(() => _errorText = context.l10n.inviteInvalidInput);
      return;
    }
    Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.inviteOpenAction),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: l10n.invitePasteHint,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.inviteOpenAction),
        ),
      ],
    );
  }
}
