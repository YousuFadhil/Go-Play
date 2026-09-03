import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a community's picture lives.
///
/// The counterpart of `SupabaseAvatars`, and deliberately not part of it. The
/// two buckets hold different kinds of thing with different owners: an avatar
/// belongs to the person whose id names its folder, and a logo belongs to a
/// *community*, replaceable by any of its organizers. One helper carrying both
/// rules would have to keep saying which of the two it meant.
class SupabaseCommunityLogos {
  const SupabaseCommunityLogos._();

  /// Created by migration `0061`: public for reading, writable only by an owner
  /// or an admin of the community the first folder names.
  static const String bucket = 'community-logos';

  /// The object name a community's picture is stored under.
  ///
  /// **The community comes first, and that is the security decision.** The
  /// storage policies read this first segment and ask
  /// `has_community_role(<that community>, auth.uid(), 'admin')`. Putting the
  /// uploader's id here instead — the way an avatar path does — would authorize
  /// the wrong thing: an admin could not replace a picture the owner uploaded,
  /// and anybody at all could write into a folder named after themselves.
  ///
  /// **The name is versioned, and that is the caching decision.** An avatar
  /// keeps one fixed name and busts caches with a query string; a logo is read
  /// by people who are not signed in, through a CDN, on pages the app does not
  /// control the caching of. A new object name on every replacement is the one
  /// approach that does not depend on any of them honouring a cache header.
  static String pathFor(
    String communityId,
    String fileExtension, {
    DateTime? now,
  }) {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return '$communityId/logo-$stamp.$fileExtension';
  }

  /// Where [path] can be fetched from.
  ///
  /// Plain and unversioned: the object name already carries the version, so a
  /// query string would add a second one and defeat the caching that versioned
  /// names are what make safe.
  static String publicUrl(SupabaseClient client, String path) =>
      client.storage.from(bucket).getPublicUrl(path);

  /// The object [url] names, or null when it does not name one in this bucket.
  ///
  /// Deletion needs a path and the community carries a URL, so something has to
  /// turn one into the other. It is written to fail closed: a URL from anywhere
  /// else — an old avatar, a link somebody pasted, a bucket renamed under us —
  /// returns null and is simply not deleted. Deleting the wrong object is worse
  /// than leaving a stray one.
  static String? pathOf(String? url) {
    if (url == null || url.isEmpty) return null;
    const marker = '/$bucket/';
    final at = url.indexOf(marker);
    if (at < 0) return null;
    final path = url.substring(at + marker.length);
    // Anything after a `?` is a cache-busting suffix rather than part of the
    // object's name.
    final query = path.indexOf('?');
    final trimmed = query < 0 ? path : path.substring(0, query);
    return trimmed.isEmpty ? null : Uri.decodeComponent(trimmed);
  }

  /// The encoding the bytes are in. The same three the bucket accepts, and the
  /// same fallback the avatar path uses: anything unrecognised is treated as
  /// JPEG, which is what the picker re-encodes to when it resizes.
  static String contentTypeFor(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
