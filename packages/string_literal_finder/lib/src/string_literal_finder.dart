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
    final result = await context.currentSession.getResolvedUnit(filePath);
    if (result is! ResolvedUnitResult) {
      throw StateError('Did not resolve to valid unit.');
    }
    final unit = result.unit;
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

class StringLiteralContext {
  StringLiteralContext({
    required this.filePath,
    required this.unit,
    required this.lineInfo,
  });

  final String filePath;
  final CompilationUnit? unit;
  final LineInfo? lineInfo;
}

class StringLiteralVisitor<R> extends GeneralizingAstVisitor<R> {
  StringLiteralVisitor({
    required String filePath,
    required CompilationUnit unit,
    required void Function(FoundStringLiteral foundStringLiteral)
        foundStringLiteral,
  }) : this.context(
            context: () => StringLiteralContext(
                filePath: filePath, unit: unit, lineInfo: unit.lineInfo),
            foundStringLiteral: foundStringLiteral);

  StringLiteralVisitor.context({
    required this.context,
    required this.foundStringLiteral,
  });

  static const loggerChecker = TypeChecker.typeNamed(Logger);
  static const nonNlsChecker = TypeChecker.typeNamed(NonNlsArg);
  static const exceptionChecker = TypeChecker.typeNamed(Exception);
  static const errorChecker = TypeChecker.typeNamed(Error);
  static const ignoredConstructorCalls = [
    TypeChecker.typeNamed(Uri),
    TypeChecker.typeNamed(RegExp),
    TypeChecker.fromUrl(
        'package:flutter/src/painting/image_resolution.dart#AssetImage'),
    TypeChecker.fromUrl(
        'package:flutter/src/widgets/navigator.dart#RouteSettings'),
    TypeChecker.fromUrl('package:flutter/src/foundation/key.dart#ValueKey'),
    TypeChecker.fromUrl(
        'package:flutter/src/services/platform_channel.dart#MethodChannel'),
    TypeChecker.typeNamed(StateError),
    loggerChecker,
    exceptionChecker,
    errorChecker,
  ];

  final StringLiteralContext Function() context;
  final void Function(FoundStringLiteral foundStringLiteral) foundStringLiteral;

  /// Whether [node] is merely an operand of an enclosing [AdjacentStrings],
  /// i.e. part of a larger literal which is reported as a whole.
  ///
  /// `'foo' 'bar'` is one string as far as the author is concerned, so it must
  /// produce one finding, not three.
  static bool _isPartOfEnclosingLiteral(StringLiteral node) =>
      node.parent is AdjacentStrings;

  /// The expressions interpolated into [node], which are the only children of
  /// a string literal that can contain further string literals.
  static Iterable<Expression> _interpolatedExpressions(
      StringLiteral node) sync* {
    switch (node) {
      case AdjacentStrings():
        for (final part in node.strings) {
          yield* _interpolatedExpressions(part);
        }
      case StringInterpolation():
        for (final element in node.elements) {
          if (element is InterpolationExpression) {
            yield element.expression;
          }
        }
      case SimpleStringLiteral():
        break;
    }
  }

  @override
  R? visitStringLiteral(StringLiteral node) {
    if (_isPartOfEnclosingLiteral(node) || _shouldIgnore(node)) {
      return null;
    }

    final lineInfo = context().lineInfo;
    if (lineInfo == null) {
      return null;
    }
    final begin = node.beginToken.charOffset;
    final end = node.endToken.charEnd;
    final loc = lineInfo.getLocation(begin);
    final locEnd = lineInfo.getLocation(end);

    // Note: the message is built lazily. Interpolating it eagerly cost a
    // measurable amount of time on large code bases, since it ran for every
    // literal regardless of the configured log level.
    _logger.finest(() =>
        'Found string literal (${loc.lineNumber}:${loc.columnNumber}) $node '
        '- parent: ${node.parent.runtimeType}');
    foundStringLiteral(FoundStringLiteral(
      filePath: context().filePath,
      loc: loc,
      locEnd: locEnd,
      stringValue: node.stringValue,
      stringLiteral: node,
    ));
    // Descend only into interpolated expressions. Visiting all children would
    // re-report the operands of an `AdjacentStrings` as literals of their own.
    for (final expression in _interpolatedExpressions(node)) {
      expression.accept(this);
    }
    return null;
  }

