import 'dart:convert';

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:yaml/yaml.dart';

final _logger = Logger('string_literal_finder');

final plugin = LiteralStringFinderPlugin();

class LiteralStringFinderPlugin extends Plugin {
  @override
  String get name => 'String Literal Finder';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(LiteralStringRule());
  }
}

class LiteralStringRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'literal_string',
    'Found string literal {0}',
    correctionMessage: "Try externalizing literal string for translation",
  );

  LiteralStringRule()
      : super(
          name: 'literal_string',
          description: 'Finds literal strings',
        );

  @override
  LintCode get diagnosticCode => code;

  final Map<String, AnalysisOptions> _analysisOptions = {};

  // AnalysisOptions _getAnalysisOptions(AnalysisContext context) {
  //   final optionsPath = context.contextRoot.optionsFile;
  //   _logger.info('Loading analysis options.');
  //   final exists = optionsPath?.exists ?? false;
  //   if (!exists || optionsPath == null) {
  //     _logger.warning('Unable to resolve optionsFile.');
  //     return AnalysisOptions(excludeGlobs: []);
  //   }
  //   return AnalysisOptions.loadFromYaml(optionsPath.readAsStringSync());
  // }
  AnalysisOptions? findAnalysisOptions(File? file) {
    if (file == null) {
      return null;
    }
    var dir = file.parent;
    while (!dir.isRoot) {
      try {
        final optionsFile = dir.getChildAssumingFile('analysis_options.yaml');
        if (optionsFile.exists) {
          final x = _analysisOptions[optionsFile.path];
          if (x != null) {
            return x;
          }
          _logger.finer('parsing ${optionsFile.path}');
          final ret =
              AnalysisOptions.loadFromYaml(dir, optionsFile.readAsStringSync());
          _analysisOptions[optionsFile.path] = ret;
          return ret;
        }
        dir = dir.parent;
      } catch (e) {
        break;
      }
    }
    return null;
  }

  @override
  void registerNodeProcessors(
      RuleVisitorRegistry registry, RuleContext context) {
    // TODO check analysis_options file for ignored files.
    // https://github.com/dart-lang/sdk/issues/61770
    final visitor = StringLiteralVisitor.context(
        context: () => StringLiteralContext(
              filePath: context.currentUnit?.file.path ?? '',
              unit: context.currentUnit?.unit,
              lineInfo: context.currentUnit?.unit.lineInfo,
            ),
        foundStringLiteral: (foundStringLiteral) {
          final file = context.currentUnit?.file;
          final options = findAnalysisOptions(file);
          if (file != null) {
            if (options != null && options.isExcluded(file.path)) {
              return;
            }
          }
          final content = context.currentUnit?.content ?? '';
          String stringValue() {
            if (content.length < foundStringLiteral.charEnd) {
              return '';
            }
            return content
                .substring(
                  foundStringLiteral.charOffset,
                  foundStringLiteral.charEnd,
                )
                .trim();
          }

          final stringCode = foundStringLiteral.stringValue ?? stringValue();
          reportAtNode(foundStringLiteral.stringLiteral, arguments: [
            stringCode,
          ]);
        });
    registry.addSimpleStringLiteral(this, visitor);
    registry.addAdjacentStrings(this, visitor);
  }
}

class AnalysisOptions {
  AnalysisOptions({
    required this.root,
    required this.excludeGlobs,
    this.debug = false,
  });

  static AnalysisOptions loadFromYaml(Folder root, String yamlSource) {
    final yaml =
        json.decode(json.encode(loadYaml(yamlSource))) as Map<String, dynamic>;
    final options = yaml['string_literal_finder'] as Map<String, dynamic>?;
    final excludeGlobs =
        options?['exclude_globs'] as List<dynamic>? ?? <dynamic>[];
    final debug = options?['debug'] as bool? ?? false;
    return AnalysisOptions(
      root: root,
      excludeGlobs: excludeGlobs.cast<String>().map((e) => Glob(e)).toList(),
      debug: debug,
    );
  }

  final Folder root;
  final List<Glob> excludeGlobs;
  final bool debug;

  bool isExcluded(String path) {
    if (path.endsWith('.g.dart')) {
      return true;
    }
    final relative = root.relativeIfContains(path);
    return excludeGlobs.any((glob) => glob.matches(relative ?? path));
  }
}
