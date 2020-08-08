import 'dart:io';

import 'package:logging_appenders/logging_appenders.dart';
import 'package:string_literal_finder/string_literal_finder.dart';
import 'package:path/path.dart' as path;

import 'package:logging/logging.dart';

final _logger = Logger('string_literal_finder');

Future<void> main(List<String> arguments) async {
//  PrintAppender.setupLogging(level: Level.FINER);
  PrintAppender.setupLogging(level: Level.ALL);
  try {
    if (arguments.isEmpty) {
      print('Usage: ${Platform.executable} <library path>');
      exit(1);
    }
    final basePath = arguments[0];
    final absolutePath = path.absolute(basePath);
    final foundStringLiterals = await StringLiteralFinder(absolutePath).start();
    final fileCount = foundStringLiterals.map((e) => e.filePath).toSet();
    print('Found ${foundStringLiterals.length} literals in '
        '${fileCount.length} files.');
    if (foundStringLiterals.isNotEmpty) {
      exitCode = 1;
    }
  } catch (e, stackTrace) {
    _logger.severe('Error during analysis.', e, stackTrace);
    exitCode = 70;
  }
}
