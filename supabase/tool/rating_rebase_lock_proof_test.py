"""The parts of the lock proof that decide whether to connect at all.

    python -m unittest discover -s supabase/tool -p "*_test.py"

No database is touched here. What is held is the judgement the script makes
before it opens anything -- which port it will refuse, and what it counts as a
pass -- because those are the two places where a wrong answer would let an
unproved release gate look like a proved one.
"""

import unittest

from rating_rebase_lock_proof import (
    PROTECTED_TABLES,
    classify_dsn,
    dsn_port,
    evaluate,
    fingerprint_diffs,
)


def passing_report():
    """What a genuine two-session proof looks like."""
    return {
        'pid_a': 111,
        'pid_b': 222,
        'held_by_a': list(PROTECTED_TABLES),
        'writer': {t: 'BLOCKED' for t in PROTECTED_TABLES},
        'reads': {'matches': 'READABLE', 'users': 'READABLE'},
        'post_release': 'ACQUIRED',
        'locks_after_release': [],
        'fingerprint_drift': [],
        'rolled_back': True,
    }


class PortReading(unittest.TestCase):
    def test_it_reads_the_port(self):
        self.assertEqual(
            dsn_port('postgresql://user:pw@host.example:5432/postgres'), 5432)
        self.assertEqual(
            dsn_port('postgres://user:pw@host.example:6543/postgres'), 6543)

    def test_no_port_is_no_port(self):
        self.assertIsNone(dsn_port('postgresql://user:pw@host.example/postgres'))

    def test_a_malformed_port_is_not_a_port(self):
        self.assertIsNone(dsn_port('postgresql://user:pw@host.example:nope/db'))


class DsnClassification(unittest.TestCase):
    def test_a_missing_dsn_stops_the_run(self):
        usable, level, message = classify_dsn('')
        self.assertFalse(usable)
        self.assertEqual(level, 'FATAL')
        self.assertIn('GO_PLAY_DATABASE_URL', message)
        self.assertIn('SESSION-MODE', message)

    def test_blank_is_missing(self):
        self.assertFalse(classify_dsn('   ')[0])

    def test_the_transaction_pooler_is_refused(self):
        # 6543 multiplexes: two connections are not two sessions there, so a
        # result from it would be meaningless rather than merely awkward.
        usable, level, message = classify_dsn(
            'postgresql://u:p@host.example:6543/postgres')
        self.assertFalse(usable)
        self.assertEqual(level, 'FATAL')
        self.assertIn('6543', message)
        self.assertIn('5432', message)

    def test_session_mode_is_accepted(self):
        usable, level, _ = classify_dsn(
            'postgresql://u:p@host.example:5432/postgres')
        self.assertTrue(usable)
        self.assertEqual(level, 'OK')

    def test_an_unusual_port_warns_but_proceeds(self):
        usable, level, _ = classify_dsn(
            'postgresql://u:p@host.example:5433/postgres')
        self.assertTrue(usable)
        self.assertEqual(level, 'WARN')

    def test_an_absent_port_warns_but_proceeds(self):
        usable, level, _ = classify_dsn('postgresql://u:p@host.example/postgres')
        self.assertTrue(usable)
        self.assertEqual(level, 'WARN')

    def test_no_message_ever_carries_the_dsn(self):
        secret = 'postgresql://someone:hunter2@host.example:6543/postgres'
        for dsn in ('', secret,
                    'postgresql://someone:hunter2@host.example:5432/postgres'):
            _, _, message = classify_dsn(dsn)
            self.assertNotIn('hunter2', message)
            self.assertNotIn('someone', message)
            self.assertNotIn('host.example', message)


class Fingerprints(unittest.TestCase):
    def test_identical_readings_have_no_drift(self):
        before = {'history_rows': 1714, 'top_rating': '6.020'}
        self.assertEqual(fingerprint_diffs(before, dict(before)), [])

    def test_a_moved_value_is_named(self):
        drift = fingerprint_diffs(
            {'history_rows': 1714, 'top_rating': '6.020'},
            {'history_rows': 1715, 'top_rating': '6.020'})
        self.assertEqual(len(drift), 1)
        self.assertIn('history_rows', drift[0])

    def test_a_missing_value_counts_as_drift(self):
        self.assertEqual(len(fingerprint_diffs({'a': 1}, {})), 1)


class Evaluation(unittest.TestCase):
    def test_a_complete_proof_passes(self):
        self.assertEqual(evaluate(passing_report()), [])

    def test_one_session_is_not_two(self):
        report = passing_report()
        report['pid_b'] = report['pid_a']
        failures = evaluate(report)
        self.assertTrue(any('one session' in f for f in failures))

    def test_a_writer_getting_through_fails_everything(self):
        report = passing_report()
        report['writer']['users'] = 'ALLOWED'
        failures = evaluate(report)
        self.assertTrue(any('users' in f and 'BLOCKED' in f for f in failures))

    def test_every_protected_table_must_be_tested(self):
        report = passing_report()
        del report['writer']['matches']
        self.assertTrue(any('matches' in f for f in evaluate(report)))

    def test_a_blocked_reader_fails(self):
        report = passing_report()
        report['reads']['matches'] = 'BLOCKED:55P03'
        self.assertTrue(
            any('reads must stay available' in f for f in evaluate(report)))

    def test_reads_must_actually_be_measured(self):
        report = passing_report()
        report['reads'] = {}
        self.assertTrue(
            any('no read availability' in f for f in evaluate(report)))

    def test_a_lock_that_outlives_its_rollback_fails(self):
        report = passing_report()
        report['locks_after_release'] = ['matches']
        self.assertTrue(any('survived' in f for f in evaluate(report)))

    def test_the_writer_must_get_through_afterwards(self):
        report = passing_report()
        report['post_release'] = 'REFUSED'
        self.assertTrue(any('ACQUIRED' in f for f in evaluate(report)))

    def test_changed_data_fails_a_read_only_proof(self):
        report = passing_report()
        report['fingerprint_drift'] = ['history_rows: 1714 -> 1715']
        self.assertTrue(any('data changed' in f for f in evaluate(report)))

    def test_an_uncompared_fingerprint_is_not_a_pass(self):
        report = passing_report()
        report['fingerprint_drift'] = None
        self.assertTrue(
            any('was not compared' in f for f in evaluate(report)))

    def test_an_unrolled_transaction_fails(self):
        report = passing_report()
        report['rolled_back'] = False
        self.assertTrue(any('rollback' in f for f in evaluate(report)))

    def test_missing_locks_are_named(self):
        report = passing_report()
        report['held_by_a'] = ['matches']
        failures = evaluate(report)
        self.assertTrue(any('did not hold' in f for f in failures))


if __name__ == '__main__':
    unittest.main()
