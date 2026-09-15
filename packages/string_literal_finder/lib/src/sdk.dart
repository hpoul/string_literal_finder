// `getSdkPath` has no public home.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:analyzer/src/util/sdk.dart' as analyzer;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

final _logger = Logger('string_literal_finder.sdk');

/// The file every Dart SDK has, used to tell a real SDK root from a guess.
const _sdkMarker = 'lib/_internal/sdk_library_metadata/lib/libraries.dart';

/// Resolves the Dart SDK to analyse against, preferring [configured].
///
/// The analyzer derives the SDK from `Platform.resolvedExecutable`. That is
/// correct on the Dart VM, and wrong for a binary produced by
/// `dart compile exe`, where the resolved executable *is* the binary — so an
/// AOT build of this tool used to die with a `PathNotFoundException` for a
/// `libraries.dart` next to itself.
///
/// Falls back to `DART_SDK`, then to a `dart` on `PATH`, and only then gives
/// up. Throws a [StateError] naming the flag rather than letting the analyzer
/// fail later with a path nobody recognises.
String resolveSdkPath(String? configured) {
  if (configured != null) {
    if (!_looksLikeSdk(configured)) {
      throw StateError(
        'No Dart SDK at $configured '
        '(expected to find $_sdkMarker under it).',
      );
    }
    return configured;
  }
  for (final candidate in _candidates()) {
    if (candidate != null && _looksLikeSdk(candidate)) {
      _logger.fine(() => 'Using Dart SDK at $candidate.');
      return candidate;
    }
  }
  throw StateError(
    'Unable to locate the Dart SDK. Pass --dart-sdk=<path>, or set DART_SDK. '
    'This normally only happens for a binary built with `dart compile exe`, '
    'which cannot work the SDK out from its own location.',
  );
}

Iterable<String?> _candidates() sync* {
  // What the analyzer would have chosen, which is right on the Dart VM.
  yield _tryAnalyzerDefault();
  yield Platform.environment['DART_SDK'];
  yield* _sdkFromPath();
}

String? _tryAnalyzerDefault() {
  try {
    return analyzer.getSdkPath();
  } catch (e) {
    _logger.fine(() => 'Analyzer could not derive an SDK path: $e');
    return null;
  }
}

/// SDK roots to try relative to the first `dart` on `PATH`.
Iterable<String> _sdkFromPath() sync* {
  final String executable;
  try {
    final which = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(which, ['dart']);
    if (result.exitCode != 0) {
      return;
    }
    final found = (result.stdout as String).split('\n').first.trim();
    if (found.isEmpty) {
      return;
    }
    // `dart` is very often a symlink.
    executable = File(found).resolveSymbolicLinksSync();
  } catch (e) {
    _logger.fine(() => 'Unable to find a dart executable on PATH: $e');
    return;
  }
  final bin = path.dirname(executable);
  // `<sdk>/bin/dart`.
  yield path.dirname(bin);
  // Flutter ships a wrapper at `<flutter>/bin/dart` and the real SDK below it.
  yield path.join(bin, 'cache', 'dart-sdk');
  yield bin;
}

bool _looksLikeSdk(String sdkPath) =>
    File(path.joinAll([sdkPath, ..._sdkMarker.split('/')])).existsSync();
