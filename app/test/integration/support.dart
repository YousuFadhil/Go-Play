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
/// The six accounts below are permanent MVP testing accounts, provisioned by
/// hand. The suite signs in to them and never creates or deletes them, so a run
/// leaves the account list exactly as it found it. Everything a test creates
/// below the account level - communities, matches, registrations - is
/// removed in teardown through delete_community, which cascades.
///
/// Their roles:
///
///   owner    - creates every fixture community and owns it
///   admin    - promoted to admin in the community under test
///   player   - ordinary member
///   player2  - ordinary member, present so capacity scenarios can reach five
///   player3  - ordinary member, the fifth body
///   outsider - the dedicated NON-member, used to prove RLS refuses outsiders
///
/// Five genuine members are what the approved minimum match size costs: with
/// starting_players at 4 (OP-2), producing a reserve needs a fifth registrant.
/// `outsider` is not that fifth body - it is only ever added to a community by
/// a test that is specifically exercising a role or authorization rule.
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
        '(${e.message}). These six accounts are fixtures: create the missing '
        'one once, with the suite password, rather than letting a test run '
        'add users to the project.');
  }

  final user = response.user;
  expect(user, isNotNull, reason: 'No session for $email.');
  return TestUser(label, client, user!.id, name);
}

/// A community owned by [owner], cleaned up by [disposeCommunity].
Future<String> createCommunity(TestUser owner, String name,
    {String joinPolicy = 'CODE_REQUIRED'}) async {
  final id = await owner.client.rpc('create_community', params: {
    'p_name': name,
    'p_description': null,
    'p_join_policy': joinPolicy,
  });
  return id as String;
}

/// Adds [user] to [communityId] with the given role. Joining always goes
/// through the join code, which is the only way in; a role above player is then
/// granted by the owner, which is the only way roles change.
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
  // Every match has a name; the column is NOT NULL, so the fixture supplies
  // one the way the app makes the organizer supply one.
  String title = 'ITest match',
}) async {
  final start = DateTime.now().toUtc().add(startsIn);
  final row = await organizer.client
      .from('matches')
      .insert({
        'community_id': communityId,
        'created_by': organizer.id,
        'title': title,
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
  'INVALID_TITLE',
  'JOIN_CODE_REQUIRED',
  'INVALID_JOIN_POLICY',
  'LINEUP_REQUIRED',
  'INVALID_SCORE',
  'INVALID_GOALS',
  'GOALS_DO_NOT_MATCH_SCORE',
  'MVP_NOT_PARTICIPANT',
  'SCORER_NOT_PARTICIPANT',
  // Correcting a match that has already been played (migration 0029).
  // MATCH_NOT_COMPLETED is listed before MATCH_COMPLETED would match it: the
  // scan is by substring, and neither token contains the other, but the order
  // keeps the intent readable.
  'MATCH_NOT_COMPLETED',
  'RESULT_PARTICIPANT_REMOVED',
  'INVALID_TEAM',
  'INVALID_POSITION',
  // Professional Guests (migrations 0047, 0049).
  'INVALID_GUEST_NAME',
  'GUEST_NOT_FOUND',
  'INVALID_MVP',
  // Administrative roster arrangement (migration 0053).
  'ROSTER_MISMATCH',
  'INVALID_SWAP',
  'ROSTER_ORDER_MODE_LOCKED',
];
