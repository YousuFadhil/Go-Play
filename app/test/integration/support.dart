import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared harness for the integration suite.
///
/// The suite runs against a real Supabase project and is skipped unless both
/// values are supplied:
///
///   flutter test --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///                --dart-define=SUPABASE_ANON_KEY=<publishable key>
///
/// The four accounts below are permanent MVP testing accounts. The suite
/// signs in to them and never creates or deletes them, so a run leaves the
/// account list exactly as it found it. Everything a test creates below the
/// account level - communities, matches, registrations, invitations - is
/// removed in teardown through delete_community, which cascades.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get integrationConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

const skipReason =
    'Integration suite: pass --dart-define=SUPABASE_URL and SUPABASE_ANON_KEY.';

const _password = 'GoPlayIntegration!1';

/// One signed-in participant.
class TestUser {
  TestUser(this.label, this.client, this.id, this.name);

  final String label;
  final SupabaseClient client;
  final String id;
  final String name;
}

/// Signs in the permanent testing account for [label]. It is never created
/// here: a missing account is a setup problem to fix deliberately, not
/// something to paper over by minting a user in the live project.
Future<TestUser> signInTestUser(String label) async {
  // A headless test has no storage for the PKCE flow, and does not need it:
  // these clients hold their session in memory for the length of the run.
  final client = SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  final email = 'goplay.itest.$label@example.com';
  final name = 'ITest ${label[0].toUpperCase()}${label.substring(1)}';

  AuthResponse response;
  try {
    response = await client.auth
        .signInWithPassword(email: email, password: _password);
  } on AuthException catch (e) {
    fail('Could not sign in the permanent testing account $email '
        '(${e.message}). These four accounts are fixtures: create the missing '
        'one once, with the suite password, rather than letting a test run '
        'add users to the project.');
  }

  final user = response.user;
  expect(user, isNotNull, reason: 'No session for $email.');
  return TestUser(label, client, user!.id, name);
}

/// A community owned by [owner], cleaned up by [disposeCommunity].
Future<String> createCommunity(TestUser owner, String name,
    {bool isPrivate = true}) async {
  final id = await owner.client.rpc('create_community', params: {
    'p_name': name,
    'p_description': null,
    'p_is_private': isPrivate,
  });
  return id as String;
}

/// Adds [user] to [communityId] with the given role. Uses the join code for
/// the player case and an invitation otherwise, so the paths under test are
/// the real ones.
Future<void> addMember(
  TestUser owner,
  String communityId,
  TestUser user, {
  String role = 'player',
}) async {
  final row = await owner.client
      .from('communities')
      .select('join_code')
      .eq('id', communityId)
      .single();
  await user.client
      .rpc('join_community_by_code', params: {'p_code': row['join_code']});
  if (role != 'player') {
    await owner.client.rpc('set_member_role', params: {
      'p_community_id': communityId,
      'p_user_id': user.id,
      'p_role': role,
    });
  }
}

/// Inserts a match directly so tests can place it in the past or future.
/// Only an owner or admin may do this, which the insert policy enforces.
Future<String> createMatch(
  TestUser organizer,
  String communityId, {
  required Duration startsIn,
  Duration duration = const Duration(hours: 2),
  int startingPlayers = 10,
  String location = 'ITest pitch',
}) async {
  final start = DateTime.now().toUtc().add(startsIn);
  final row = await organizer.client
      .from('matches')
      .insert({
        'community_id': communityId,
        'created_by': organizer.id,
        'location': location,
        'start_at': start.toIso8601String(),
        'end_at': start.add(duration).toIso8601String(),
        'starting_players': startingPlayers,
      })
      .select('id')
      .single();
  return row['id'] as String;
}

/// Removes a community and everything under it. Safe to call twice.
Future<void> disposeCommunity(TestUser owner, String? communityId) async {
  if (communityId == null) return;
  try {
    await owner.client
        .rpc('delete_community', params: {'p_community_id': communityId});
  } catch (_) {
    // Already gone, or the owner changed during the test; teardown must not
    // mask the failure that actually matters.
  }
}

/// Runs [action] and returns the error code it raised, or 'ALLOW' when it
/// succeeded. Keeps assertions readable.
Future<String> outcomeOf(Future<void> Function() action) async {
  try {
    await action();
    return 'ALLOW';
  } on PostgrestException catch (e) {
    for (final code in _codes) {
      if (e.message.contains(code)) return code;
    }
    return e.message;
  }
}

const _codes = <String>[
  'NOT_AUTHENTICATED',
  'NOT_AUTHORIZED',
  'NOT_COMMUNITY_MEMBER',
  'CANNOT_CHANGE_OWN_ROLE',
  'CANNOT_REMOVE_SELF',
  'CANNOT_REMOVE_OWNER',
  'ALREADY_OWNER',
  'MEMBER_NOT_FOUND',
  'ALREADY_MEMBER',
  'INVITATION_EXISTS',
  'INVITATION_NOT_FOUND',
  'INVITATION_NOT_PENDING',
  'INVITATION_EXPIRED',
  'INVALID_ROLE',
  'COMMUNITY_NOT_FOUND',
  'MATCH_NOT_FOUND',
  'MATCH_CLOSED',
  'MATCH_LOCKED',
  'MATCH_COMPLETED',
  'ALREADY_REGISTERED',
  'NOT_REGISTERED',
  'REGISTRATION_CLOSED',
  'OVERLAPPING_MATCH',
  'MAX_BELOW_REGISTERED',
  'INVALID_TIME_RANGE',
  'INVALID_STARTING_PLAYERS',
  'INVITE_NOT_FOUND',
  'INVITE_REVOKED',
  'INVITE_EXPIRED',
  'INVITE_MATCH_DELETED',
  'MATCH_NOT_IN_COMMUNITY',
];
