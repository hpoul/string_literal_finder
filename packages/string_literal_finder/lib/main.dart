import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:logging/logging.dart';
import 'package:string_literal_finder/src/analysis_options.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';

export 'package:string_literal_finder/src/analysis_options.dart'
    show AnalysisOptions;

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
    : super(name: 'literal_string', description: 'Finds literal strings');

  @override
  LintCode get diagnosticCode => code;

  final Map<String, AnalysisOptions> _analysisOptions = {};

  AnalysisOptions? findAnalysisOptions(File? file) {
    if (file == null) {
      return null;
    }
    var dir = file.parent;
    while (!dir.isRoot) {
      try {
        final optionsFile = dir.getFile('analysis_options.yaml');
        if (optionsFile.exists) {
          return _analysisOptions[optionsFile.path] ??= () {
            _logger.finer('parsing ${optionsFile.path}');
            return AnalysisOptions.loadFromYaml(
              dir.path,
              optionsFile.readAsStringSync(),
            );
          }();
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
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    // The plugin framework has no API for rule specific configuration yet,
    // so the `string_literal_finder:` section of `analysis_options.yaml` is
    // parsed by hand in `findAnalysisOptions` below.
    // See https://github.com/dart-lang/sdk/issues/63098
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
        reportAtNode(foundStringLiteral.stringLiteral, arguments: [stringCode]);
      },
    );
    // All three concrete `StringLiteral` subtypes have to be registered
    // individually. Omitting `StringInterpolation` used to make the plugin
    // blind to exactly the literals that matter most, e.g. `'$distance km'`.
    registry.addSimpleStringLiteral(this, visitor);
    registry.addAdjacentStrings(this, visitor);
    registry.addStringInterpolation(this, visitor);
  }
}
