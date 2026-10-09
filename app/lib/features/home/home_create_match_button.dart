import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/tokens.dart';
import '../communities/community_models.dart';
import '../communities/community_repository.dart';
import '../communities/create_community_screen.dart';
import '../matches/create_match_screen.dart';

/// The Upcoming Matches shortcut. Eligibility is read only when pressed;
/// the existing create_match RPC remains the final permission check.
class HomeCreateMatchButton extends StatefulWidget {
  const HomeCreateMatchButton({
    super.key,
    required this.communityRepository,
    required this.onCreated,
    this.matchScreenBuilder,
    this.communityScreenBuilder,
  });

  final CommunityRepository communityRepository;
  final VoidCallback onCreated;

  /// Navigation targets can be replaced by lightweight widget-test screens.
  final Widget Function(String communityId)? matchScreenBuilder;
  final Widget Function()? communityScreenBuilder;

  @override
  State<HomeCreateMatchButton> createState() => _HomeCreateMatchButtonState();
}

class _HomeCreateMatchButtonState extends State<HomeCreateMatchButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final managed = await widget.communityRepository.fetchManagedCommunities();
      if (!mounted) return;

      if (managed.isEmpty) {
        final wantsCommunity = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.l10n.createCommunityTitle),
            content: Text(dialogContext.l10n.homeNoManagedCommunities),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(dialogContext.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(dialogContext.l10n.createCommunityTitle),
              ),
            ],
          ),
        );
        if (!mounted || wantsCommunity != true) return;
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                widget.communityScreenBuilder?.call() ??
                const CreateCommunityScreen(),
          ),
        );
        if (mounted && created == true) widget.onCreated();
        return;
      }

      var community = managed.first;
      if (managed.length > 1) {
        final chosen = await showDialog<Community>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text(dialogContext.l10n.homeChooseCommunityForMatch),
            children: [
              for (final option in managed)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(option),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                    child: Text(option.name),
                  ),
                ),
            ],
          ),
        );
        if (!mounted || chosen == null) return;
        community = chosen;
      }

      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              widget.matchScreenBuilder?.call(community.id) ??
              CreateMatchScreen(communityId: community.id),
        ),
      );
      if (mounted && created == true) widget.onCreated();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.genericError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        key: const Key('homeCreateMatch'),
        onPressed: _busy ? null : _open,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(context.l10n.createMatchTitle),
      );
}
