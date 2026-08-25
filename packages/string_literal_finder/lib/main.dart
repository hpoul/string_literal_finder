import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:logging/logging.dart';
import 'package:string_literal_finder/src/analysis_options.dart';
import 'package:string_literal_finder/src/fixes.dart';
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
    registry.registerFixForRule(LiteralStringRule.code, WrapWithNonNls.new);
    registry.registerFixForRule(LiteralStringRule.code, AddNonNlsComment.new);
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

  /// Parsed options, keyed by the options file and the modification stamp they
  /// were read at, so editing `exclude_globs` takes effect without restarting
  /// the analyzer.
  final Map<String, (int stamp, AnalysisOptions options)> _analysisOptions = {};

  /// Directories already known to have no options file above them. Without
  /// this a project with no `analysis_options.yaml` walks to the filesystem
  /// root again for every literal.
  final Set<String> _withoutOptions = {};

  AnalysisOptions? findAnalysisOptions(File? file) {
    if (file == null) {
      return null;
    }
    final searched = <String>[];
    for (var dir = file.parent; ; dir = dir.parent) {
      if (_withoutOptions.contains(dir.path)) {
        break;
      }
      searched.add(dir.path);
      try {
        final optionsFile = dir.getFile('analysis_options.yaml');
        if (optionsFile.exists) {
          final stamp = optionsFile.modificationStamp;
          final cached = _analysisOptions[optionsFile.path];
          if (cached != null && cached.$1 == stamp) {
            return cached.$2;
          }
          _logger.finer('parsing ${optionsFile.path}');
          final options = AnalysisOptions.loadFromYaml(
            dir.path,
            optionsFile.readAsStringSync(),
          );
          _analysisOptions[optionsFile.path] = (stamp, options);
          return options;
        }
      } catch (e, stackTrace) {
        // Failing here silently disables every exclude_glob, so say so.
        _logger.warning(
          'Unable to read analysis options near ${dir.path}',
          e,
          stackTrace,
        );
        break;
      }
      // Checked after reading, so an options file at the root is still found.
      if (dir.isRoot) {
        break;
      }
    }
    _withoutOptions.addAll(searched);
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
      // The rule framework walks the unit itself and dispatches every
      // registered node type, so the visitor must not descend as well.
      descendIntoInterpolations: false,
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
