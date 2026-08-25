import 'package:analysis_server_plugin/edit/change_builder/change_builder.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// The library the `@NonNls` annotation and the `nonNls()` function live in.
final _annotationsUri = Uri.parse(
  'package:string_literal_finder_annotations/'
  'string_literal_finder_annotations.dart',
);

/// The literal the reported diagnostic is on, or null if the fix was somehow
/// invoked somewhere else.
StringLiteral? _reportedLiteral(AstNode node) {
  final literal = node.thisOrAncestorOfType<StringLiteral>();
  if (literal == null) {
    return null;
  }
  // The diagnostic is reported on the outermost literal, so a fix invoked on
  // an operand of an `AdjacentStrings` has to widen to the whole thing --
  // wrapping or commenting only one operand would not suppress anything.
  var outermost = literal;
  while (true) {
    final parent = outermost.parent;
    if (parent is! AdjacentStrings) {
      return outermost;
    }
    outermost = parent;
  }
}

/// Appends `// NON-NLS` to the line the literal ends on.
///
/// Always available: unlike [WrapWithNonNls] it needs no dependency on
/// `string_literal_finder_annotations`.
class AddNonNlsComment extends ResolvedCorrectionProducer {
  AddNonNlsComment({required super.context});

  static const _kind = FixKind(
    'string_literal_finder.add_non_nls_comment',
    DartFixKindPriority.ignore,
    "Add '// NON-NLS' comment",
  );

  /// Deliberately not `acrossSingleFile`. "Suppress every literal in this
  /// file" is a tempting triage action that blanket-hides real copy; the
  /// baseline file is the reviewable way to accept what a project already has.
  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final literal = _reportedLiteral(node);
    if (literal == null) {
      return;
    }
    final lineInfo = unitResult.lineInfo;
    final offset = _endOfLineAfter(literal, unitResult);
    if (offset == null) {
      return;
    }
    // A trailing comment already on the line is fine to extend: the finder
    // looks for `NON-NLS` anywhere in the comment text.
    final line = lineInfo.getLocation(literal.end).lineNumber;
    final lineStart = lineInfo.getOffsetOfLine(line - 1);
    final text = unitResult.content.substring(lineStart, offset);
    final suffix = text.contains('//') ? ' NON-NLS' : ' // NON-NLS';
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(offset, suffix);
    });
  }
}

/// The end of the line [literal] ends on, or null if a comment cannot safely be
/// appended there.
///
/// It cannot when a token starting on that line runs past the end of it, which
/// happens for a multi-line string: `final a = 'x'; final b = '''` would put
/// the comment *inside* `b`'s contents rather than after a statement.
int? _endOfLineAfter(StringLiteral literal, ResolvedUnitResult unitResult) {
  final lineInfo = unitResult.lineInfo;
  final line = lineInfo.getLocation(literal.end).lineNumber;
  for (
    Token? token = literal.endToken.next;
    token != null && token.type != TokenType.EOF;
    token = token.next
  ) {
    if (lineInfo.getLocation(token.offset).lineNumber != line) {
      break;
    }
    if (lineInfo.getLocation(token.end).lineNumber != line) {
      return null;
    }
  }
  final content = unitResult.content;
  final lineCount = lineInfo.lineCount;
  if (line >= lineCount) {
    return content.length;
  }
  var end = lineInfo.getOffsetOfLine(line) - 1;
  // Leave a `\r\n` intact.
  if (end > 0 && content.codeUnitAt(end - 1) == 0x0d) {
    end--;
  }
  return end;
}

/// Wraps the literal in `nonNls(...)`.
///
/// More precise than a line comment and it survives reformatting, but it needs
/// `string_literal_finder_annotations` to be resolvable — so the fix is only
/// offered when it is. Emitting code that does not compile would be worse than
/// offering nothing.
class WrapWithNonNls extends ResolvedCorrectionProducer {
  WrapWithNonNls({required super.context});

  static const _kind = FixKind(
    'string_literal_finder.wrap_with_non_nls',
    DartFixKindPriority.standard,
    'Wrap with nonNls()',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final literal = _reportedLiteral(node);
    if (literal == null) {
      return;
    }
    // `nonNls()` returns its argument, so wrapping is safe in an expression
    // position but not in a constant one: `const x = nonNls('a')` does not
    // compile, and neither does an annotation argument or a `case` pattern.
    if (literal.thisOrAncestorMatching(_isConstantContext) != null) {
      return;
    }
    final resolved = await sessionHelper.session.getLibraryByUri(
      '$_annotationsUri',
    );
    if (resolved is! LibraryElementResult) {
      return;
    }
    await builder.addDartFileEdit(file, (builder) {
      builder.addInsertion(literal.offset, (builder) {
        builder.writeImportedName([_annotationsUri], 'nonNls');
        builder.write('(');
      });
      builder.addSimpleInsertion(literal.end, ')');
    });
  }
}

/// Whether [node] is somewhere a non-constant call cannot appear.
bool _isConstantContext(AstNode node) => switch (node) {
  Annotation() => true,
  ConstantPattern() => true,
  SwitchCase() => true,
  InstanceCreationExpression(:final isConst) => isConst,
  TypedLiteral(:final isConst) => isConst,
  VariableDeclarationList(:final isConst) => isConst,
  FieldDeclaration(fields: VariableDeclarationList(:final isConst)) => isConst,
  FormalParameterDefaultClause() => true,
  _ => false,
};
