"""Proves the migration 0082 lock contract with two real PostgreSQL sessions.

    set GO_PLAY_DATABASE_URL=...          (session mode, port 5432)
    python supabase/tool/rating_rebase_lock_proof.py

The hardened rebase locks its whole evidence set against writers before it
reads a single archived row, and leaves every reader alone while it does. Both
halves of that are claims about PostgreSQL's lock conflict matrix, and a claim
is not a proof: this script holds the locks in one connection and, from a
second, shows that a writer is refused and a reader is not.

**It is the release gate for applying 0082**, because the Supabase wrapper the
rest of this repository is validated through opens a fresh backend per call and
serialises them -- so it can never hold two transactions open at once, and can
never observe contention at all.

Environment: `GO_PLAY_DATABASE_URL` only. Nothing is read from anywhere else,
and the DSN is never printed -- only its port, which is the one part of it that
has to be checked out loud.

**Session mode, not transaction mode.** Supabase's pooler on 6543 multiplexes
several clients onto one backend and hands it back between statements, so two
"sessions" there are not two sessions and a held lock is not reliably held.
The script refuses that port rather than reporting a result it cannot trust.

**Nothing is written.** The whole proof is `SET LOCAL`, `LOCK TABLE`, `SELECT`
and `ROLLBACK`: no insert, no update, no delete, no migration, no rebase, no
object created, no Team of Period. A fingerprint of the rating tables is taken
before and after and compared, so a run that somehow did change something says
so instead of passing quietly. Every transaction is rolled back in `finally`.
"""

import os
import sys
from urllib.parse import urlsplit

# Exactly the evidence set `rebase_ratings_to_0078` locks, in exactly the order
# migration 0082 takes it: alphabetical, so that anything else needing several
# of these tables can take them the same way and never deadlock against it.
PROTECTED_TABLES = (
    'match_goals',
    'match_results',
    'match_team_assignments',
    'matches',
    'rating_history',
    'users',
)

# The mode the rebase holds: conflicts with the ROW EXCLUSIVE every INSERT,
# UPDATE and DELETE takes, and with nothing a reader takes.
HOLD_MODE = 'SHARE ROW EXCLUSIVE'

# What a writer would take, and what Session B asks for without ever writing.
WRITER_MODE = 'ROW EXCLUSIVE'

LOCK_TIMEOUT = '15s'
READ_TIMEOUT_MS = 5000
LOCK_NOT_AVAILABLE = '55P03'

SESSION_PORT = 5432
TRANSACTION_POOLER_PORT = 6543

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_USAGE = 64


# ---------------------------------------------------------------------------
# Pure helpers -- unit-tested in rating_rebase_lock_proof_test.py without a
# database, because they are the part that decides whether to connect at all.
# ---------------------------------------------------------------------------

def dsn_port(dsn):
    """The port in a libpq URI, or None when it names no port.

    Never returns, logs or reconstructs any other part of the DSN.
    """
    try:
        parsed = urlsplit(dsn.strip())
    except ValueError:
        return None
    try:
        return parsed.port
    except ValueError:
        # A malformed port is not a port.
        return None


def classify_dsn(dsn):
    """Decide whether this DSN may be used, before anything connects.

    Returns `(usable, level, message)`. The message never contains the DSN.
    """
    if not dsn or not dsn.strip():
        return (False, 'FATAL',
                'GO_PLAY_DATABASE_URL is not set. This proof needs a direct '
                'SESSION-MODE PostgreSQL connection (Supabase pooler port '
                '%d). Set GO_PLAY_DATABASE_URL and run it again; the value is '
                'never printed or stored by this script.' % SESSION_PORT)

    port = dsn_port(dsn)
    if port == TRANSACTION_POOLER_PORT:
        return (False, 'FATAL',
                'port %d is the transaction pooler: it multiplexes clients '
                'onto shared backends, so two connections are not two '
                'sessions and a held lock is not reliably held. Use session '
                'mode (port %d).' % (TRANSACTION_POOLER_PORT, SESSION_PORT))
    if port is None:
        return (True, 'WARN',
                'the DSN names no port; assuming session mode. If this is the '
                'transaction pooler the result cannot be trusted.')
    if port != SESSION_PORT:
        return (True, 'WARN',
                'port %d is not the expected session-mode port %d. '
                'Continuing, but confirm this is not a transaction pooler.'
                % (port, SESSION_PORT))
    return (True, 'OK', 'session-mode port %d' % SESSION_PORT)


def fingerprint_diffs(before, after):
    """Which fingerprint values moved between the two readings."""
    return [
        '%s: %r -> %r' % (key, before[key], after.get(key))
        for key in sorted(before)
        if before[key] != after.get(key)
    ]


