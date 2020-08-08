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

Future<void> main(List<String> arguments) async {
//  PrintAppender.setupLogging(level: Level.FINER);
  PrintAppender.setupLogging(level: Level.ALL);
  final parser = ArgParser()
    ..addOption(
      ARG_PATH,
      abbr: 'p',
      help: 'Base path of your library.',
    )
    ..addFlag(ARG_HELP, abbr: 'h', negatable: false);
  try {
    final results = parser.parse(arguments);
    if (results[ARG_HELP] as bool) {
      throw UsageException('Showing help.', parser.usage);
    }
    if (results[ARG_PATH] == null) {
      throw UsageException('Required $ARG_PATH parameter.', parser.usage);
    }
    final basePath = results[ARG_PATH] as String;
    final absolutePath = path.absolute(basePath);
    final foundStringLiterals = await StringLiteralFinder(absolutePath).start();
    final fileCount = foundStringLiterals.map((e) => e.filePath).toSet();
    print('Found ${foundStringLiterals.length} literals in '
        '${fileCount.length} files.');
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
