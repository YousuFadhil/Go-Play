import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/infrastructure/supabase/mappers/community_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/discover_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/match_mapper.dart';
import 'package:go_play/infrastructure/supabase/supabase_community_logos.dart';

/// A community's picture: what it is, how it is drawn, and the order the two
/// halves of changing it happen in.
///
/// The ordering is where the product decision lives. A logo is two things — an
/// object in a bucket and a column pointing at it — and every way of updating
/// them except one leaves a window where the community is showing nothing.
/// That order is asserted here rather than described.
void main() {
  _migrationChecks();

  const bytes = <int>[1, 2, 3];

  Community community({String? logoUrl}) => Community(
        id: 'c1',
        ownerId: 'u9',
        name: 'Al Amerat FC',
        joinPolicy: JoinPolicy.open,
        description: 'Friday football in Al Amerat.',
        logoUrl: logoUrl,
      );

  // --- the model and the row it comes from ----------------------------------

  group('a community carries an optional picture', () {
    test('a row with a logo maps it', () {
      final mapped = communityFromRow(const {
        'id': 'c1',
        'owner_id': 'u9',
        'name': 'Al Amerat FC',
        'description': null,
        'join_policy': 'OPEN',
        'logo_url': 'https://example.test/community-logos/c1/logo-7.png',
      });

      expect(
          mapped.logoUrl, 'https://example.test/community-logos/c1/logo-7.png');
    });

    test('a row with none maps to null rather than to a placeholder', () {
      final mapped = communityFromRow(const {
        'id': 'c1',
        'owner_id': 'u9',
        'name': 'Al Amerat FC',
        'description': null,
        'join_policy': 'OPEN',
        'logo_url': null,
      });

      expect(mapped.logoUrl, isNull);
    });

    test('a row from before the column existed still maps', () {
      // Backward compatibility, stated: every community that predates migration
      // `0061` is read by a client that now asks for the column, and a row that
      // does not carry it must not be a crash.
      final mapped = communityFromRow(const {
        'id': 'c1',
        'owner_id': 'u9',
        'name': 'Al Amerat FC',
        'description': null,
        'join_policy': 'OPEN',
      });

      expect(mapped.logoUrl, isNull);
      expect(mapped.name, 'Al Amerat FC');
    });

    test('withLogo changes the picture and nothing else', () {
      final before = community();
      final after = before.withLogo('https://example.test/x.png');

      expect(after.logoUrl, 'https://example.test/x.png');
      expect(after.id, before.id);
      expect(after.name, before.name);
      expect(after.description, before.description);
      expect(after.joinPolicy, before.joinPolicy);
      expect(after.ownerId, before.ownerId);
      expect(before.logoUrl, isNull, reason: 'the original is untouched');
    });
  });

  // --- the object path is the security boundary ------------------------------

  group('where a logo is stored', () {
    test('the community comes first in the path', () {
      // This is what the storage policies authorize against: the first folder
      // is the community, so the rule can ask about a role in it. A path scoped
      // by the uploader would authorize the wrong thing entirely.
      final path = SupabaseCommunityLogos.pathFor(
        'c1',
        'png',
        now: DateTime.fromMillisecondsSinceEpoch(7),
      );

      expect(path, 'c1/logo-7.png');
      expect(path.split('/').first, 'c1');
    });

    test('a replacement is a new object, never the same name', () {
      final first = SupabaseCommunityLogos.pathFor(
        'c1',
        'png',
        now: DateTime.fromMillisecondsSinceEpoch(1),
      );
      final second = SupabaseCommunityLogos.pathFor(
        'c1',
        'png',
        now: DateTime.fromMillisecondsSinceEpoch(2),
      );

      // The whole of the cache-busting strategy: a new name cannot be served
      // from a cache holding the old picture.
      expect(first, isNot(second));
    });

    test('a URL is read back to the object it names', () {
      expect(
        SupabaseCommunityLogos.pathOf(
          'https://x.supabase.co/storage/v1/object/public/community-logos/c1/logo-7.png',
        ),
        'c1/logo-7.png',
      );
    });

    test('and a URL from anywhere else names nothing', () {
      // Fail closed. A stray object costs storage; deleting the wrong one costs
      // somebody their picture.
      expect(SupabaseCommunityLogos.pathOf(null), isNull);
      expect(SupabaseCommunityLogos.pathOf(''), isNull);
      expect(
        SupabaseCommunityLogos.pathOf(
          'https://x.supabase.co/storage/v1/object/public/avatars/u1/avatar.png',
        ),
        isNull,
      );
      expect(SupabaseCommunityLogos.pathOf('https://example.test/logo.png'),
          isNull);
    });
  });

  // --- the crest -------------------------------------------------------------

  group('the crest', () {
    Future<void> pumpCrest(WidgetTester tester, Widget crest) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Center(child: crest)),
      ));
      await tester.pump();
    }

    testWidgets('with no picture it is the initials', (tester) async {
      await pumpCrest(tester, const CommunityCrest(name: 'Al Amerat FC'));

      expect(find.text('AA'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('with a picture it draws one, clipped to the crest',
        (tester) async {
      await pumpCrest(
        tester,
        const CommunityCrest(
          name: 'Al Amerat FC',
          logoUrl: 'https://example.test/community-logos/c1/logo-7.png',
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url,
          'https://example.test/community-logos/c1/logo-7.png');
      // Cover, so a picture of any proportion fills the square rather than
      // being stretched into a different one.
      expect(image.fit, BoxFit.cover);
      // Rounded square, not a circle: a circle is a person in this product.
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
    });

    testWidgets('a picture that will not load falls back to the initials',
        (tester) async {
      // The test binding answers every image request with a 400, so this is the
      // real error path rather than a simulated one. What must not happen is a
      // broken-image glyph or an empty square.
      await pumpCrest(
        tester,
        const CommunityCrest(
          name: 'Al Amerat FC',
          logoUrl: 'https://example.test/community-logos/c1/missing.png',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AA'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsNothing);
    });

    testWidgets('an empty URL is no picture, not a broken one', (tester) async {
      await pumpCrest(
        tester,
        const CommunityCrest(name: 'Al Amerat FC', logoUrl: ''),
      );

      expect(find.text('AA'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a community with no name keeps its glyph', (tester) async {
      await pumpCrest(tester, const CommunityCrest(name: ''));
      expect(find.byIcon(Icons.groups), findsOneWidget);
    });

    testWidgets('the initials rule is unchanged by any of this',
        (tester) async {
      expect(CommunityCrest.initialsOf('Al Amerat FC'), 'AA');
      expect(CommunityCrest.initialsOf('  spaced   out  '), 'SO');
      expect(CommunityCrest.initialsOf(''), '');
      expect(
        CommunityCrest.initialsOf(
          'The Extremely Long Community Name Football Association Of Muscat',
        ),
        'TE',
      );
    });
  });

  group('a community is a rounded square, a player is a circle', () {
    Future<void> pumpIdentity(WidgetTester tester, Widget identity) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Center(child: identity)),
      ));
      await tester.pump();
    }

    testWidgets('the public community identity draws a square', (tester) async {
      // That surface used to draw a circle — the player's shape, and the one
      // thing the crest's geometry exists to distinguish. One widget draws a
      // community now, so the two cannot diverge again.
      await pumpIdentity(
        tester,
        const PublicCommunityIdentityProbe(
          logoUrl: 'https://example.test/community-logos/c1/logo-7.png',
        ),
      );

      expect(find.byType(CommunityCrest), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('and its initials fallback is the same square', (tester) async {
      await pumpIdentity(tester, const PublicCommunityIdentityProbe());

      expect(find.text('AA'), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);

      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CommunityCrest),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isNotNull,
          reason: 'a rounded square, which a circle cannot carry');
    });

    testWidgets('a player is still a circle', (tester) async {
      // The other half of the contract, asserted beside it so a later change to
      // one shape cannot quietly be applied to both.
      await pumpIdentity(
          tester, const PlayerAvatar(fullName: 'Yousuf Al Amri'));

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byType(ClipRRect), findsNothing);
    });
  });

  // --- every surface that shows a community ---------------------------------

  group('the picture reaches the models each surface reads', () {
    // Coverage of the data paths rather than of eight pumped screens: each
    // crest takes `logoUrl` from exactly one model field, and what could
    // regress is a mapper dropping it, not a widget forgetting to draw it —
    // the widget is asserted once, above.

    test('a public community carries it, for the pages a visitor sees', () {
      final mapped = publicCommunityFromRow(const {
        'id': 'c1',
        'name': 'Al Amerat FC',
        'description': null,
        'member_count': 12,
        'upcoming_match_count': 2,
        'logo_url': 'https://example.test/community-logos/c1/logo-7.png',
      });

      expect(
          mapped.logoUrl, 'https://example.test/community-logos/c1/logo-7.png');
    });

    test('and null where it has none', () {
      final mapped = publicCommunityFromRow(const {
        'id': 'c1',
        'name': 'Al Amerat FC',
        'description': null,
        'member_count': 12,
        'upcoming_match_count': 2,
        'logo_url': null,
      });

      expect(mapped.logoUrl, isNull);
    });

    test('an invitation preview carries it, before anybody signs in', () {
      final preview = invitePreviewFromRow(const {
        'state': 'valid',
        'community_id': 'c1',
        'community_name': 'Al Amerat FC',
        'is_member': false,
        'community_logo_url':
            'https://example.test/community-logos/c1/logo-7.png',
      });

      expect(preview.isValid, isTrue);
      expect(preview.communityLogoUrl,
          'https://example.test/community-logos/c1/logo-7.png');
    });

    test('a preview from before the field existed still maps', () {
      final preview = invitePreviewFromRow(const {
        'state': 'valid',
        'community_id': 'c1',
        'community_name': 'Al Amerat FC',
        'is_member': false,
      });

      expect(preview.communityLogoUrl, isNull);
      expect(preview.communityName, 'Al Amerat FC');
    });

    test("a match carries its community picture on the same join", () {
      // One read, not two: the crest on a match screen costs nothing extra.
      final match = matchFromRow(const {
        'id': 'm1',
        'community_id': 'c1',
        'created_by': 'u9',
        'location': 'Al Amerat Pitch',
        'start_at': '2027-03-06T19:00:00Z',
        'end_at': '2027-03-06T20:30:00Z',
        'starting_players': 10,
        'max_registration': 14,
        'status': 'open',
        'title': 'Friday Night',
        'community': {
          'name': 'Al Amerat FC',
          'logo_url': 'https://example.test/community-logos/c1/logo-7.png',
        },
      });

      expect(match.communityName, 'Al Amerat FC');
      expect(match.communityLogoUrl,
          'https://example.test/community-logos/c1/logo-7.png');
    });

    test('a match read without the join names no community and no picture', () {
      final match = matchFromRow(const {
        'id': 'm1',
        'community_id': 'c1',
        'created_by': 'u9',
        'location': 'Al Amerat Pitch',
        'start_at': '2027-03-06T19:00:00Z',
        'end_at': '2027-03-06T20:30:00Z',
        'starting_players': 10,
        'max_registration': 14,
        'status': 'open',
        'title': 'Friday Night',
      });

      expect(match.communityName, isNull);
      expect(match.communityLogoUrl, isNull);
    });
  });

  // --- the order the two halves happen in ------------------------------------

  group('giving a community a picture', () {
    test('uploads first, then points the community at it', () async {
      final adapter = _RecordingAdapter();
      final repository = CommunityRepository(adapter);

      final url = await repository.changeCommunityLogo(
        communityId: 'c1',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'png',
      );

      expect(url, adapter.uploadedUrl);
      expect(adapter.calls, ['upload', 'set:${adapter.uploadedUrl}']);
      // Nothing was deleted: there was nothing to replace.
      expect(adapter.deleted, isEmpty);
    });

    test('a replacement deletes the old one last, and only then', () async {
      final adapter = _RecordingAdapter();
      final repository = CommunityRepository(adapter);

      await repository.changeCommunityLogo(
        communityId: 'c1',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'png',
        previousLogoUrl: 'https://example.test/community-logos/c1/logo-1.png',
      );

      // The order is the point. Upload, persist, *then* delete — so the
      // community is showing a real picture at every instant.
      expect(adapter.calls, [
        'upload',
        'set:${adapter.uploadedUrl}',
        'delete:https://example.test/community-logos/c1/logo-1.png',
      ]);
    });

    test('when the database refuses, the old picture is still the one',
        () async {
      final adapter =
          _RecordingAdapter(setFailure: const AuthorizationFailure());
      final repository = CommunityRepository(adapter);

      await expectLater(
        repository.changeCommunityLogo(
          communityId: 'c1',
          bytes: Uint8List.fromList(bytes),
          fileExtension: 'png',
          previousLogoUrl: 'https://example.test/community-logos/c1/logo-1.png',
        ),
        throwsA(isA<AuthorizationFailure>()),
      );

      // The old object was never touched — the community goes on showing it.
      expect(
          adapter.deleted,
          isNot(
              contains('https://example.test/community-logos/c1/logo-1.png')));
      // And the orphan nobody is pointing at was cleaned up.
      expect(adapter.deleted, contains(adapter.uploadedUrl));
    });

    test('a failed cleanup does not fail the change', () async {
      final adapter = _RecordingAdapter(
        deleteFailure: const NetworkFailure(),
      );
      final repository = CommunityRepository(adapter);

      // The picture was changed. That the old file could not be swept up is not
      // something to report as "that did not work".
      final url = await repository.changeCommunityLogo(
        communityId: 'c1',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'png',
        previousLogoUrl: 'https://example.test/community-logos/c1/logo-1.png',
      );

      expect(url, adapter.uploadedUrl);
    });
  });

  group('taking the picture away', () {
    test('clears the column first, then removes the object', () async {
      final adapter = _RecordingAdapter();
      final repository = CommunityRepository(adapter);

      await repository.removeCommunityLogo(
        communityId: 'c1',
        previousLogoUrl: 'https://example.test/community-logos/c1/logo-1.png',
      );

      // The reverse of a replacement, for the same reason: by the time the
      // object goes, nothing is pointing at it.
      expect(adapter.calls, [
        'set:null',
        'delete:https://example.test/community-logos/c1/logo-1.png',
      ]);
    });

    test('a refusal leaves the picture where it was', () async {
      final adapter =
          _RecordingAdapter(setFailure: const AuthorizationFailure());
      final repository = CommunityRepository(adapter);

      await expectLater(
        repository.removeCommunityLogo(
          communityId: 'c1',
          previousLogoUrl: 'https://example.test/community-logos/c1/logo-1.png',
        ),
        throwsA(isA<AuthorizationFailure>()),
      );

      expect(adapter.deleted, isEmpty,
          reason: 'nothing is deleted while the community still points at it');
    });

    test('a failed cleanup does not restore a picture nobody asked for',
        () async {
      final adapter = _RecordingAdapter(deleteFailure: const NetworkFailure());
      final repository = CommunityRepository(adapter);

      // Completes. Putting the URL back to tidy storage would return a picture
      // the organizer asked to be rid of, pointing at an object that may not be
      // there.
      await repository.removeCommunityLogo(
        communityId: 'c1',
        previousLogoUrl: 'https://example.test/community-logos/c1/logo-1.png',
      );

      expect(adapter.calls.first, 'set:null');
    });
  });
}

/// A community port that records the order it was used in.
///
/// Only the three logo operations are implemented: this file is about what
/// happens between them, and a fake that answered the rest would invite a test
/// that is really about something else.
class _RecordingAdapter implements CommunityAdapter {
  _RecordingAdapter({this.setFailure, this.deleteFailure});

  final Failure? setFailure;
  final Failure? deleteFailure;

  final List<String> calls = [];
  final List<String> deleted = [];

  String get uploadedUrl =>
      'https://example.test/community-logos/c1/logo-uploaded.png';

  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    calls.add('upload');
    return uploadedUrl;
  }

  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) async {
    calls.add('set:${logoUrl ?? 'null'}');
    if (setFailure != null) throw setFailure!;
  }

  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) async {
    calls.add('delete:$logoUrl');
    if (deleteFailure != null) throw deleteFailure!;
    deleted.add(logoUrl);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s '
          'subject');
}

