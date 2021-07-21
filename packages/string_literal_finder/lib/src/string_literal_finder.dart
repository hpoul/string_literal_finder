import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:source_gen/source_gen.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

final _logger = Logger('string_literal_finder');

abstract class ExcludePathChecker {
  const ExcludePathChecker();

  static ExcludePathChecker excludePathCheckerStartsWith(String exclude) =>
      _ExcludePathCheckerImpl(
        predicate: (path) => path.startsWith(exclude),
        description: 'Starts with: $exclude',
      );

  static ExcludePathChecker excludePathCheckerEndsWith(String exclude) =>
      _ExcludePathCheckerImpl(
        predicate: (path) => path.endsWith(exclude),
        description: 'Ends with: $exclude',
      );

  static final excludePathDefaults = [
    excludePathCheckerStartsWith('l10n'),
    excludePathCheckerEndsWith('.g.dart'),
    excludePathCheckerEndsWith('.freezed.dart'),
  ];

  bool shouldExclude(String path);
}

class _ExcludePathCheckerImpl extends ExcludePathChecker {
  const _ExcludePathCheckerImpl(
      {required this.predicate, required this.description});
  final bool Function(String path) predicate;
  final String description;

  @override
  bool shouldExclude(String path) => predicate(path);
}

/// The main finder class which will use dart analyzer to analyse all
/// dart files in the given [basePath] and look for string literals.
/// Some literals will be (smartly) ignored which should not be localized.
class StringLiteralFinder {
  StringLiteralFinder({
    required this.basePath,
    required this.excludePaths,
  });

  /// Base path of the library.
  final String basePath;

  /// Paths which should be ignored. Usually something like `l10n/' to ignore
  /// the actual translation files.
  final List<ExcludePathChecker> excludePaths;

  final List<FoundStringLiteral> foundStringLiterals = [];
  final Set<String> filesSkipped = <String>{};
  final Set<String> filesAnalyzed = <String>{};

  /// Starts the analyser and returns information about the found
  /// string literals.
  Future<List<FoundStringLiteral>> start() async {
    _logger.fine('Starting analysis.');
    final collection = AnalysisContextCollection(includedPaths: [basePath]);
    _logger.finer('Finding contexts.');
    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        final relative = path.relative(filePath, from: basePath);
        if (excludePaths
                .where((element) => element.shouldExclude(relative))
                .isNotEmpty ||
            // exclude generated code.
            filePath.endsWith('.g.dart')) {
          filesSkipped.add(filePath);
          continue;
        }
        filesAnalyzed.add(filePath);
        await _analyzeSingleFile(context, filePath);
      }
    }
    _logger.info('Found ${foundStringLiterals.length} literals:');
    for (final f in foundStringLiterals) {
      final relative = path.relative(f.filePath, from: basePath);
      _logger.info('$relative:${f.loc} ${f.stringLiteral}');
    }
    return foundStringLiterals;
  }

  Future<void> _analyzeSingleFile(
      AnalysisContext context, String filePath) async {
    _logger.fine('analyzing $filePath');
//    final result = context.currentSession.getParsedUnit(filePath);
    final result = await context.currentSession.getResolvedUnit2(filePath);
    if (result is! ResolvedUnitResult) {
      throw StateError('Did not resolve to valid unit.');
    }
    final unit = result.unit!;
    final visitor = StringLiteralVisitor<dynamic>(
        filePath: filePath,
        unit: unit,
        foundStringLiteral: (foundStringLiteral) {
          foundStringLiterals.add(foundStringLiteral);
        });
    unit.visitChildren(visitor);
//    for (final unitMember in unit.declarations) {
//      _logger
//          .finest('${path.basename(filePath)} Found ${unitMember.runtimeType}');
//    }
  }
}

/// Information about a string literal found in dart code.
class FoundStringLiteral {
  FoundStringLiteral({
    required this.filePath,
    required this.loc,
    required this.locEnd,
    required this.stringValue,
    required this.stringLiteral,
  });

  /// absolute file path to the file in which the string literal was found.
  final String filePath;

  /// line/column of the beginning of the string literal.
  final CharacterLocation loc;

  /// line/column of the end of the string literal.
  final CharacterLocation locEnd;

  /// The actual value of the string, better to use [stringLiteral].
  final String? stringValue;

  /// The string literal from the analyser.
  final StringLiteral stringLiteral;

  int get charOffset => stringLiteral.beginToken.charOffset;
  int get charEnd => stringLiteral.endToken.charEnd;
  int get charLength => charEnd - charOffset;
}

class StringLiteralVisitor<R> extends GeneralizingAstVisitor<R> {
  StringLiteralVisitor({
    required this.filePath,
    required this.unit,
    required this.foundStringLiteral,
  }) : lineInfo = unit.lineInfo;

  static const loggerChecker = TypeChecker.fromRuntime(Logger);
  static const nonNlsChecker = TypeChecker.fromRuntime(NonNlsArg);
  static const exceptionChecker = TypeChecker.fromRuntime(Exception);
  static const errorChecker = TypeChecker.fromRuntime(Error);
  static const ignoredConstructorCalls = [
    TypeChecker.fromRuntime(Uri),
    TypeChecker.fromRuntime(RegExp),
    TypeChecker.fromUrl(
        'package:flutter/src/painting/image_resolution.dart#AssetImage'),
    TypeChecker.fromUrl(
        'package:flutter/src/widgets/navigator.dart#RouteSettings'),
    TypeChecker.fromUrl('package:flutter/src/foundation/key.dart#ValueKey'),
    TypeChecker.fromUrl(
        'package:flutter/src/services/platform_channel.dart#MethodChannel'),
    TypeChecker.fromRuntime(StateError),
    loggerChecker,
    exceptionChecker,
    errorChecker,
  ];

