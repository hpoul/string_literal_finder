import 'dart:io';

import 'package:logging_appenders/logging_appenders.dart';
import 'package:string_literal_finder/string_literal_finder.dart';

import 'package:logging/logging.dart';

final _logger = Logger('string_literal_finder');

Future<void> main(List<String> arguments) async {
  PrintAppender.setupLogging(level: Level.FINER);
  try {
    if (arguments.isEmpty) {
      print('Usage: ${Platform.executable} <library path>');
      exit(1);
    }
    final path = arguments[0];
    final foundStringLiterals = await StringLiteralFinder(path).start();
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
