import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/analysis_options.dart';
import 'package:string_literal_finder/src/baseline.dart';
import 'package:string_literal_finder/src/filters.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:string_literal_finder/src/utils.dart';

final _logger = Logger('string_literal_finder');

const executableName = 'string_literal_finder';

const _argPath = 'path';
const _argHelp = 'help';
const _argVerbose = 'verbose';
const _argSilent = 'silent';
const _argExcludePath = 'exclude-path';
const _argExcludeSuffix = 'exclude-suffix';
const _argAnalysisOptions = 'analysis-options';
const _argCacheDir = 'cache-dir';
const _argMetricsFile = 'metrics-output-file';
const _argAnnotationFile = 'annotations-output-file';
const _argAnnotationRoot = 'annotations-path-root';
const _argFormat = 'format';
const _argBaseline = 'baseline';
const _argWriteBaseline = 'write-baseline';
const _argMaxLiterals = 'max-literals';
const _argMinLength = 'min-length';
const _argIgnorePattern = 'ignore-pattern';
const _argIgnoreSymbols = 'ignore-symbols';
const _argProseOnly = 'prose-only';

const _formatPretty = 'pretty';
const _formatJson = 'json';

/// Everything is fine.
const _exitOk = 0;

/// Literals were found which the configured gate does not allow.
const _exitLiteralsFound = 1;

/// The command line could not be understood.
const _exitUsage = 2;

/// Something went wrong while analysing.
const _exitError = 70;

ArgParser _buildParser() => ArgParser()
  ..addSeparator('Analysis:')
  ..addOption(_argPath, abbr: 'p', help: 'Base path of your library.')
  ..addMultiOption(
    _argExcludePath,
    help: 'Exclude paths (relative to path, "startsWith").',
  )
  ..addMultiOption(
    _argExcludeSuffix,
    help: 'Exclude path suffixes ("endsWith").',
  )
  ..addFlag(
    _argAnalysisOptions,
    defaultsTo: true,
    help:
        'Read `string_literal_finder: exclude_globs:` from the '
        'analysis_options.yaml next to --path.',
  )
  ..addOption(
    _argCacheDir,
    help:
        'Directory for the analyzer cache. Reusing it between runs is '
        'roughly twice as fast; safe to cache in CI.',
  )
  ..addSeparator('Filtering (off by default — see README for trade-offs):')
  ..addOption(
    _argMinLength,
    help: 'Ignore literals with fewer than this many visible characters.',
  )
  ..addMultiOption(
    _argIgnorePattern,
    help: 'Ignore literals matching this regular expression. Repeatable.',
  )
  ..addFlag(
    _argIgnoreSymbols,
    negatable: false,
    help:
        'Ignore literals with no word in them: punctuation, digits and dates, '
        'plus pure substitutions like \'\$error\'. Keeps templates such as '
        "' \$unit'. Removed 16% of findings on a real corpus; start here.",
  )
  ..addFlag(
    _argProseOnly,
    negatable: false,
    help:
        'Ignore literals that are not a phrase of two or more words. Very '
        'aggressive (-67%) and discards real single-word labels such as '
        "'Cancel' - for triage, not for a gate.",
  )
  ..addSeparator('CI gating:')
  ..addOption(
    _argBaseline,
    help: 'Baseline file. Only literals absent from it cause a failure.',
  )
  ..addFlag(
    _argWriteBaseline,
    negatable: false,
    help: 'Record the current findings into --baseline and exit 0.',
  )
  ..addOption(
    _argMaxLiterals,
    help: 'Only fail if more than this many literals are found.',
  )
  ..addSeparator('Output:')
  ..addOption(
    _argFormat,
    allowed: [_formatPretty, _formatJson],
    defaultsTo: _formatPretty,
    help: 'Output format. `json` writes every finding to stdout.',
  )
  ..addOption(_argMetricsFile, abbr: 'm', help: 'File to write json metrics to')
  ..addOption(
    _argAnnotationFile,
    help:
        'File for annotations as taken by '
        'https://github.com/Attest/annotations-action/',
  )
  ..addOption(
    _argAnnotationRoot,
    help: 'Make paths relative to the given root directory.',
  )
  ..addFlag(_argVerbose, abbr: 'v')
  ..addFlag(_argSilent, abbr: 's')
  ..addFlag(_argHelp, abbr: 'h', negatable: false);

