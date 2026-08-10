import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a player's picture lives, and how a stored path becomes a URL.
///
/// Two adapters need this — the profile reads and writes the signed-in player's
/// own picture, and the team adapter reads everybody else's for the pitch — and
/// the bucket name and the cache-busting rule are one fact, not two. Stating it
/// here is what keeps them from drifting.
class SupabaseAvatars {
  const SupabaseAvatars._();

  /// Created by migration `0031`: public for reading, writable only inside a
  /// folder named after the owner's id.
  static const String bucket = 'avatars';

  /// The object name a player's picture is stored under.
  ///
  /// The folder is what the storage policy checks ownership against, and the
  /// fixed file name is what keeps a player to one picture rather than an
  /// accumulating pile of them.
  static String pathFor(String userId, String fileExtension) =>
      '$userId/avatar.$fileExtension';

  /// Where [path] can be fetched from, or null when there is no path.
  ///
  /// A plain URL rather than a signed one: the bucket is public for reading,
  /// an avatar appears beside a name wherever a player does, and signing each of
  /// those would cost a round trip per face for no secret worth keeping.
  ///
  /// [version] busts caches. The object name is stable across uploads, so
  /// without it every client holding the previous picture would keep showing it.
  /// It is only worth passing where a change has just happened — a list of forty
  /// faces wants the cache to work.
  static String? publicUrl(
    SupabaseClient client,
    String? path, {
    bool version = false,
  }) {
    if (path == null || path.isEmpty) return null;
    final url = client.storage.from(bucket).getPublicUrl(path);
    if (!version) return url;
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  static String contentTypeFor(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