  /// Checks whether the formal parameter which [argument] is bound to is
  /// annotated with [NonNlsArg].
  ///
  /// [argument] must be a direct child of [argumentList]. Since analyzer 13
  /// named arguments are represented by [NamedArgument] (which is *not* an
  /// [Expression]) rather than the former `NamedExpression`, so the argument
  /// is typed as [Argument] here.
  bool _checkArgumentAnnotation(
    ArgumentList argumentList,
    ExecutableElement? executableElement,
    Argument argument,
  ) {
    if (executableElement == null) {
      return false;
    }
    final argPos = argumentList.arguments.indexOf(argument);
    if (argPos == -1) {
      return false;
    }
    final formalParameters = executableElement.formalParameters;
    final FormalParameterElement? param;
    if (argument is NamedArgument) {
      final name = argument.name.lexeme;
      param = formalParameters
          .where((element) => element.isNamed && element.name == name)
          .firstOrNull;
    } else {
      // Positional arguments are always listed before named ones, so the
      // argument index doubles as the parameter index.
      param =
          argPos < formalParameters.length ? formalParameters[argPos] : null;
    }
    if (param == null) {
      return false;
    }
    return nonNlsChecker.hasAnnotationOf(param);
  }

  bool _shouldIgnore(AstNode origNode) {
    late final lineInfo = context().lineInfo;
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
        if (node is ClassDeclaration) {
          if (nonNlsChecker.hasAnnotationOf(node.declaredFragment!.element)) {
            if (nodeChild is FieldDeclaration) {
              if (nodeChild.isStatic) {
                return true;
              }
            }
            // since analyzer 10 There is another hierarchy
            if (nodeChildChild is FieldDeclaration) {
              if (nodeChildChild.isStatic) {
                return true;
              }
            }
          }
        }
        if (node is IndexExpression) {
          final target = node.realTarget;
          if (target is SimpleIdentifier) {
            try {
              if (nonNlsChecker.hasAnnotationOf(target.element!)) {
                return true;
              }
            } catch (e, stackTrace) {
              _logger.warning(
                  'Unable to check annotation for $origNode at ${context().filePath}',
                  e,
                  stackTrace);
            }
          }
        }
        if (node is EnumConstantArguments) {
          final constantDeclaration = node.parent as EnumConstantDeclaration;
          final constructor = constantDeclaration.constructorElement;
          if (nodeChildChild is Argument &&
              _checkArgumentAnnotation(
                node.argumentList,
                constructor,
                nodeChildChild,
              )) {
            return true;
          }
        }
        if (node is InstanceCreationExpression) {
          if (nodeChildChild is Argument &&
              _checkArgumentAnnotation(node.argumentList,
                  node.constructorName.element, nodeChildChild)) {
            return true;
          }
          for (final ignoredConstructorCall in ignoredConstructorCalls) {
            if (ignoredConstructorCall
                .isAssignableFrom(node.staticType!.element!)) {
              return true;
            }
          }
        }
        if (node is VariableDeclaration) {
          final element = node.declaredFragment?.element;
          if (element != null && nonNlsChecker.hasAnnotationOf(element)) {
            return true;
          }
        }
        if (node is FormalParameter) {
          final element = node.declaredFragment?.element;
          if (element != null && nonNlsChecker.hasAnnotationOf(element)) {
            return true;
          }
        }
        if (node is MethodInvocation) {
          // Check that `nodeChildChild` is actually a full argument. It may not
          // be, for sub expressions such as
          // `myFunc('string'.split('').join(''))`, where `'string'.split('')`
          // is not itself an entry of the parent argument list.
          if (nodeChildChild is Argument &&
              node.argumentList.arguments.contains(nodeChildChild) &&
              // check if the argument is annotated
              _checkArgumentAnnotation(
                  node.argumentList,
                  node.methodName.element as ExecutableElement?,
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
            if (nonNlsChecker.hasAnnotationOf(node.declaredFragment!.element)) {
              return true;
            }
          }
        }
      } catch (e, stackTrace) {
        final loc = lineInfo!.getLocation(origNode.offset);
        _logger.severe(
            'Error while analysing node $origNode at ${context().filePath} $loc',
            e,
            stackTrace);
      }
    }
    // see if we can find a line end comment.
    final lineNumber = lineInfo!.getLocation(origNode.end).lineNumber;
    var nextToken = origNode.endToken.next;
    while (nextToken != null &&
        lineInfo.getLocation(nextToken.offset).lineNumber == lineNumber) {
      nextToken = nextToken.next;
    }
    final comment = nextToken!.precedingComments;
    if (comment != null &&
        lineInfo.getLocation(comment.offset).lineNumber == lineNumber) {
      if (comment.value().contains('NON-NLS')) {
        return true;
      }
    }
    return false;
  }
}