def evaluate(report):
    """Every requirement, and the reason for each one that was not met."""
    failures = []

    if report.get('pid_a') is None or report.get('pid_b') is None:
        failures.append('both backend PIDs must be known')
    elif report['pid_a'] == report['pid_b']:
        failures.append(
            'Session A and Session B share backend PID %s -- this is one '
            'session, not two, and proves nothing' % report['pid_a'])

    held = report.get('held_by_a') or []
    missing = [t for t in PROTECTED_TABLES if t not in held]
    if missing:
        failures.append(
            'Session A did not hold %s on: %s'
            % (HOLD_MODE, ', '.join(missing)))

    for table in PROTECTED_TABLES:
        outcome = report.get('writer', {}).get(table)
        if outcome != 'BLOCKED':
            failures.append(
                '%s %s was %s while Session A held the rebase locks; it must '
                'be BLOCKED' % (table, WRITER_MODE, outcome or 'not tested'))

    for table, outcome in sorted(report.get('reads', {}).items()):
        if outcome != 'READABLE':
            failures.append('%s was %s during the lock; reads must stay '
                            'available' % (table, outcome))
    if not report.get('reads'):
        failures.append('no read availability was measured')

    if report.get('post_release') != 'ACQUIRED':
        failures.append(
            'after Session A rolled back, %s was %s; it must be ACQUIRED'
            % (WRITER_MODE, report.get('post_release') or 'not tested'))

    if report.get('locks_after_release'):
        failures.append(
            "Session A's locks survived its rollback: %s"
            % ', '.join(report['locks_after_release']))

    drift = report.get('fingerprint_drift')
    if drift is None:
        failures.append('the before/after fingerprint was not compared')
    elif drift:
        failures.append('data changed during a read-only proof: %s'
                        % '; '.join(drift))

    if not report.get('rolled_back'):
        failures.append('not every transaction ended in a rollback')

    return failures


# ---------------------------------------------------------------------------
# The proof
# ---------------------------------------------------------------------------

FINGERPRINT_SQL = """
select
  (select count(*) from public.rating_history) as history_rows,
  (select coalesce(max(entry_no), 0) from public.rating_history) as max_entry_no,
  (select coalesce(sum(delta), 0)::text from public.rating_history) as sum_delta,
  (select count(*) from public.users) as user_rows,
  (select max(overall_rating)::text from public.users) as top_rating,
  (select md5(string_agg(u.id::text || ':' || u.overall_rating::text, ','
                         order by u.id))
     from public.users u) as rating_fingerprint
"""

HELD_LOCKS_SQL = """
select l.relation::regclass::text
from pg_locks l
where l.pid = %s
  and l.locktype = 'relation'
  and l.mode = 'ShareRowExclusiveLock'
  and l.granted
order by 1
"""


def _backend_pid(conn):
    with conn.cursor() as cur:
        cur.execute('select pg_backend_pid()')
        pid = cur.fetchone()[0]
    conn.rollback()
    return pid


def _fingerprint(conn):
    with conn.cursor() as cur:
        cur.execute(FINGERPRINT_SQL)
        row = cur.fetchone()
        names = [d[0] for d in cur.description]
    conn.rollback()
    return dict(zip(names, row))


def _hold_rebase_locks(conn):
    """Session A: the migration's own opening, verbatim in effect."""
    cur = conn.cursor()
    cur.execute("set local lock_timeout = %s", (LOCK_TIMEOUT,))
    cur.execute('lock table %s in %s mode'
                % (', '.join('public.' + t for t in PROTECTED_TABLES),
                   HOLD_MODE.lower()))
    # Left open on purpose: the caller rolls it back.
    return cur


def _writer_refused(conn, table):
    """Ask for the lock a writer would take. Never writes."""
    try:
        with conn.cursor() as cur:
            cur.execute('lock table public.%s in %s mode nowait'
                        % (table, WRITER_MODE.lower()))
        return 'ALLOWED'
    except Exception as exc:                      # noqa: BLE001 - reported
        code = getattr(exc, 'pgcode', None)
        return 'BLOCKED' if code == LOCK_NOT_AVAILABLE else 'ERROR:%s' % code
    finally:
        conn.rollback()


def _readable(conn, table):
    try:
        with conn.cursor() as cur:
            cur.execute('set local statement_timeout = %s', (READ_TIMEOUT_MS,))
            cur.execute('select count(*) from public.%s' % table)
            cur.fetchone()
        return 'READABLE'
    except Exception as exc:                      # noqa: BLE001 - reported
        return 'BLOCKED:%s' % getattr(exc, 'pgcode', 'unknown')
    finally:
        conn.rollback()