Future<void> main(List<String> arguments) async {
  final parser = _buildParser();
  // Diagnostics belong on stderr so that `--format=json` keeps stdout
  // parseable; without `stderrLevel` every record is print()ed to stdout.
  PrintAppender.setupLogging(level: Level.SEVERE, stderrLevel: Level.SEVERE);
  try {
    exitCode = await _run(parser, parser.parse(arguments));
  } on UsageException catch (e) {
    stderr.writeln('$executableName [arguments]');
    stderr.writeln(e);
    exitCode = _exitUsage;
  } on FormatException catch (e) {
    stderr.writeln('$executableName: ${e.message}');
    exitCode = _exitUsage;
  } catch (e, stackTrace) {
    _logger.severe('Error during analysis.', e, stackTrace);
    exitCode = _exitError;
  }
}

Future<int> _run(ArgParser parser, ArgResults results) async {
  if (results.flag(_argHelp)) {
    throw UsageException('Showing help.', parser.usage);
  }
  final json = results.option(_argFormat) == _formatJson;
  PrintAppender.setupLogging(
    stderrLevel: Level.SEVERE,
    level: switch (results) {
      // In json mode stdout carries the report, so keep everything else off
      // unless it was asked for explicitly.
      _ when results.flag(_argSilent) || json => Level.SEVERE,
      _ when results.flag(_argVerbose) => Level.ALL,
      _ => Level.FINE,
    },
  );
  final basePath = results.option(_argPath);
  if (basePath == null) {
    throw UsageException('Required $_argPath parameter.', parser.usage);
  }
  final absolutePath = path.absolute(basePath);

  final baselinePath = results.option(_argBaseline);
  final writeBaseline = results.flag(_argWriteBaseline);
  if (writeBaseline && baselinePath == null) {
    throw UsageException(
      '--$_argWriteBaseline requires --$_argBaseline.',
      parser.usage,
    );
  }

  final stringLiteralFinder = StringLiteralFinder(
    basePath: absolutePath,
    excludePaths: [
      ...ExcludePathChecker.excludePathDefaults,
      ...results
          .multiOption(_argExcludePath)
          .map(ExcludePathChecker.excludePathCheckerStartsWith),
      ...results
          .multiOption(_argExcludeSuffix)
          .map(ExcludePathChecker.excludePathCheckerEndsWith),
    ],
    analysisOptions: results.flag(_argAnalysisOptions)
        ? _loadAnalysisOptions(absolutePath)
        : null,
    cachePath: results.option(_argCacheDir)?.let(path.absolute),
  );
  final filters = _buildFilters(results);
  final allFound = await stringLiteralFinder.start();
  final foundStringLiterals = filters.apply(allFound);

  if (writeBaseline) {
    final baseline = Baseline.fromFound(foundStringLiterals, absolutePath);
    await File(baselinePath!).writeAsString(baseline.toJson());
    stdout.writeln(
      'Recorded ${baseline.totalCount} literals in '
      '${baseline.literals.length} files to $baselinePath.',
    );
    return _exitOk;
  }

  final comparison = baselinePath?.let(
    (file) => _readBaseline(file).compare(foundStringLiterals, absolutePath),
  );
  final reported = comparison?.newLiterals ?? foundStringLiterals;

  await results
      .option(_argAnnotationFile)
      ?.let(
        (file) => _generateAnnotationsFile(
          file,
          reported,
          pathRelativeFrom: results.option(_argAnnotationRoot),
        ),
      );

  final maxLiterals = results
      .option(_argMaxLiterals)
      ?.let((e) => _nonNegativeInt(e, _argMaxLiterals));
  final failed = reported.length > (maxLiterals ?? 0);

  final metrics = <String, Object?>{
    'stringLiterals': reported.length,
    'stringLiteralsFiles': reported.map((e) => e.filePath).toSet().length,
    'filesAnalyzed': stringLiteralFinder.filesAnalyzed.length,
    'filesSkipped': stringLiteralFinder.filesSkipped.length,
    'filesWithoutLiterals':
        stringLiteralFinder.filesAnalyzed.length -
        allFound.map((e) => e.filePath).toSet().length,
    if (filters.isNotEmpty) ...{
      'literalsBeforeFiltering': allFound.length,
      'filteredOut': allFound.length - foundStringLiterals.length,
    },
    if (comparison != null) ...{
      'baselineLiterals': foundStringLiterals.length - reported.length,
      'baselineObsolete': comparison.obsoleteCount,
    },
  };

  if (json) {
    _writeJsonReport(reported, metrics, absolutePath, failed: failed);
  } else {
    _writePrettyReport(
      reported,
      metrics,
      absolutePath,
      filters,
      comparison: comparison,
    );
  }

  await results
      .option(_argMetricsFile)
      ?.let(
        (metricsFile) => File(metricsFile).writeAsString(_encodeJson(metrics)),
      );

  return failed ? _exitLiteralsFound : _exitOk;
}

