import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:string_literal_finder/string_literal_finder.dart';
import 'package:path/path.dart' as path;

import 'package:logging/logging.dart';

final _logger = Logger('string_literal_finder');

const executableName = 'string_literal_finder';
const ARG_PATH = 'path';
const ARG_HELP = 'help';
const ARG_VERBOSE = 'verbose';
const ARG_SILENT = 'silent';
const ARG_EXCLUDE_PATH = 'exclude-path';
const ARG_METRICS_FILE = 'metrics-output-file';

Future<void> main(List<String> arguments) async {
//  PrintAppender.setupLogging(level: Level.FINER);
  final parser = ArgParser()
    ..addOption(
      ARG_PATH,
      abbr: 'p',
      help: 'Base path of your library.',
    )
    ..addOption(ARG_METRICS_FILE,
        abbr: 'm', help: 'File to write json metrics to')
    ..addMultiOption(ARG_EXCLUDE_PATH,
        help: 'Exclude paths (relative to path).')
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
            : results[ARG_VERBOSE] as bool ? Level.ALL : Level.FINE);
    if (results[ARG_PATH] == null) {
      throw UsageException('Required $ARG_PATH parameter.', parser.usage);
    }
    final basePath = results[ARG_PATH] as String;
    final absolutePath = path.absolute(basePath);
    final stringLiteralFinder = StringLiteralFinder(
      basePath: absolutePath,
      excludePaths: results[ARG_EXCLUDE_PATH] as List<String>,
    );
    final foundStringLiterals = await stringLiteralFinder.start();
    final fileCount = foundStringLiterals.map((e) => e.filePath).toSet();
    print('Found ${foundStringLiterals.length} literals in '
        '${fileCount.length} files.');
    final result = {
      'stringLiterals': foundStringLiterals.length,
      'stringLiteralsFiles': fileCount.length,
      'filesAnalyzed': stringLiteralFinder.filesAnalyzed.length,
      'filesSkipped': stringLiteralFinder.filesSkipped.length,
    };
    final jsonMetrics = const JsonEncoder.withIndent('  ').convert(result);
    print(jsonMetrics);
    await (results[ARG_METRICS_FILE] as String)?.let(
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

extension<T extends Object> on T {
  U let<U>(U Function(T value) cb) {
    return cb(this);
  }
}
