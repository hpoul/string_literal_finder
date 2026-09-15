import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';

/// Builds a [FoundStringLiteral] for [source] (the literal *as written*, e.g.
/// `"'hello'"`) as though it had been found in [filePath] at [line].
///
/// The literal is parsed rather than hand-built, so that `sourceText` and
/// `textValue` behave exactly as they do in a real run. Parsing is syntactic
/// only, so this stays fast enough for table-driven tests.
FoundStringLiteral fakeLiteral(String filePath, String source, {int line = 1}) {
  final padding = '\n' * (line - 1);
  final unit = parseString(content: '${padding}final x = $source;').unit;
  final literal = _FirstStringLiteral.of(unit);
  final lineInfo = unit.lineInfo;
  return FoundStringLiteral(
    filePath: filePath,
    loc: lineInfo.getLocation(literal.offset),
    locEnd: lineInfo.getLocation(literal.end),
    stringValue: literal.stringValue,
    stringLiteral: literal,
  );
}

class _FirstStringLiteral extends GeneralizingAstVisitor<void> {
  StringLiteral? _found;

  static StringLiteral of(CompilationUnit unit) {
    final visitor = _FirstStringLiteral();
    unit.visitChildren(visitor);
    return visitor._found ?? (throw ArgumentError('No string literal found.'));
  }

  @override
  void visitStringLiteral(StringLiteral node) => _found ??= node;
}