/// The migration, read as text.
///
/// **These are static assertions and nothing more.** There is no Supabase CLI
/// and no local database in this repository, so nothing here executes SQL or
/// proves an authorization outcome — what they protect is that the statements
/// the security review signed off on are still in the file, and that a later
/// edit cannot quietly drop one. Runtime verification of the owner/admin matrix
/// remains outstanding until the migration is applied somewhere.
void _migrationChecks() {
  final sql =
      File('../supabase/migrations/0061_community_logo.sql').readAsStringSync();

  group('what migration 0061 says (static review, not a runtime result)', () {
    test('it adds a nullable column and grants it', () {
      expect(sql, contains('add column if not exists logo_url text'));
      expect(
          sql,
          contains(
              'grant select (logo_url) on public.communities to authenticated'));
      // Nothing here touches the owner-only table policy.
      expect(sql, isNot(contains('create policy "communities_update_owner"')));
      expect(sql, isNot(contains('alter policy "communities_update_owner"')));
      expect(sql,
          isNot(contains('drop policy if exists "communities_update_owner"')));
    });

    test('the bucket is its own, public, and takes real MIME types', () {
      expect(
          sql, contains("'community-logos', 'community-logos', true, 5242880"));
      expect(
        sql,
        contains("array['image/jpeg', 'image/png', 'image/webp']"),
        reason: 'MIME types, never file extensions',
      );
    });

    test('the write function is hardened', () {
      final fn = sql.substring(
          sql.indexOf('create or replace function public.set_community_logo'));
      expect(fn, contains("set search_path = ''"),
          reason: 'an empty search path, so no name resolves against a schema '
              'a caller controls');
      expect(fn, contains('public.has_community_role('));
      expect(fn, contains('update public.communities c'));
      expect(fn, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(fn, contains("raise exception 'NOT_AUTHORIZED'"));
      // One column, plus the audit stamp. Nothing else is writable through it.
      expect(fn, contains('set logo_url = p_logo_url'));
      expect(
        sql,
        contains(
            'revoke execute on function public.set_community_logo(uuid, text) from anon, public'),
      );
      expect(
        sql,
        contains(
            'grant execute on function public.set_community_logo(uuid, text) to authenticated'),
      );
    });

    test('the folder helper fails closed and is callable by the policies', () {
      expect(sql, contains('returns uuid'));
      expect(sql, contains('exception when others then\n    return null;'));
      expect(
          sql,
          contains(
              'revoke execute on function public.community_logo_folder(text) from anon, public'));
      // The storage policies run as `authenticated` and call it, so the grant
      // is what makes them evaluable at all.
      expect(
          sql,
          contains(
              'grant execute on function public.community_logo_folder(text) to authenticated'));
    });

    test('storage is public to read and organizers-only to write', () {
      expect(
          sql,
          contains(
              'for select\n  to public\n  using (bucket_id = \'community-logos\')'));
      for (final policy in [
        'community_logos_insert_organizer',
        'community_logos_update_organizer',
        'community_logos_delete_organizer',
      ]) {
        expect(sql, contains('create policy "$policy"'));
      }
      // Four evaluations of the community-role predicate: insert, delete, and
      // update twice — its USING and its WITH CHECK.
      expect(
        'public.community_logo_folder(name)'.allMatches(sql).length,
        4,
        reason: 'insert, delete, and update twice — USING and WITH CHECK',
      );
      // Never a blanket write, and never the uploader's own id as the rule.
      expect(sql, isNot(contains('using (true)')));
      expect(sql, isNot(contains('with check (true)')));
      // Not the uploader's own id — that is the avatars rule, and it appears in
      // this file only in the comment contrasting the two. Scoped to the
      // statements so the explanation does not trip the assertion.
      final policies = sql.substring(
        sql.indexOf('drop policy if exists "community_logos_read_all"'),
        sql.indexOf('-- 5) The one way'),
      );
      expect(policies, isNot(contains('auth.uid()::text')));
      // No avatars policy is created, altered or dropped here. The word appears
      // in the commentary explaining why this bucket is separate, which is why
      // this asks about statements rather than about the text.
      expect(sql, isNot(contains('policy "avatars')));
    });

    test('the update policy carries both halves', () {
      final update = sql.substring(
        sql.indexOf('create policy "community_logos_update_organizer"'),
        sql.indexOf('drop policy if exists "community_logos_delete_organizer"'),
      );
      expect(update, contains('using ('));
      expect(update, contains('with check ('));
    });

    test('the public projection carries the logo and nothing else new', () {
      final view = sql.substring(
        sql.indexOf('create or replace view public.v_public_communities'),
        sql.indexOf('comment on view public.v_public_communities'),
      );
      expect(view, contains('c.logo_url'));
      // The columns that were there before, in the order they were in.
      for (final column in [
        'c.id',
        'c.name',
        'c.description',
        'member_count',
        'upcoming_match_count',
        'c.created_at',
      ]) {
        expect(view, contains(column));
      }
      expect(view, contains('where c.is_active'),
          reason: 'the filter is unchanged');
      expect(view, isNot(contains('join_code')));
      expect(view, isNot(contains('owner_id')));
    });

    test('the invitation preview carries it too, with its grants restated', () {
      expect(
          sql,
          contains(
              'drop function if exists public.preview_community_invite(text)'));
      expect(sql, contains('community_logo_url text'));
      expect(
          sql,
          contains(
              'revoke execute on function public.preview_community_invite(text) from public'));
      expect(
        sql,
        contains(
            'grant execute on function public.preview_community_invite(text) to anon'),
        reason: 'an invitation link is read before anybody signs in',
      );
      expect(
        sql,
        contains(
            'grant execute on function public.preview_community_invite(text) to authenticated'),
      );
      // Recreating it was the chance to harden it, and it was taken.
      final invite = sql.substring(
        sql.indexOf('create function public.preview_community_invite'),
      );
      expect(invite, contains("set search_path = ''"));
      expect(invite, contains('from public.communities c'));
      expect(invite, contains('public.is_community_member('));
      // The behaviour it had is the behaviour it keeps.
      expect(invite,
          contains('c.join_code = upper(trim(p_code)) and c.is_active'));
    });
  });
}

/// The community identity the public community page renders.
///
/// A stand-in for that screen's identity row rather than the screen itself: the
/// page reaches a repository and a session, and what is under test is which
/// shape a community is drawn in. The size is the one the page passes.
class PublicCommunityIdentityProbe extends StatelessWidget {
  const PublicCommunityIdentityProbe({super.key, this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) => CommunityCrest(
        name: 'Al Amerat FC',
        logoUrl: logoUrl,
        size: 72,
      );
}
