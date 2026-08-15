import 'share_card_renderer.dart';

/// What became of a share.
///
/// **Dismissing the sheet is an outcome, not a failure.** A reader who opens
/// the share sheet and changes their mind has done nothing wrong and nothing
/// broke; telling them "sharing failed" would be untrue and would need a
/// dismissal of its own. So it is reported as a value and the screen simply
/// says nothing.
enum ShareOutcome {
  /// The reader picked somewhere to send it.
  shared,

  /// The reader closed the sheet without picking anything.
  dismissed,

  /// The sheet was shown and the platform cannot say what happened. Android
  /// reports this for most shares — it knows an app was chosen, not whether
  /// that app went on to send anything — so it is the common answer rather
  /// than an unusual one, and it is never treated as an error.
  unknown,
}

/// The application's one way of handing a picture to the operating system.
///
/// **One operation, and no destinations.** The product decision is that Go Play
/// does not integrate with messaging apps: the OS share sheet already lists
/// every app the reader has, in their own order, with their own defaults. So
/// there is no `shareToWhatsApp`, no target parameter and no place for one —
/// an implementation that named an application would be a different product
/// decision, not a different implementation.
///
/// Implementations raise a [Failure] rather than a platform exception (OP-5).
abstract interface class ShareService {
  /// Offers [image] to the operating system's share sheet.
  ///
  /// Throws [InfrastructureFailure] when the sheet could not be shown at all.
  /// A sheet that was shown and closed returns [ShareOutcome.dismissed].
  Future<ShareOutcome> shareImage(ShareCardImage image);
}
