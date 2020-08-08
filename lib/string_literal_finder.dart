import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

final _logger = Logger('string_literal_finder');

class StringLiteralFinder {
  StringLiteralFinder(this.basePath);

  String basePath;
  final List<FoundStringLiteral> foundStringLiterals = [];

  Future<List<FoundStringLiteral>> start() async {
    _logger.fine('Starting analysis.');
    final collection = AnalysisContextCollection(includedPaths: [basePath]);
    _logger.finer('Finding contexts.');
    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        analyzeSingleFile(context, filePath);
      }
    }
    _logger.info('Found ${foundStringLiterals.length} literals:');
    for (final f in foundStringLiterals) {
      _logger.info('${f.filePath}:${f.loc} ${f.stringLiteral}');
    }
    return foundStringLiterals;
  }

  void analyzeSingleFile(AnalysisContext context, String filePath) {
    _logger.fine('analyzing $filePath');
    final result = context.currentSession.getParsedUnit(filePath);
    final unit = result.unit;
    final visitor = StringLiteralVisitor(
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
    final loc = lineInfo.getLocation(node.beginToken.charOffset);

    final next = node.endToken.next;
    final nextNext = next?.next;
    _logger.finest(
        '''Found string literal (${loc.lineNumber}:${loc.columnNumber}) ${node}
         - parent: $parent (${parent.runtimeType})
         - parentParent: $pp (${pp.runtimeType} / ${pp.parent?.runtimeType})
         - next: $next
         - nextNext: $nextNext 
         - precedingComments: ${node.beginToken.precedingComments}''');
    foundStringLiteral(loc, node);
    return super.visitStringLiteral(node);
  }

  bool _shouldIgnore(AstNode origNode) {
    var node = origNode;
    for (; node != null; node = node.parent) {
      if (node is ImportDirective) {
        return true;
      }
      if (node is InstanceCreationExpression) {
        if (node.constructorName.type.name.name == 'RouteSettings') {
          return true;
        }
      }
      if (node is MethodInvocation) {
        final target = node.target;
        if (target is SimpleIdentifier && target.name == '_logger') {
          return true;
        }
        if (node.methodName.name == 'Logger') {
          return true;
        }
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
