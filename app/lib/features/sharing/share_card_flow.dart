import 'package:flutter/material.dart';

import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'share_card_preview_screen.dart';
import 'share_card_renderer.dart';
import 'share_service.dart';
import 'widget_share_card_renderer.dart';

/// The engine's front door: compose a card, show it, let it be sent.
///
/// This is the whole of what a feature needs to know. A future Player
/// Statistics card, Community Statistics card or Team Lineup card calls this
/// with the widget it wants pictured and is finished:
///
/// ```dart
/// await presentShareCard(
///   context,
///   template: (context) => PlayerStatisticsCard(statistics: statistics),
/// );
/// ```
///
/// **The caller brings the data already loaded.** [template] is a widget, so
/// whatever it shows was fetched by the feature that owns it, through that
/// feature's own repository. The engine has no repository, reads nothing and
/// cannot — which is what keeps one renderer serving three unrelated cards.
///
/// The renderer and the share service are parameters only so that a test can
/// supply its own; nothing in the app passes them.
Future<void> presentShareCard(
  BuildContext context, {
  required ShareCardTemplate template,
  double pixelRatio = 1.0,
  String? matchId,
  String? communityId,
  ShareCardRenderer? renderer,
  ShareService? shareService,
  ShareCardDownloader? downloader,
}) async {
  final l10n = context.l10n;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final cardRenderer = renderer ?? WidgetShareCardRenderer.of(context);

  // Composing a 1080×1920 card takes a moment the reader would otherwise spend
  // wondering whether the button worked. The barrier is dismissible-proof on
  // purpose: it is gone in well under a second either way, and a reader who
  // taps it away mid-compose would be left with a preview arriving over a
  // screen they thought they had returned to.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ComposingDialog(message: l10n.shareCardPreparing),
  );

  ShareCardImage? image;
  Failure? failure;
  try {
    image = await cardRenderer.render(template, pixelRatio: pixelRatio);
  } on Failure catch (thrown) {
    failure = thrown;
  } catch (_) {
    // A template is ordinary widget code and can throw for its own reasons.
    // The reader's situation is the same whatever it was: there is no card.
    failure = const InfrastructureFailure();
  }

  // The barrier goes first and unconditionally, so no path leaves it up.
  if (navigator.mounted) navigator.pop();

  if (image == null) {
    messenger.showSnackBar(SnackBar(
      content: Text(switch (failure) {
        NetworkFailure() => l10n.networkError,
        _ => l10n.errShareCardRender,
      }),
    ));
    return;
  }

  if (!navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ShareCardPreviewScreen(
        image: image!,
        matchId: matchId,
        communityId: communityId,
        shareService: shareService,
        downloader: downloader,
      ),
    ),
  );
}

/// What the reader sees while a card is being composed.
class _ComposingDialog extends StatelessWidget {
  const _ComposingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // A back press must not leave the reader on a screen with an invisible
    // barrier over it; the flow above owns when this closes.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

/// Loads a card's faces into the image cache before the card is composed.
///
/// **The engine gives a template two frames to settle**, which is ample for
/// layout and nowhere near enough for a network image — so a card composed
/// without this shows a blank disc for every player who has a picture. Calling
/// it is the caller's business; every card that draws faces needs it, and the
/// two that draw the same lineup need the same one, which is why it is here
/// rather than beside either of them.
///
/// Best effort, and issued together because the fetches are independent. A
/// picture that will not load is not an error anywhere else in the app either,
/// and the pitch already falls back to a plain disc. `onError` is what keeps
/// that true: without a handler `precacheImage` reports the failure to
/// `FlutterError`, turning a missing photograph into an app-level error.
Future<void> precacheShareCardFaces(
  BuildContext context,
  Iterable<String> urls,
) async {
  final unique = urls.toSet();
  if (unique.isEmpty) return;

  await Future.wait([
    for (final url in unique)
      precacheImage(NetworkImage(url), context, onError: (_, __) {}),
  ]);
}
