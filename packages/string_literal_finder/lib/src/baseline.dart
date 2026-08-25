import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/string_literal_finder.dart';

/// A record of the string literals which already existed when a project
/// adopted this tool, so that CI can fail on *new* literals only.
///
/// A code base with thousands of literals cannot be fixed in one commit, and a
/// check which is red from the day it is introduced gets ignored. Recording the
/// current state and gating on additions is what makes adoption possible.
///
/// Literals are keyed by file and by source text rather than by line, so that
/// moving code around, reformatting, or editing an unrelated line does not
/// invalidate the baseline. Repeated identical literals in one file are
/// counted, so adding a second `'-'` to a file that already had one is still
/// reported.
class Baseline {
  Baseline(this.literals);

  Baseline.empty() : literals = const {};

  /// Version of the on-disk format, so a future change can be detected rather
  /// than silently misread.
  static const currentVersion = 1;

  static const _keyVersion = 'version';
  static const _keyLiterals = 'literals';

  /// Relative file path -> literal source text -> number of occurrences.
  final Map<String, Map<String, int>> literals;

  int get totalCount =>
      literals.values.expand((e) => e.values).fold(0, (a, b) => a + b);

  static Baseline fromJson(String source) {
    final decoded = json.decode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Baseline must be a JSON object.');
    }
    final version = decoded[_keyVersion];
    if (version != currentVersion) {
      throw FormatException(
        'Unsupported baseline version $version, expected $currentVersion. '
        'Re-record it with --write-baseline.',
      );
    }
    final literals = decoded[_keyLiterals];
    if (literals is! Map<String, dynamic>) {
      throw const FormatException('Baseline "literals" must be an object.');
    }
    try {
      return Baseline({
        for (final MapEntry(:key, :value) in literals.entries)
          key: {
            for (final MapEntry(key: literal, value: count)
                in (value as Map<String, dynamic>).entries)
              literal: count as int,
          },
      });
    } on TypeError catch (e) {
      // A bare TypeError here surfaces as an internal error with a stack
      // trace, which tells nobody that their baseline file is corrupt.
      throw FormatException(
        'Baseline is malformed ($e). '
        'Re-record it with --write-baseline.',
      );
    }
  }

  /// Builds a baseline from [found]. Paths are stored relative to [basePath] so
  /// the file is portable between checkouts and CI machines.
  static Baseline fromFound(
    Iterable<FoundStringLiteral> found,
    String basePath,
  ) {
    final literals = <String, Map<String, int>>{};
    for (final literal in found) {
      final relative = _relative(literal.filePath, basePath);
      final counts = literals.putIfAbsent(relative, () => {});
      final key = literal.sourceText;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Baseline(literals);
  }

  static String _relative(String filePath, String basePath) =>
      path.toUri(path.relative(filePath, from: basePath)).path;

  /// Sorted, indented JSON, so that the file reviews well in a pull request.
  String toJson() {
    Map<String, int> sortedCounts(String file) {
      final counts = literals[file]!;
      return {
        for (final key in counts.keys.toList()..sort()) key: counts[key]!,
      };
    }

    final encoded = const JsonEncoder.withIndent('  ').convert({
      _keyVersion: currentVersion,
      _keyLiterals: {
        for (final file in literals.keys.toList()..sort())
          if (literals[file]!.isNotEmpty) file: sortedCounts(file),
      },
    });
    return '$encoded\n';
  }

  /// Splits [found] into literals which the baseline already accounts for and
  /// literals which are new.
  BaselineComparison compare(
    Iterable<FoundStringLiteral> found,
    String basePath,
  ) {
    final remaining = {
      for (final MapEntry(:key, :value) in literals.entries) key: Map.of(value),
    };
    final newLiterals = <FoundStringLiteral>[];
    for (final literal in found) {
      final relative = _relative(literal.filePath, basePath);
      final counts = remaining[relative];
      final key = literal.sourceText;
      final available = counts?[key] ?? 0;
      if (available > 0) {
        counts![key] = available - 1;
      } else {
        newLiterals.add(literal);
      }
    }
    final obsolete = remaining.values
        .expand((counts) => counts.values)
        .fold(0, (a, b) => a + b);
    return BaselineComparison(
      newLiterals: newLiterals,
      obsoleteCount: obsolete,
    );
  }
}

/// The result of checking findings against a [Baseline].
class BaselineComparison {
  BaselineComparison({required this.newLiterals, required this.obsoleteCount});

  /// Literals which are not accounted for by the baseline.
  final List<FoundStringLiteral> newLiterals;

  /// Literals recorded in the baseline which no longer exist. Purely
  /// informational — they mean the baseline can be shrunk.
  final int obsoleteCount;
}
