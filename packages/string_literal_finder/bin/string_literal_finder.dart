import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:string_literal_finder/string_literal_finder.dart';

final _logger = Logger('string_literal_finder');

const executableName = 'string_literal_finder';
const ARG_PATH = 'path';
const ARG_HELP = 'help';
const ARG_VERBOSE = 'verbose';
const ARG_SILENT = 'silent';
const ARG_EXCLUDE_PATH = 'exclude-path';
const ARG_EXCLUDE_SUFFIX = 'exclude-suffix';
const ARG_METRICS_FILE = 'metrics-output-file';
const ARG_ANNOTATION_FILE = 'annotations-output-file';
const ARG_ANNOTATION_ROOT = 'annotations-path-root';

Future<void> main(List<String> arguments) async {
  PrintAppender.setupLogging(level: Level.SEVERE);
  final parser = ArgParser()
    ..addOption(
      ARG_PATH,
      abbr: 'p',
      help: 'Base path of your library.',
    )
    ..addOption(ARG_METRICS_FILE,
        abbr: 'm', help: 'File to write json metrics to')
    ..addOption(ARG_ANNOTATION_FILE,
        help: 'File for annotations as taken by '
            'https://github.com/Attest/annotations-action/')
    ..addOption(ARG_ANNOTATION_ROOT,
        help: 'Maks paths relative to the given root directory.')
    ..addMultiOption(ARG_EXCLUDE_PATH,
        help: 'Exclude paths (relative to path, "startsWith").')
    ..addMultiOption(ARG_EXCLUDE_SUFFIX,
        help: 'Exclude path suffixes ("endsWith").')
    ..addFlag(ARG_VERBOSE, abbr: 'v')
    ..addFlag(ARG_SILENT, abbr: 's')
    ..addFlag(ARG_HELP, abbr: 'h', negatable: false);
  try {
    final results = parser.parse(arguments);
    if (results[ARG_HELP] as bool) {
      throw UsageException('Showing help.', parser.usage);
    }
    PrintAppender.setupLogging(
        level: results[ARG_SILENT] as bool
            ? Level.SEVERE
            : results[ARG_VERBOSE] as bool
                ? Level.ALL
                : Level.FINE);
    if (results[ARG_PATH] == null) {
      throw UsageException('Required $ARG_PATH parameter.', parser.usage);
    }
    final basePath = results[ARG_PATH] as String;
    final absolutePath = path.absolute(basePath);
    final stringLiteralFinder = StringLiteralFinder(
      basePath: absolutePath,
      excludePaths: ExcludePathChecker.excludePathDefaults
          .followedBy((results[ARG_EXCLUDE_PATH] as List<String>)
              .map((e) => ExcludePathChecker.excludePathCheckerStartsWith(e)))
          .followedBy((results[ARG_EXCLUDE_SUFFIX] as List<String>)
              .map((e) => ExcludePathChecker.excludePathCheckerEndsWith(e)))
          .toList(),
    );
    final foundStringLiterals = await stringLiteralFinder.start();

    await (results[ARG_ANNOTATION_FILE] as String?)?.let((file) =>
        _generateAnnotationsFile(file, foundStringLiterals,
            pathRelativeFrom: results[ARG_ANNOTATION_ROOT] as String?));

    final fileCount = foundStringLiterals.map((e) => e.filePath).toSet();
    final nonLiteralFiles =
        stringLiteralFinder.filesAnalyzed.difference(fileCount);
    _logger.finest('Files without Literals: $nonLiteralFiles 👍️');
    print('Found ${foundStringLiterals.length} literals in '
        '${fileCount.length} files.');
    final result = {
      'stringLiterals': foundStringLiterals.length,
      'stringLiteralsFiles': fileCount.length,
      'filesAnalyzed': stringLiteralFinder.filesAnalyzed.length,
      'filesSkipped': stringLiteralFinder.filesSkipped.length,
      'filesWithoutLiterals':
          stringLiteralFinder.filesAnalyzed.length - fileCount.length,
    };
    final jsonMetrics = const JsonEncoder.withIndent('  ').convert(result);
    print(jsonMetrics);
    await (results[ARG_METRICS_FILE] as String?)?.let(
        (metricsFile) async => File(metricsFile).writeAsString(jsonMetrics));
    if (foundStringLiterals.isNotEmpty) {
      exitCode = 1;
    }
  } on UsageException catch (e) {
    print('$executableName [arguments]');
    print(e);
    exitCode = 1;
  } catch (e, stackTrace) {
    _logger.severe('Error during analysis.', e, stackTrace);
    exitCode = 70;
  }
}

Future<void> _generateAnnotationsFile(
  String file,
  List<FoundStringLiteral> foundStringLiterals, {
  String? pathRelativeFrom,
}) async {
  print('ok?');
  final pathValue = pathRelativeFrom
          ?.let((from) => (String p) => path.relative(p, from: from)) ??
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

extension<T extends Object> on T {
  U let<U>(U Function(T value) cb) {
    return cb(this);
  }
}
