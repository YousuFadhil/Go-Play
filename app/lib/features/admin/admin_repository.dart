import 'package:supabase_flutter/supabase_flutter.dart';

/// One row in an admin list. The three sections show different things, so each
/// row carries a title, a subtitle and the id to delete — enough to find a
/// record and remove it, which is all these screens are for.
class AdminRow {
  const AdminRow({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isProtected = false,
  });

  final String id;
  final String title;
  final String subtitle;

  /// A System Admin account, which the app may not delete.
  final bool isProtected;
}

/// Data access for the internal administration screens.
///
/// Every method goes through an `admin_*` RPC that checks `is_system_admin()`
/// server-side. Nothing here is authorization: hiding the screens is a
/// convenience, and the database refuses regardless.
class AdminRepository {
  AdminRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Whether the signed-in account may see the administration screens at all.
  Future<bool> isSystemAdmin() async {
    if (_client.auth.currentUser == null) return false;
    try {
      final result = await _client.rpc('is_system_admin');
      return result == true;
    } catch (_) {
      // A failure here must not open the door.
      return false;
    }
  }

  Future<List<AdminRow>> listUsers(String? search) async {
    final rows = await _client
        .rpc('admin_list_users', params: {'p_search': search}) as List<dynamic>;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        AdminRow(
          id: row['id'] as String,
          title: row['full_name'] as String? ?? '',
          subtitle: row['email'] as String? ?? '',
          isProtected: row['is_system_admin'] as bool? ?? false,
        ),
    ];
  }

  Future<List<AdminRow>> listCommunities(String? search) async {
    final rows = await _client.rpc('admin_list_communities',
        params: {'p_search': search}) as List<dynamic>;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        AdminRow(
          id: row['id'] as String,
          title: row['name'] as String? ?? '',
          subtitle: '${row['owner_name'] ?? '—'} · '
              '${row['member_count']} · ${row['match_count']}',
        ),
    ];
  }

  Future<List<AdminRow>> listMatches(String? search) async {
    final rows = await _client
        .rpc('admin_list_matches', params: {'p_search': search}) as List<dynamic>;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        AdminRow(
          id: row['id'] as String,
          title: row['title'] as String? ?? '',
          subtitle: '${row['community_name'] ?? '—'} · '
              '${row['location'] ?? ''} · ${row['registration_count']}',
        ),
    ];
  }

  Future<void> deleteUser(String id) =>
      _client.rpc('admin_delete_user', params: {'p_user_id': id});

  Future<void> deleteCommunity(String id) =>
      _client.rpc('admin_delete_community', params: {'p_community_id': id});

  Future<void> deleteMatch(String id) =>
      _client.rpc('admin_delete_match', params: {'p_match_id': id});
}
