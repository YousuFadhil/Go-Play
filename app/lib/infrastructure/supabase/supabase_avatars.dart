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

  /// Where each of [userIds] keeps their picture, as URLs, skipping the ones
  /// who have none.
  ///
  /// **Why this exists as a second read.** A roster is read through
  /// `v_match_registrations`, whose ordering is the authoritative participant
  /// order (migration `0053`) and which carries the profile columns a roster
  /// needs — but not `avatar_path`. Adding it there is a schema change, and a
  /// face beside a name does not need one: `users.avatar_path` is readable by
  /// exactly the people who can already read `full_name` off the same row, so
  /// this asks for it directly and joins on the client.
  ///
  /// Unversioned, for the reason the team adapter gives: a roster is a
  /// screenful of faces, and busting the cache on every read would refetch all
  /// of them each time it opens.
  ///
  /// An empty [userIds] does not reach the network. A roster of Professional
  /// Guests alone has nobody to look up.
  static Future<Map<String, String>> urlsForUsers(
    SupabaseClient client,
    Iterable<String> userIds,
  ) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return const {};

    final rows = await client
        .from('users')
        .select('id, avatar_path')
        .inFilter('id', ids);

    return {
      for (final row in rows)
        if (publicUrl(client, row['avatar_path'] as String?)
            case final String url)
          row['id'] as String: url,
    };
  }

  static String contentTypeFor(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
