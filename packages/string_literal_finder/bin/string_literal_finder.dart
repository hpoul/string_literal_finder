import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/string_literal_finder.dart';

final _logger = Logger('string_literal_finder');

const executableName = 'string_literal_finder';
const _argPath = 'path';
const _argHelp = 'help';
const _argVerbose = 'verbose';
const _argSilent = 'silent';
const _argExcludePath = 'exclude-path';
const _argExcludeSuffix = 'exclude-suffix';
const _argMetricsFile = 'metrics-output-file';
const _argAnnotationFile = 'annotations-output-file';
const _argAnnotationRoot = 'annotations-path-root';

Future<void> main(List<String> arguments) async {
  PrintAppender.setupLogging(level: Level.SEVERE);
  final parser = ArgParser()
    ..addOption(
      _argPath,
      abbr: 'p',
      help: 'Base path of your library.',
    )
    ..addOption(_argMetricsFile,
        abbr: 'm', help: 'File to write json metrics to')
    ..addOption(_argAnnotationFile,
        help: 'File for annotations as taken by '
            'https://github.com/Attest/annotations-action/')
    ..addOption(_argAnnotationRoot,
        help: 'Maks paths relative to the given root directory.')
    ..addMultiOption(_argExcludePath,
        help: 'Exclude paths (relative to path, "startsWith").')
    ..addMultiOption(_argExcludeSuffix,
        help: 'Exclude path suffixes ("endsWith").')
    ..addFlag(_argVerbose, abbr: 'v')
    ..addFlag(_argSilent, abbr: 's')
    ..addFlag(_argHelp, abbr: 'h', negatable: false);
  try {
    final results = parser.parse(arguments);
    if (results[_argHelp] as bool) {
      throw UsageException('Showing help.', parser.usage);
    }
    PrintAppender.setupLogging(
        level: results[_argSilent] as bool
            ? Level.SEVERE
            : results[_argVerbose] as bool
                ? Level.ALL
                : Level.FINE);
    if (results[_argPath] == null) {
      throw UsageException('Required $_argPath parameter.', parser.usage);
    }
    final basePath = results[_argPath] as String;
    final absolutePath = path.absolute(basePath);
    final stringLiteralFinder = StringLiteralFinder(
      basePath: absolutePath,
      excludePaths: ExcludePathChecker.excludePathDefaults
          .followedBy((results[_argExcludePath] as List<String>)
              .map((e) => ExcludePathChecker.excludePathCheckerStartsWith(e)))
          .followedBy((results[_argExcludeSuffix] as List<String>)
              .map((e) => ExcludePathChecker.excludePathCheckerEndsWith(e)))
          .toList(),
    );
    final foundStringLiterals = await stringLiteralFinder.start();

    await (results[_argAnnotationFile] as String?)?.let((file) =>
        _generateAnnotationsFile(file, foundStringLiterals,
            pathRelativeFrom: results[_argAnnotationRoot] as String?));

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
    await (results[_argMetricsFile] as String?)?.let(
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
