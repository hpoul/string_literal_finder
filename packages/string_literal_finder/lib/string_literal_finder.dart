import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:source_gen/source_gen.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
import 'package:path/path.dart' as path;

final _logger = Logger('string_literal_finder');

class StringLiteralFinder {
  StringLiteralFinder({
    this.basePath,
    this.excludePaths,
  });

  final String basePath;
  final List<String> excludePaths;

  final List<FoundStringLiteral> foundStringLiterals = [];
  final Set<String> filesSkipped = <String>{};
  final Set<String> filesAnalyzed = <String>{};

  Future<List<FoundStringLiteral>> start() async {
    _logger.fine('Starting analysis.');
    final collection = AnalysisContextCollection(includedPaths: [basePath]);
    _logger.finer('Finding contexts.');
    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        final relative = path.relative(filePath, from: basePath);
        if (excludePaths
                .where((element) => relative.startsWith(element))
                .isNotEmpty ||
            // exclude generated code.
            filePath.endsWith('.g.dart')) {
          filesSkipped.add(filePath);
          continue;
        }
        filesAnalyzed.add(filePath);
        await analyzeSingleFile(context, filePath);
      }
    }
    _logger.info('Found ${foundStringLiterals.length} literals:');
    for (final f in foundStringLiterals) {
      final relative = path.relative(f.filePath, from: basePath);
      _logger.info('$relative:${f.loc} ${f.stringLiteral}');
    }
    return foundStringLiterals;
  }

  Future<void> analyzeSingleFile(
      AnalysisContext context, String filePath) async {
    _logger.fine('analyzing $filePath');
//    final result = context.currentSession.getParsedUnit(filePath);
    final result = await context.currentSession.getResolvedUnit(filePath);
    final unit = result.unit;
    final visitor = StringLiteralVisitor<dynamic>(
        unit: unit,
        foundStringLiteral: (loc, stringLiteral) {
          foundStringLiterals.add(FoundStringLiteral(
            filePath: filePath,
            loc: loc,
            stringValue: stringLiteral.stringValue,
            stringLiteral: stringLiteral,
          ));
        });
    unit.visitChildren(visitor);
//    for (final unitMember in unit.declarations) {
//      _logger
//          .finest('${path.basename(filePath)} Found ${unitMember.runtimeType}');
//    }
  }
}

class FoundStringLiteral {
  FoundStringLiteral({
    @required this.filePath,
    @required this.loc,
    @required this.stringValue,
    @required this.stringLiteral,
  });
  final String filePath;
  final CharacterLocation loc;
  final String stringValue;
  final StringLiteral stringLiteral;
}

class StringLiteralVisitor<R> extends GeneralizingAstVisitor<R> {
  StringLiteralVisitor({this.unit, this.foundStringLiteral})
      : lineInfo = unit.lineInfo;

  static const loggerChecker = TypeChecker.fromRuntime(Logger);
  static const nonNlsChecker = TypeChecker.fromRuntime(NonNlsArg);

  final CompilationUnit unit;
  final LineInfo lineInfo;
  final void Function(CharacterLocation loc, StringLiteral stringLiteral)
      foundStringLiteral;

  @override
  R visitStringLiteral(StringLiteral node) {
//    final previous = node.findPrevious(node.beginToken);
    final parent = node.parent;
    final pp = node.parent?.parent;

    if (_shouldIgnore(node)) {
      return null;
    }

    final lineInfo = unit.lineInfo;
    final loc =
        lineInfo.getLocation(node.beginToken.charOffset) as CharacterLocation;

    final next = node.endToken.next;
    final nextNext = next?.next;
    _logger.finest(
        '''Found string literal (${loc.lineNumber}:${loc.columnNumber}) $node
         - parent: $parent (${parent.runtimeType})
         - parentParent: $pp (${pp.runtimeType} / ${pp.parent?.runtimeType})
         - next: $next
         - nextNext: $nextNext 
         - precedingComments: ${node.beginToken.precedingComments}''');
    foundStringLiteral(loc, node);
    return super.visitStringLiteral(node);
  }

  bool _checkArgumentAnnotation(ArgumentList argumentList,
      ExecutableElement executableElement, Expression nodeChildChild) {
    final argPos = argumentList.arguments.indexOf(nodeChildChild);
    assert(argPos != -1);
    final param = executableElement.parameters[argPos];
    if (nonNlsChecker.hasAnnotationOf(param)) {
//      _logger.finest('XX Argument is annotated with NonNls.');
      return true;
    }
    return false;
  }

  bool _shouldIgnore(AstNode origNode) {
    var node = origNode;
    AstNode nodeChild;
    AstNode nodeChildChild;
    for (;
        node != null;
        nodeChildChild = nodeChild, nodeChild = node, node = node.parent) {
      try {
        if (node is ImportDirective) {
          return true;
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
          const ignoredConstructors = ['RouteSettings', 'Logger'];
          if (ignoredConstructors
              .contains(node.constructorName.type.name.name)) {
            return true;
          }
        }
        if (node is MethodInvocation) {
          if (nodeChildChild is! Expression) {
            _logger.warning('not an expression. $nodeChildChild ($node)');
          } else if (_checkArgumentAnnotation(
              node.argumentList,
              node.methodName.staticElement as ExecutableElement,
              nodeChildChild as Expression)) {
            return true;
          }
          final target = node.target;
          if (target != null) {
            // ignore all calls to `Logger`
            if (target.staticType == null) {
              _logger.warning('Unable to resolve type for $target');
            } else if (loggerChecker.isAssignableFromType(target.staticType)) {
              return true;
            }
          }
        }
      } catch (e, stackTrace) {
        final loc = lineInfo.getLocation(origNode.offset);
        _logger.severe(
            'Error while analysing node $origNode at $loc', e, stackTrace);
      }
    }
    // see if we can find a line end comment.
    final lineNumber = lineInfo.getLocation(origNode.end).lineNumber;
    var nextToken = origNode.endToken.next;
    while (nextToken != null &&
        lineInfo.getLocation(nextToken.offset).lineNumber == lineNumber) {
      nextToken = nextToken.next;
    }
    final comment = nextToken.precedingComments;
    if (comment != null &&
        lineInfo.getLocation(comment.offset).lineNumber == lineNumber) {
      if (comment.value().contains('NON-NLS')) {
        return true;
      }
    }
    return false;
  }
}