/// Parses [value], reporting the flag it came from rather than leaving
/// `int.parse` to complain about a "radix-10 number" nobody asked for.
int _nonNegativeInt(String value, String flag) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw FormatException(
      '--$flag expects a non-negative integer, got "$value".',
    );
  }
  return parsed;
}

List<LiteralFilter> _buildFilters(ArgResults results) => [
  ...?results
      .option(_argMinLength)
      ?.let((e) => [MinLengthFilter(_nonNegativeInt(e, _argMinLength))]),
  ...results.multiOption(_argIgnorePattern).map(PatternFilter.parse),
  if (results.flag(_argIgnoreSymbols)) const NoLetterFilter(),
  if (results.flag(_argProseOnly)) const ProseOnlyFilter(),
];

/// Loads the `analysis_options.yaml` governing [basePath], searching upwards
/// the same way the analyzer plugin does.
AnalysisOptions? _loadAnalysisOptions(String basePath) {
  var dir = Directory(basePath).absolute;
  while (true) {
    final file = File(path.join(dir.path, 'analysis_options.yaml'));
    if (file.existsSync()) {
      _logger.fine('Reading exclude_globs from ${file.path}');
      return AnalysisOptions.loadFromYaml(dir.path, file.readAsStringSync());
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}

Baseline _readBaseline(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FormatException(
      'Baseline file $filePath does not exist. Create it with '
      '--$_argBaseline=$filePath --$_argWriteBaseline.',
    );
  }
  return Baseline.fromJson(file.readAsStringSync());
}

String _encodeJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

Map<String, Object?> _literalToJson(
  FoundStringLiteral literal,
  String basePath,
) => {
  'path': path.relative(literal.filePath, from: basePath),
  'line': literal.loc.lineNumber,
  'column': literal.loc.columnNumber,
  'endLine': literal.locEnd.lineNumber,
  'endColumn': literal.locEnd.columnNumber,
  'literal': literal.sourceText,
  'value': literal.textValue,
};

void _writeJsonReport(
  List<FoundStringLiteral> found,
  Map<String, Object?> metrics,
  String basePath, {
  required bool failed,
}) {
  stdout.writeln(
    _encodeJson({
      'ok': !failed,
      'metrics': metrics,
      'literals': [
        for (final literal in found) _literalToJson(literal, basePath),
      ],
    }),
  );
}

void _writePrettyReport(
  List<FoundStringLiteral> found,
  Map<String, Object?> metrics,
  String basePath,
  List<LiteralFilter> filters, {
  BaselineComparison? comparison,
}) {
  for (final literal in found) {
    final relative = path.relative(literal.filePath, from: basePath);
    stdout.writeln(
      '$relative:${literal.loc.lineNumber}:'
      '${literal.loc.columnNumber} ${literal.sourceText}',
    );
  }
  final fileCount = found.map((e) => e.filePath).toSet().length;
  final label = comparison == null ? 'literal' : 'new literal';
  stdout.writeln(
    'Found ${found.length} $label${found.length == 1 ? '' : 's'} in '
    '$fileCount file${fileCount == 1 ? '' : 's'}.',
  );
  for (final filter in filters) {
    stdout.writeln('  (ignoring literals ${filter.description})');
  }
  if (comparison != null && comparison.obsoleteCount > 0) {
    stdout.writeln(
      '  ${comparison.obsoleteCount} baseline entries no longer '
      'exist; re-record the baseline to shrink it.',
    );
  }
  stdout.writeln(_encodeJson(metrics));
}

Future<void> _generateAnnotationsFile(
  String file,
  List<FoundStringLiteral> foundStringLiterals, {
  String? pathRelativeFrom,
}) async {
  final pathValue =
      pathRelativeFrom?.let(
        (from) =>
            (String p) => path.relative(p, from: from),
      ) ??
      ((String p) => p);
  final annotations = foundStringLiterals
      .map(
        (e) => {
          'message': 'String literal',
          'level': 'notice',
          'path': pathValue(e.filePath),
          'column': {'start': e.loc.columnNumber, 'end': e.locEnd.columnNumber},
          'line': {'start': e.loc.lineNumber, 'end': e.locEnd.lineNumber},
        },
      )
      .toList();
  await File(file).writeAsString(json.encode(annotations));
}