def run_proof(psycopg2, dsn):
    report = {
        'pid_a': None, 'pid_b': None, 'held_by_a': [],
        'writer': {}, 'reads': {}, 'post_release': None,
        'locks_after_release': [], 'fingerprint_drift': None,
        'rolled_back': False,
    }
    conn_a = conn_b = None
    try:
        conn_a = psycopg2.connect(dsn)
        conn_b = psycopg2.connect(dsn)
        conn_a.autocommit = False
        conn_b.autocommit = False

        report['pid_a'] = _backend_pid(conn_a)
        report['pid_b'] = _backend_pid(conn_b)
        if report['pid_a'] == report['pid_b']:
            # Nothing below would mean anything.
            return report

        before = _fingerprint(conn_b)

        _hold_rebase_locks(conn_a)

        # Observed from the other session, which is the only observation that
        # counts: B can see what A is holding.
        with conn_b.cursor() as cur:
            cur.execute(HELD_LOCKS_SQL, (report['pid_a'],))
            report['held_by_a'] = [r[0] for r in cur.fetchall()]
        conn_b.rollback()

        # TEST A -- every protected table refuses a writer.
        for table in PROTECTED_TABLES:
            report['writer'][table] = _writer_refused(conn_b, table)

        # TEST B -- and none of them refuses a reader.
        for table in ('matches', 'match_results', 'users', 'rating_history'):
            report['reads'][table] = _readable(conn_b, table)

        # TEST C -- released, and a writer may proceed.
        conn_a.rollback()
        with conn_b.cursor() as cur:
            cur.execute(HELD_LOCKS_SQL, (report['pid_a'],))
            report['locks_after_release'] = [r[0] for r in cur.fetchall()]
        conn_b.rollback()

        report['post_release'] = (
            'ACQUIRED' if _writer_refused(conn_b, 'matches') == 'ALLOWED'
            else 'REFUSED')

        after = _fingerprint(conn_b)
        report['fingerprint_drift'] = fingerprint_diffs(before, after)
        return report
    finally:
        rolled_back = True
        for conn in (conn_a, conn_b):
            if conn is not None:
                try:
                    conn.rollback()
                except Exception:                 # noqa: BLE001
                    rolled_back = False
        report['rolled_back'] = rolled_back
        for conn in (conn_a, conn_b):
            if conn is not None:
                try:
                    conn.close()
                except Exception:                 # noqa: BLE001
                    pass


def render(report, failures):
    lines = []
    out = lines.append
    out('RESULT            %s' % ('PASS' if not failures else 'FAIL'))
    out('session A pid     %s' % report.get('pid_a'))
    out('session B pid     %s' % report.get('pid_b'))
    out('distinct sessions %s' % (
        'yes' if report.get('pid_a') and report.get('pid_a') != report.get('pid_b')
        else 'NO'))
    out('locks held by A   %d/%d (%s)' % (
        len(report.get('held_by_a') or []), len(PROTECTED_TABLES), HOLD_MODE))
    out('')
    out('TEST A -- %s NOWAIT while A holds:' % WRITER_MODE)
    for table in PROTECTED_TABLES:
        out('  %-26s %s' % (table, report.get('writer', {}).get(table, 'not tested')))
    out('')
    out('TEST B -- reads during the lock:')
    for table, outcome in sorted(report.get('reads', {}).items()):
        out('  %-26s %s' % (table, outcome))
    out('')
    out('TEST C -- after A rolled back:')
    out('  %-26s %s' % ('post_release_' + WRITER_MODE.lower().replace(' ', '_'),
                        report.get('post_release') or 'not tested'))
    out('  %-26s %s' % ('stale locks',
                        ', '.join(report.get('locks_after_release') or []) or 'none'))
    out('')
    drift = report.get('fingerprint_drift')
    out('fingerprint       %s' % (
        'unchanged' if drift == [] else
        'NOT COMPARED' if drift is None else 'CHANGED: ' + '; '.join(drift)))
    out('all transactions  %s' % ('rolled back' if report.get('rolled_back') else 'NOT rolled back'))
    if failures:
        out('')
        out('failures:')
        for reason in failures:
            out('  - %s' % reason)
    return '\n'.join(lines)


def main(argv):
    dsn = os.environ.get('GO_PLAY_DATABASE_URL', '')
    usable, level, message = classify_dsn(dsn)
    if not usable:
        sys.stderr.write('%s: %s\n' % (level, message))
        return EXIT_USAGE
    if level == 'WARN':
        sys.stderr.write('WARN: %s\n' % message)
    else:
        sys.stdout.write('connection       %s\n' % message)

    try:
        import psycopg2                           # noqa: PLC0415 - optional
    except ImportError:
        sys.stderr.write('FATAL: psycopg2 is required '
                         '(pip install psycopg2-binary)\n')
        return EXIT_USAGE

    report = run_proof(psycopg2, dsn)
    failures = evaluate(report)
    sys.stdout.write(render(report, failures) + '\n')
    return EXIT_OK if not failures else EXIT_FAILED


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
