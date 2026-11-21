import 'dart:io';

import '../lib/entry.dart';

void main() {
  final entries = List.generate(
    10000,
    (i) => Entry('Item $i', '/launch/Target-$i', Kind.values[i % 2]),
  );
  const queries = ['target-84', 'item 17', 'ITEM 92', 'missing', ''];
  final samples = <String, List<int>>{'baseline': [], 'indexed': []};
  var count = 0;

  int measure(bool indexed) {
    final time = Stopwatch()..start();
    for (var round = 0; round < 18; round++) {
      for (final query in queries) {
        final normalized = query.toLowerCase();
        count +=
            (indexed
                    ? filterEntries(entries, query, Kind.app)
                    : entries.where(
                        (entry) =>
                            entry.kind == Kind.app &&
                            '${entry.name} ${entry.target}'
                                .toLowerCase()
                                .contains(normalized),
                      ))
                .length;
      }
    }
    return time.elapsedMicroseconds;
  }

  for (final query in queries) {
    final expected = entries.where(
      (entry) =>
          entry.kind == Kind.app &&
          '${entry.name} ${entry.target}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
    );
    final actual = filterEntries(entries, query, Kind.app);
    if (actual.map((entry) => entry.target).join() !=
        expected.map((entry) => entry.target).join()) {
      throw StateError('Resultado diferente para $query.');
    }
  }
  for (var i = 0; i < 3; i++) {
    measure(false);
    measure(true);
  }
  for (var i = 0; i < 11; i++) {
    for (final key
        in i.isEven ? ['baseline', 'indexed'] : ['indexed', 'baseline']) {
      samples[key]!.add(measure(key == 'indexed'));
    }
  }
  for (final MapEntry(:key, :value) in samples.entries) {
    value.sort();
    stdout.writeln(
      '$key median ${(value[5] / 1000).toStringAsFixed(2)} ms / 90 searches',
    );
  }
  stdout.writeln('Matches counted: $count');
}
