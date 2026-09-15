import 'dart:convert';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// The `string_literal_finder:` section of an `analysis_options.yaml`.
///
/// The analyzer plugin framework has no API yet for handing rule specific
/// configuration to a rule (https://github.com/dart-lang/sdk/issues/63098),
/// so the file is located and parsed by hand. Both front ends use this class,
/// so that a glob which silences a warning in the IDE also silences it in CI.
class AnalysisOptions {
  AnalysisOptions({
    required this.root,
    required this.excludeGlobs,
    this.debug = false,
  });

  /// Options with no exclusions at all.
  AnalysisOptions.empty(this.root) : excludeGlobs = const [], debug = false;

  /// Parses [yamlSource], the contents of an `analysis_options.yaml` located
  /// in the directory [root]. Globs are matched relative to [root].
  static AnalysisOptions loadFromYaml(String root, String yamlSource) {
    final yaml = json.decode(json.encode(loadYaml(yamlSource)));
    if (yaml is! Map<String, dynamic>) {
      return AnalysisOptions.empty(root);
    }
    final options = yaml['string_literal_finder'] as Map<String, dynamic>?;
    final excludeGlobs =
        options?['exclude_globs'] as List<dynamic>? ?? <dynamic>[];
    final debug = options?['debug'] as bool? ?? false;
    return AnalysisOptions(
      root: root,
      excludeGlobs: excludeGlobs.cast<String>().map(Glob.new).toList(),
      debug: debug,
    );
  }

  /// Directory containing the `analysis_options.yaml` these options came from.
  final String root;

  /// Globs, relative to [root], of files which should not be reported.
  final List<Glob> excludeGlobs;

  final bool debug;

  /// Whether the file at the absolute [filePath] is excluded.
  bool isExcluded(String filePath) {
    if (filePath.endsWith('.g.dart')) {
      return true;
    }
    final relative = path.isWithin(root, filePath)
        ? path.relative(filePath, from: root)
        : filePath;
    // Globs are always written with forward slashes, even on Windows.
    final normalized = path.toUri(relative).path;
    return excludeGlobs.any((glob) => glob.matches(normalized));
  }
}