  final String filePath;
  final CompilationUnit unit;
  final LineInfo? lineInfo;
  final void Function(FoundStringLiteral foundStringLiteral) foundStringLiteral;

  @override
  R? visitStringLiteral(StringLiteral node) {
//    final previous = node.findPrevious(node.beginToken);
    final parent = node.parent;
    final pp = node.parent?.parent;

    if (_shouldIgnore(node)) {
      return null;
    }

    final lineInfo = unit.lineInfo!;
    final begin = node.beginToken.charOffset;
    final end = node.endToken.charEnd;
    final loc = lineInfo.getLocation(begin) as CharacterLocation;
    final locEnd = lineInfo.getLocation(end) as CharacterLocation;

    final next = node.endToken.next;
    final nextNext = next?.next;
    _logger.finest(
        '''Found string literal (${loc.lineNumber}:${loc.columnNumber}) $node
         - parent: $parent (${parent.runtimeType})
         - parentParent: $pp (${pp.runtimeType} / ${pp!.parent?.runtimeType})
         - next: $next
         - nextNext: $nextNext 
         - precedingComments: ${node.beginToken.precedingComments}''');
    foundStringLiteral(FoundStringLiteral(
      filePath: filePath,
      loc: loc,
      locEnd: locEnd,
      stringValue: node.stringValue,
      stringLiteral: node,
    ));
    return super.visitStringLiteral(node);
  }

  bool _checkArgumentAnnotation(ArgumentList argumentList,
      ExecutableElement? executableElement, Expression nodeChildChild) {
    final argPos = argumentList.arguments.indexOf(nodeChildChild);
    assert(argPos != -1);
    final arg = argumentList.arguments[argPos];
    ParameterElement param;
    if (arg is NamedExpression) {
      param = executableElement!.parameters.firstWhere(
          (element) => element.isNamed && element.name == arg.name.label.name,
          orElse: () => throw StateError(
              'Unable to find parameter of name ${arg.name.label} for '
              '$executableElement'));
    } else {
      param = executableElement!.parameters[argPos];
      assert(param.isPositional);
    }
    if (nonNlsChecker.hasAnnotationOf(param)) {
//      _logger.finest('XX Argument is annotated with NonNls.');
      return true;
    }
    return false;
  }

  bool _shouldIgnore(AstNode origNode) {
    AstNode? node = origNode;
    AstNode? nodeChild;
    AstNode? nodeChildChild;
    for (;
        node != null;
        nodeChildChild = nodeChild, nodeChild = node, node = node.parent) {
      try {
        if (node is ImportDirective ||
            node is PartDirective ||
            node is PartOfDirective) {
          return true;
        }
        if (node is Annotation) {
          _logger.finest('Ignoring annotation parameters $node');
          return true;
        }
        if (node is IndexExpression) {
          final target = node.realTarget;
          if (target is SimpleIdentifier) {
            try {
              if (nonNlsChecker.hasAnnotationOf(target.staticElement!)) {
                return true;
              }
            } catch (e, stackTrace) {
              _logger.warning(
                  'Unable to check annotation for $origNode at $filePath',
                  e,
                  stackTrace);
            }
          }
        }
        if (node is InstanceCreationExpression) {
          assert(nodeChild == node.argumentList);
          if (_checkArgumentAnnotation(
              node.argumentList,
              node.constructorName.staticElement,
              nodeChildChild as Expression)) {
            return true;
          }
//        param.no
//          node.constructorName.staticElement;
          for (final ignoredConstructorCall in ignoredConstructorCalls) {
            if (ignoredConstructorCall
                .isAssignableFrom(node.staticType!.element!)) {
              return true;
            }
          }
        }
        if (node is MethodInvocation) {
          if (nodeChildChild is! Expression) {
            _logger.warning('not an expression. $nodeChildChild ($node)');
            // } else if (nodeChildChild != origNode) {
            //   we only care about direct method calls.
          } else if (
              // check if `nodeChildChild` is actually a full argument.
              // this can happen with sub expressions like
              // myFunc('string'.split('').join('')); where
              // `string'.split('')` will not be found in the parent expression.
              node.argumentList.arguments.contains(nodeChildChild) &&
                  // check if the argument is annotated
                  _checkArgumentAnnotation(
                      node.argumentList,
                      node.methodName.staticElement as ExecutableElement?,
                      nodeChildChild)) {
            return true;
          }
          final target = node.target;
          if (target != null) {
            // ignore all calls to `Logger`
            if (target.staticType == null) {
              _logger.warning('Unable to resolve type for $target');
            } else if (loggerChecker.isAssignableFromType(target.staticType!)) {
              return true;
            }
          }
        }
        if (node is FunctionDeclaration || node is MethodDeclaration) {
          if (node is Declaration) {
            if (nonNlsChecker.hasAnnotationOf(node.declaredElement!)) {
              return true;
            }
          }
        }
      } catch (e, stackTrace) {
        final loc = lineInfo!.getLocation(origNode.offset);
        _logger.severe('Error while analysing node $origNode at $filePath $loc',
            e, stackTrace);
      }
    }
    // see if we can find a line end comment.
    final lineNumber = lineInfo!.getLocation(origNode.end).lineNumber;
    var nextToken = origNode.endToken.next;
    while (nextToken != null &&
        lineInfo!.getLocation(nextToken.offset).lineNumber == lineNumber) {
      nextToken = nextToken.next;
    }
    final comment = nextToken!.precedingComments;
    if (comment != null &&
        lineInfo!.getLocation(comment.offset).lineNumber == lineNumber) {
      if (comment.value().contains('NON-NLS')) {
        return true;
      }
    }
    return false;
  }
}
