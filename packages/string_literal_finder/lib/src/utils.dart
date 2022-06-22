import 'dart:io';

import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as p;

class StringLiteralFinderUtils {
  static String get _userHome =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/var/tmp';

  static void setupDebugLogging() {
    Logger.root.clearListeners();
    Logger.root.level = Level.ALL;
    final dir = p.join(_userHome, 'tmp');
    try {
      Directory(dir).createSync(recursive: true);
    } catch (e, stackTrace) {
      print('Error while creating logging directory $dir: $e\n$stackTrace');
    }
    final appender = RotatingFileAppender(
      baseFilePath: p.join(dir, 'string_literal_finder.log.txt'),
    );
    appender.attachToLogger(Logger.root);
  }
}
