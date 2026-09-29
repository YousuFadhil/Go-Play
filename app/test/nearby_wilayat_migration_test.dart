import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'moi_source_reader.dart';

/// Static contract for migration 0094 (nearby discovery, by Wilayat).
///
/// The migration is applied to a project that production shares, so what it may
/// and may not do is pinned against the file itself. Its behaviour was also
/// exercised against a disposable Postgres (roles, RLS, grants, every guard of
/// the setter, the view logic and the rollback); what this keeps true from then
/// on is the *shape* that behaviour depends on: the grants, the guard order,
/// the columns that are not there, and the seed.
void main() {
  const path = '../supabase/migrations/0094_nearby_discovery_wilayat.sql';
  const rollbackPath =
      '../supabase/rollback/0094_nearby_discovery_wilayat_rollback.sql';
  const specPath = '../Docs/reviews/Nearby_Discovery_Frozen_Spec.md';
  const sourcePath =
      '../Docs/reviews/sources/MOI_governorates_wilayats_2022-08-03.xlsx';

  String code(String file) => File(file)
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  final sql = code(path);
  final rollback = code(rollbackPath);
  String flat(String text) => text.replaceAll(RegExp(r'\s+'), ' ');
  final flatSql = flat(sql);

  /// The body of `create [or replace] function public.<name>(...)`, up to the
  /// closing `$$;`.
  String functionText(String source, String name) {
    final start = source
        .indexOf(RegExp('create (or replace )?function public\\.$name\\('));
    if (start < 0) throw StateError('$name is not created');
    final end = source.indexOf('\n\$\$;', start);
    if (end < 0) throw StateError('$name body is not closed');
    return flat(source.substring(start, end));
  }

  /// Positions of [tokens] in [text], failing loudly if any is missing.
  List<int> order(String text, List<String> tokens) => [
        for (final token in tokens)
          () {
            final at = text.indexOf(token);
            expect(at, greaterThanOrEqualTo(0), reason: '$token is missing');
            return at;
          }(),
      ];

  bool ascending(List<int> positions) {
    for (var i = 1; i < positions.length; i++) {
      if (positions[i] <= positions[i - 1]) return false;
    }
    return true;
  }

  test('0094 is the next migration and has a rollback', () {
    final names = Directory('../supabase/migrations')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .where((name) => name.startsWith('0094'))
        .toList();

    expect(names, ['0094_nearby_discovery_wilayat.sql']);
    expect(File(rollbackPath).existsSync(), isTrue);
    expect(
        File('../supabase/migrations/0093_public_community_football_contract.sql')
            .existsSync(),
        isTrue);
  });

  group('reference tables', () {
    test('keyed by the Ministry codes, as smallint', () {
      expect(
          flatSql,
          contains(
              'create table public.governorates ( code smallint primary key'));
      expect(flatSql,
          contains('create table public.wilayats ( code smallint primary key'));
      expect(
          flatSql,
          contains(
              'governorate_code smallint not null references public.governorates (code)'));
      expect(flatSql, contains('search_terms text[] not null default'));
      expect(flatSql, contains('is_active boolean not null default true'));
      expect(flatSql, contains('create index wilayats_governorate_code_idx'));
    });

    test('row level security is on, with a public read policy', () {
      for (final table in ['governorates', 'wilayats']) {
        expect(flatSql,
            contains('alter table public.$table enable row level security'));
        expect(
          flatSql,
          contains(
              'create policy "${table}_select_all" on public.$table for select to anon, authenticated using (true)'),
        );
      }
    });

    test('writes are revoked explicitly, and only SELECT is granted', () {
      for (final table in ['governorates', 'wilayats']) {
        expect(
            flatSql,
            contains(
                'revoke all on public.$table from public, anon, authenticated'));
        expect(flatSql,
            contains('grant select on public.$table to anon, authenticated'));
      }
      // Nothing grants a write on either table, to anybody.
      expect(
        RegExp(r'grant\s+(insert|update|delete|truncate|all)[^;]*public\.(governorates|wilayats)')
            .hasMatch(flatSql),
        isFalse,
      );
      // And no policy but the read one exists on them.
      expect(
        RegExp(r'create policy[^;]*on public\.(governorates|wilayats)\s+for\s+(insert|update|delete|all)')
            .hasMatch(flatSql),
        isFalse,
      );
    });
  });

  group('the seed', () {
    final governorateRows = RegExp(
      r"^\s*\((\d+), '([^']+)', '([^']+)', (\d+)\)[,;]",
      multiLine: true,
    ).allMatches(sql).toList();

    final wilayatRows = RegExp(
      r"^\s*\((\d+), (\d+), '([^']+)', '([^']+)', (?:'\{\}'::text\[\]|array\[([^\]]*)\]::text\[\]), (\d+)\)[,;]",
      multiLine: true,
    ).allMatches(sql).toList();

    test('11 Governorates and 63 Wilayats, every code once', () {
      expect(governorateRows, hasLength(11));
      expect(wilayatRows, hasLength(63));
      expect({for (final m in governorateRows) int.parse(m.group(1)!)},
          {for (var i = 1; i <= 11; i++) i});
      expect({for (final m in wilayatRows) int.parse(m.group(1)!)},
          {for (var i = 1; i <= 63; i++) i});
    });

    test('Sohar is 7, in North Al Batinah, which is 2', () {
      expect(flatSql, contains("(7, 2, 'صحار', 'Sohar'"));
      expect(flatSql, contains("(2, 'شمال الباطنة', 'Al Batinah North', 2)"));
    });

    test('Majees is an alias of Sohar and of nothing else', () {
      final withAlias = [
        for (final m in wilayatRows)
          if ((m.group(5) ?? '').contains('مجيس') ||
              (m.group(5) ?? '').contains('Majees'))
            int.parse(m.group(1)!),
      ];

      expect(withAlias, [7]);
      expect(flatSql, contains("array['مجيس', 'Majees']"));
    });

    test('every Wilayat belongs to one of the 11 Governorates', () {
      final counts = <int, int>{};
      for (final m in wilayatRows) {
        final governorate = int.parse(m.group(2)!);
        expect(governorate, inInclusiveRange(1, 11));
        counts[governorate] = (counts[governorate] ?? 0) + 1;
      }

      expect([for (var g = 1; g <= 11; g++) counts[g]],
          [6, 6, 4, 3, 3, 9, 7, 4, 10, 6, 5]);
    });

    test('the orthography rules were applied', () {
      final seed = wilayatRows.map((m) => m.group(0)!).join() +
          governorateRows.map((m) => m.group(0)!).join();

      expect(seed.contains('ـ'), isFalse, reason: 'no tatweel');
      expect(seed, isNot(contains('الدخلية')));
      expect(seed, isNot(contains('الباطنه')));
      expect(seed, isNot(contains('الشرقيه')));
      expect(seed, isNot(contains('محافظة')),
          reason: 'the prefix is not stored');
      expect(seed, contains('الجبل الأخضر'));
      expect(seed, contains('الداخلية'));
    });
  });

  // The seed is held to the frozen specification, and the specification to the
  // Ministry's own workbook. Nothing here may skip: a checkout without the
  // specification or the source file is a checkout that cannot say its seed is
  // right, and the tests below fail loudly instead.
  group('the seed against the frozen specification and its source', () {
    final governorateSeed = RegExp(
      r"^\s*\((\d+), '([^']+)', '([^']+)', (\d+)\)[,;]",
      multiLine: true,
    ).allMatches(sql).toList();

    final wilayatSeed = RegExp(
      r"^\s*\((\d+), (\d+), '([^']+)', '([^']+)', (?:'\{\}'::text\[\]|array\[([^\]]*)\]::text\[\]), (\d+)\)[,;]",
      multiLine: true,
    ).allMatches(sql).toList();

    String readSpec() {
      final file = File(specPath);
      if (!file.existsSync()) {
        fail('The frozen specification is missing: $specPath. It is the '
            'authoritative source for the 63-Wilayat seed and must be tracked '
            'in Git; this test does not skip without it.');
      }
      return file.readAsStringSync().replaceAll('\r\n', '\n');
    }

    /// The cells of every data row of the appendix table under [heading].
    List<List<String>> appendix(String spec, String heading, int columns) {
      final start = spec.indexOf(heading);
      if (start < 0) fail('The specification has no "$heading"');
      final next = spec.indexOf('\n## ', start + heading.length);
      final section = spec.substring(start, next < 0 ? spec.length : next);
      final rows = <List<String>>[];
      for (final line in section.split('\n')) {
        if (!line.startsWith('|')) continue;
        final cells = line.split('|').map((c) => c.trim()).toList();
        final inner = cells.sublist(1, cells.length - 1);
        if (int.tryParse(inner.first) == null) continue; // header, rule
        expect(inner, hasLength(columns), reason: 'malformed row: $line');
        rows.add(inner);
      }
      return rows;
    }

    // Appendix A: code, Arabic, English, MOI raw spelling.
    List<List<String>> governoratesOf(String spec) =>
        appendix(spec, '## 5. Appendix A', 4);
    // Appendix B: code, region code, Arabic, English, MOI raw spelling if it
    // differs.
    List<List<String>> wilayatsOf(String spec) =>
        appendix(spec, '## 6. Appendix B', 5);

    test('the specification and the Ministry file are in the repository', () {
      expect(File(specPath).existsSync(), isTrue,
          reason: 'the frozen specification must be tracked: $specPath');
      expect(File(sourcePath).existsSync(), isTrue,
          reason: 'the Ministry source file must be tracked: $sourcePath');
      expect(File(sourcePath).lengthSync(), greaterThan(0));
    });

    test('the specification lists 11 Governorates and 63 Wilayats', () {
      final spec = readSpec();

      expect({for (final r in governoratesOf(spec)) int.parse(r[0])},
          {for (var i = 1; i <= 11; i++) i});
      expect({for (final r in wilayatsOf(spec)) int.parse(r[0])},
          {for (var i = 1; i <= 63; i++) i});
      expect(governoratesOf(spec), hasLength(11));
      expect(wilayatsOf(spec), hasLength(63));
    });

    test('every Governorate in the seed is the specification\'s, and no more',
        () {
      final expected = {
        for (final r in governoratesOf(readSpec()))
          int.parse(r[0]): [r[1], r[2]],
      };
      final seeded = {
        for (final m in governorateSeed)
          int.parse(m.group(1)!): [m.group(2)!, m.group(3)!],
      };

      expect(governorateSeed, hasLength(11));
      expect(seeded.keys.toSet(), expected.keys.toSet());
      for (final code in expected.keys) {
        expect(seeded[code], expected[code],
            reason: 'Governorate $code differs from the specification');
      }
    });

    test('every Wilayat in the seed is the specification\'s, and no more', () {
      final expected = {
        for (final r in wilayatsOf(readSpec()))
          int.parse(r[0]): [int.parse(r[1]), r[2], r[3]],
      };
      final seeded = {
        for (final m in wilayatSeed)
          int.parse(m.group(1)!): [
            int.parse(m.group(2)!),
            m.group(3)!,
            m.group(4)!,
          ],
      };

      expect(wilayatSeed, hasLength(63));
      expect(seeded.keys.toSet(), expected.keys.toSet());
      for (final code in expected.keys) {
        expect(seeded[code], expected[code],
            reason: 'Wilayat $code differs from the specification');
      }
    });

    test(
        'Sohar is 7 and North Al Batinah is 2, in the specification and the '
        'seed', () {
      final spec = readSpec();
      final sohar = wilayatsOf(spec).singleWhere((r) => r[3] == 'Sohar');
      final northBatinah =
          governoratesOf(spec).singleWhere((r) => r[2] == 'Al Batinah North');

      expect(sohar[0], '7');
      expect(sohar[1], '2', reason: 'Sohar belongs to North Al Batinah');
      expect(northBatinah[0], '2');
      expect(flatSql, contains("(7, 2, '${sohar[2]}', 'Sohar'"));
      expect(flatSql,
          contains("(2, '${northBatinah[1]}', 'Al Batinah North', 2)"));
    });

    test('the specification is the Ministry workbook, spelling included', () {
      final spec = readSpec();
      final source = readMoiWorkbook(sourcePath);

      expect(source, hasLength(63), reason: '63 Wilayat rows in the workbook');
      expect({for (final r in source) r.wilayatCode},
          {for (var i = 1; i <= 63; i++) i});
      expect({for (final r in source) r.regionCode},
          {for (var i = 1; i <= 11; i++) i});

      // Appendix B: region membership and the raw spelling, exactly.
      final byCode = {for (final r in source) r.wilayatCode: r};
      for (final row in wilayatsOf(spec)) {
        final code = int.parse(row[0]);
        final moi = byCode[code]!;
        expect(int.parse(row[1]), moi.regionCode,
            reason: 'Wilayat $code: region code differs from the Ministry');
        expect(row[4].isEmpty ? row[2] : row[4], moi.wilayatName,
            reason: 'Wilayat $code: spelling differs from the Ministry');
      }

      // Appendix A: the raw spelling of each Governorate, exactly.
      final regionNames = {
        for (final r in source) r.regionCode: r.regionName,
      };
      for (final row in governoratesOf(spec)) {
        final code = int.parse(row[0]);
        expect(row[3], regionNames[code],
            reason: 'Governorate $code: spelling differs from the Ministry');
      }
    });

    test('the seed carries the Ministry\'s numeric codes, unchanged', () {
      final source = readMoiWorkbook(sourcePath);

      expect({
        for (final m in wilayatSeed)
          int.parse(m.group(1)!): int.parse(m.group(2)!),
      }, {
        for (final r in source) r.wilayatCode: r.regionCode,
      });
      expect({for (final m in governorateSeed) int.parse(m.group(1)!)},
          {for (final r in source) r.regionCode});
    });

    test('the seed only normalises orthography, never the name itself', () {
      // What the specification (section 2.2) allows: tatweel dropped, the
      // "governorate" prefix dropped, taa marbuta for haa in two names, the one
      // MOI misspelling corrected, and the hamza MOI left off. Folding all of
      // those away must leave the seed and the Ministry's own spelling equal.
      String fold(String name) => name
          .replaceAll('محافظة ', '')
          .replaceAll('\u0640', '')
          .replaceAll('الدخلية', 'الداخلية')
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('ة', 'ه');

      final source = readMoiWorkbook(sourcePath);
      final seededWilayats = {
        for (final m in wilayatSeed) int.parse(m.group(1)!): m.group(3)!,
      };
      final seededGovernorates = {
        for (final m in governorateSeed) int.parse(m.group(1)!): m.group(2)!,
      };

      for (final r in source) {
        expect(fold(seededWilayats[r.wilayatCode]!), fold(r.wilayatName),
            reason: 'Wilayat ${r.wilayatCode}');
        expect(fold(seededGovernorates[r.regionCode]!), fold(r.regionName),
            reason: 'Governorate ${r.regionCode}');
      }
    });

    test('the migration cites the source file the specification records', () {
      final recorded =
          RegExp(r'SHA-256 `([0-9a-f]{64})`').firstMatch(readSpec())?.group(1);

      expect(recorded, isNotNull,
          reason: 'the specification records the source file\'s SHA-256');
      expect(File(path).readAsStringSync(), contains(recorded!));
    });
  });

  group('the columns', () {
    test('communities.wilayat_code is nullable and references wilayats', () {
      expect(
          flatSql,
          contains(
              'alter table public.communities add column wilayat_code smallint references public.wilayats (code);'));
    });

    test('the existing community is assigned to Sohar, and nothing is created',
        () {
      expect(
          flatSql,
          contains(
              'update public.communities set wilayat_code = 7 where wilayat_code is null;'));
      // The only inserts are the two reference tables'.
      final inserts = RegExp(r'insert into (\S+)')
          .allMatches(sql)
          .map((m) => m.group(1))
          .where(
              (table) => table != 'communities' && table != 'community_members')
          .toList();
      expect(inserts, ['public.governorates', 'public.wilayats']);
    });

    test('a match gains no location of its own', () {
      expect(flatSql, isNot(contains('alter table public.matches')));
      expect(flatSql, isNot(contains('matches add column')));
    });

    test('the player\'s Default Location is private to its owner', () {
      expect(
          flatSql,
          contains(
              'alter table public.users add column default_wilayat_code smallint references public.wilayats (code);'));
      // Not in any SELECT grant on users, and the users SELECT grant is not
      // touched at all.
      expect(
        RegExp(r'grant\s+select[^;]*on public\.users').hasMatch(flatSql),
        isFalse,
      );
      expect(flatSql, isNot(contains('revoke select on public.users')));
      // Written by the owner, one column, through the existing own-row policy.
      expect(
          flatSql,
          contains(
              'grant update (default_wilayat_code) on public.users to authenticated;'));
      expect(flatSql, isNot(contains('users_update_own_profile')));
    });

    test('a community\'s Wilayat is readable by members, and public', () {
      expect(
          flatSql,
          contains(
              'grant select (wilayat_code) on public.communities to authenticated;'));
      // Never writable by a direct UPDATE: only the setter and create write it.
      expect(flatSql, isNot(contains('grant update (wilayat_code)')));
    });
  });

  group('set_community_wilayat', () {
    final body = functionText(sql, 'set_community_wilayat');

    test('takes a community and a smallint code, and nothing else', () {
      expect(
          body,
          contains(
              'set_community_wilayat( p_community_id uuid, p_wilayat_code smallint )'));
      expect(body, contains('returns smallint'));
    });

    test('is security definer with an empty search path', () {
      expect(body, contains('security definer'));
      expect(body, contains("set search_path = ''"));
    });

    test('checks session, account, role, community, then the code', () {
      expect(
        ascending(order(body, [
          "raise exception 'NOT_AUTHENTICATED'",
          "raise exception 'ACCOUNT_SUSPENDED'",
          "raise exception 'NOT_AUTHORIZED'",
          "raise exception 'COMMUNITY_NOT_FOUND'",
          "raise exception 'COMMUNITY_INACTIVE'",
          "raise exception 'INVALID_WILAYAT'",
        ])),
        isTrue,
      );
      expect(body, contains('public.is_current_user_active()'));
    });

    test('owner is the minimum role, and the row is locked', () {
      expect(
          body,
          contains(
              "public.has_community_role(p_community_id, auth.uid(), 'owner')"));
      expect(body, isNot(contains("'admin'")));
      expect(body, contains('for update'));
      expect(body, isNot(contains('is_system_admin')));
    });

    test('an inactive, unknown or null code is refused', () {
      expect(body, contains('p_wilayat_code is null or not exists'));
      expect(body, contains('w.code = p_wilayat_code and w.is_active'));
    });

    test('is executable by signed-in users only', () {
      expect(
          flatSql,
          contains(
              'revoke execute on function public.set_community_wilayat(uuid, smallint) from anon, public;'));
      expect(
          flatSql,
          contains(
              'grant execute on function public.set_community_wilayat(uuid, smallint) to authenticated;'));
    });
  });

  group('create_community', () {
    test('is replaced, never overloaded', () {
      expect(flatSql,
          contains('drop function public.create_community(text, text, text);'));
      expect(
        RegExp(r'create (or replace )?function public\.create_community\(')
            .allMatches(sql),
        hasLength(1),
      );
      expect(
          flatSql,
          isNot(
              contains('create or replace function public.create_community')));
    });

    test('the Wilayat parameter is optional, so a three-argument call resolves',
        () {
      final body = functionText(sql, 'create_community');

      expect(
          body,
          contains(
              'p_name text, p_description text, p_join_policy text, p_wilayat_code smallint default null'));
      expect(body, contains('returns uuid'));
    });

    test('keeps 0064\'s guards, in their order, and adds one', () {
      final body = functionText(sql, 'create_community');

      expect(
        ascending(order(body, [
          "raise exception 'NOT_AUTHENTICATED'",
          "raise exception 'ACCOUNT_SUSPENDED'",
          "raise exception 'INVALID_JOIN_POLICY'",
          "raise exception 'INVALID_WILAYAT'",
          'insert into communities',
          "insert into community_members (community_id, user_id, role) values (v_id, auth.uid(), 'owner')",
        ])),
        isTrue,
      );
      // Null is accepted: the database column is nullable for older builds.
      expect(body, contains('if p_wilayat_code is not null and not exists'));
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
    });

    test('grants are restated for the new signature', () {
      expect(
          flatSql,
          contains(
              'revoke execute on function public.create_community(text, text, text, smallint) from anon, public;'));
      expect(
          flatSql,
          contains(
              'grant execute on function public.create_community(text, text, text, smallint) to authenticated;'));
    });
  });

  group('my_profile', () {
    final body = functionText(sql, 'my_profile');

    test('gains the column, stays strictly self-only', () {
      expect(body, contains('my_profile() returns table ('));
      expect(body, contains('default_wilayat_code smallint )'));
      expect(body, contains('where u.id = auth.uid()'));
      expect(body, isNot(contains('p_user_id')));
      expect(flatSql, contains('drop function public.my_profile();'));
      expect(
          flatSql,
          contains(
              'revoke execute on function public.my_profile() from anon, public;'));
      expect(
          flatSql,
          contains(
              'grant execute on function public.my_profile() to authenticated;'));
    });

    test('keeps the ten columns it had, in order', () {
      const columns = [
        'user_id',
        'full_name',
        'phone',
        'primary_position',
        'secondary_position',
        'date_of_birth',
        'avatar_path',
        'overall_rating',
        'profile_visibility',
        'age_visible',
        'default_wilayat_code',
      ];

      expect(
          ascending(
            order(body, [for (final c in columns) '$c ']),
          ),
          isTrue);
    });
  });

  group('the public views', () {
    test('each is replaced in place, with columns appended at the end', () {
      final matches = flat(sql.substring(sql
          .indexOf('create or replace view public.v_public_upcoming_matches')));

      expect(matches,
          contains('open_slots, c.wilayat_code from public.matches m'));

      final communities = flat(sql.substring(
          sql.indexOf('create or replace view public.v_public_communities')));
      expect(
          communities, contains('c.created_at, c.logo_url, c.wilayat_code,'));
      expect(
          communities,
          contains(
              ') as last_activity_at from public.communities c where c.is_active'));
    });

    test('activity is the latest completed match, else creation', () {
      final communities = flat(sql.substring(
          sql.indexOf('create or replace view public.v_public_communities')));

      // The predicate of v_football_completed_matches (0057), unchanged.
      expect(communities,
          contains("(m.status = 'completed' or m.end_at <= now())"));
      expect(communities, contains('select max(m.start_at)'));
      expect(communities, contains('), c.created_at ) as last_activity_at'));
    });

    test('they stay read-only and readable without a session', () {
      for (final view in [
        'v_public_communities',
        'v_public_upcoming_matches'
      ]) {
        expect(
            flatSql,
            contains(
                'revoke insert, update, delete, truncate, references, trigger on public.$view from anon, authenticated;'));
      }
      expect(
          flatSql,
          contains(
              'grant select on public.v_public_communities to anon, authenticated;'));
      expect(
          flatSql,
          contains(
              'grant select on public.v_public_upcoming_matches to anon, authenticated;'));
      expect(flatSql, isNot(contains('security_invoker')));
    });
  });

  group('what is deliberately left alone', () {
    test('Latest Results, the football views, sign-up and matches', () {
      for (final untouched in [
        'public_recent_results',
        'public_community_recent_results',
        'v_football_',
        'handle_new_user',
        'public_match_detail',
        'public_community_football_record',
      ]) {
        expect(sql, isNot(contains(untouched)), reason: untouched);
      }
    });

    test('no client-visible seed of fixtures', () {
      expect(flatSql, isNot(contains('insert into public.communities')));
      expect(flatSql, isNot(contains('insert into public.users')));
      expect(flatSql, isNot(contains('insert into public.matches')));
    });
  });

  group('the rollback', () {
    test('restores what 0064, 0063, 0061 and 0033 left', () {
      final flatRollback = flat(rollback);

      expect(
          flatRollback,
          contains(
              'drop function if exists public.set_community_wilayat(uuid, smallint);'));
      expect(
          flatRollback,
          contains(
              'drop function if exists public.create_community(text, text, text, smallint);'));
      expect(
          flatRollback,
          contains(
              'create function public.create_community( p_name text, p_description text, p_join_policy text )'));
      expect(flatRollback, contains('drop view public.v_public_communities;'));
      expect(flatRollback,
          contains('drop view public.v_public_upcoming_matches;'));
      expect(
          flatRollback,
          contains(
              'alter table public.communities drop column if exists wilayat_code;'));
      expect(
          flatRollback,
          contains(
              'alter table public.users drop column if exists default_wilayat_code;'));
      expect(flatRollback, contains('drop table if exists public.wilayats;'));
      expect(
          flatRollback, contains('drop table if exists public.governorates;'));
    });

    test('drops the tables only after everything that references them', () {
      final flatRollback = flat(rollback);

      expect(
        ascending(order(flatRollback, [
          'drop view public.v_public_communities',
          'alter table public.communities drop column if exists wilayat_code',
          'drop table if exists public.wilayats',
          'drop table if exists public.governorates',
        ])),
        isTrue,
      );
    });
  });

  group('the client', () {
    test('the failure mapper knows the one new business outcome', () {
      final mapper =
          File('lib/infrastructure/supabase/supabase_failure_mapper.dart')
              .readAsStringSync();

      expect(mapper, contains("'INVALID_WILAYAT': ValidationFailure()"));
    });

    test('the client names only columns and functions this migration grants',
        () {
      String read(String file) =>
          File('lib/infrastructure/supabase/$file').readAsStringSync();

      expect(read('supabase_community_adapter.dart'),
          contains("'p_wilayat_code': wilayatCode"));
      expect(read('supabase_community_adapter.dart'),
          contains("rpc('set_community_wilayat'"));
      expect(read('supabase_community_adapter.dart'),
          contains('logo_url, wilayat_code'));
      expect(read('supabase_discover_adapter.dart'),
          contains('wilayat_code, last_activity_at'));
      // The one column write on users, and it names nothing else.
      expect(read('supabase_profile_adapter.dart'),
          contains("{'default_wilayat_code': wilayatCode}"));
    });
  });
}
