@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:string_literal_finder/src/analysis_options.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:test/test.dart';

/// Runs the finder the way the command line does, against the real `example/`
/// package in this repository.
///
/// This is the only test that exercises context discovery, file exclusion and
/// the syntactic pre-pass together, so it is where a regression in the plumbing
/// around the visitor would show up.
void main() {
  final examplePath = p.normalize(
    p.join(Directory.current.absolute.path, 'example', 'lib'),
  );

  Future<StringLiteralFinder> run({AnalysisOptions? analysisOptions}) async {
    final finder = StringLiteralFinder(
      basePath: examplePath,
      excludePaths: ExcludePathChecker.excludePathDefaults,
      analysisOptions: analysisOptions,
    );
    await finder.start();
    return finder;
  }

  setUpAll(() {
    if (!Directory(examplePath).existsSync()) {
      throw StateError('Expected the example package at $examplePath.');
    }
  });

  test(
    'finds exactly the literals example/lib documents as unignored',
    () async {
      final finder = await run();
      expect(
        finder.foundStringLiterals.map((e) => e.sourceText),
        // `'Lorem ipsum'`, `'Hello world'` and the `nonNls({...})` map are all
        // suppressed; the `''` pair comes from `.split('').join('')`.
        ["'not translated'", "'not translated2'", "''", "''"],
      );
      expect(finder.filesAnalyzed, isNotEmpty);
    },
  );

  test(
    'exclude_globs from analysis_options.yaml suppresses a whole file',
    () async {
      final finder = await run(
        analysisOptions: AnalysisOptions.loadFromYaml(examplePath, '''
string_literal_finder:
  exclude_globs:
    - 'example.dart'
'''),
      );
      expect(finder.foundStringLiterals, isEmpty);
      expect(finder.filesAnalyzed, isEmpty);
    },
  );

  test('a non-matching glob leaves the findings alone', () async {
    final finder = await run(
      analysisOptions: AnalysisOptions.loadFromYaml(examplePath, '''
string_literal_finder:
  exclude_globs:
    - 'nothing_matches_this/**'
'''),
    );
    expect(finder.foundStringLiterals, hasLength(4));
  });

  test('the syntactic pre-pass never skips a file that has findings', () async {
    final finder = await run();
    final filesWithFindings = finder.foundStringLiterals
        .map((e) => e.filePath)
        .toSet();
    expect(
      finder.filesAnalyzed.length - finder.filesSkippedBySyntacticPrePass,
      greaterThanOrEqualTo(filesWithFindings.length),
    );
  });
}
