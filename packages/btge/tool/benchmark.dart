/// Measures where exhaustive search stops being practical.
///
/// `KB-D2` records that 15 vs 15 admits 77,558,760 partitions, and `KB-013`
/// forbids substituting a heuristic to get around it. This tool exists so the
/// boundary is a measured number rather than an assumption.
///
///   dart run tool/benchmark.dart [maxPlayers]
library;

import 'package:btge/btge.dart';

void main(List<String> args) {
  final maxPlayers = args.isEmpty ? 22 : int.parse(args.first);
  final matchDay = DateTime(2026, 7, 1);

  const config = BtgeConfiguration.strictLexicographic();
  const engine = BtgeEngine(config);

  print('players | partitions | elapsed');
  print('--------|------------|--------');

  for (var n = 8; n <= maxPlayers; n += 2) {
    final players = <Player>[];
    for (var i = 0; i < n; i++) {
      players.add(Player(
        id: 'p${i.toString().padLeft(2, '0')}',
        overallRating: 30 + (i * 7) % 60,
        dateOfBirth: DateTime(1990 + (i % 20), 1 + (i % 12), 1 + (i % 28)),
        primaryPosition: Position.values[i % 4],
        secondaryPosition: i.isEven ? Position.values[(i + 1) % 4] : null,
      ));
    }

    final stopwatch = Stopwatch()..start();
    final result = engine.generate(
      players: players,
      settings: MatchSettings(matchDate: matchDay),
    );
    stopwatch.stop();

    print('${n.toString().padLeft(7)} | '
        '${result.diagnostics.candidatesEvaluated.toString().padLeft(10)} | '
        '${stopwatch.elapsedMilliseconds}ms');
  }
}
