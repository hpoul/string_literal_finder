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
    final placement = _commentPlacement(literal, unitResult);
    if (placement == null) {
      return;
    }
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(placement.offset, placement.text);
    });
  }
}

/// Where and what to insert to suppress a literal, or null if no safe place
/// exists on its line.
typedef _CommentPlacement = ({int offset, String text});

/// Works out how to append `// NON-NLS` to the line [literal] ends on.
///
/// Everything here is decided from the token stream rather than from the line's
/// text. Reading the text tempts you into `line.contains('//')` to detect an
/// existing comment, which is wrong for `f('https://example.com')` — a URL is
/// the archetypal literal someone suppresses, and treating it as a comment
/// produces ` NON-NLS` with no `//`, which does not parse.
_CommentPlacement? _commentPlacement(
  StringLiteral literal,
  ResolvedUnitResult unitResult,
) {
  final lineInfo = unitResult.lineInfo;
  final line = lineInfo.getLocation(literal.end).lineNumber;
  bool onLine(int offset) => lineInfo.getLocation(offset).lineNumber == line;

  // Walk to the first token on a later line, collecting the comments attached
  // along the way. A comment is attached to the token that follows it.
  final comments = <Token>[];
  Token? token = literal.endToken.next;
  while (token != null && token.type != TokenType.EOF && onLine(token.offset)) {
    // A token that starts on this line but ends after it -- a multi-line
    // string, say -- means the end of the line is inside it, and appending
    // there would change that token's contents rather than comment the line.
    if (!onLine(token.end)) {
      return null;
    }
    _collectComments(token, comments, onLine);
    token = token.next;
  }
  if (token != null) {
    _collectComments(token, comments, onLine);
  }

  for (final comment in comments) {
    // A block comment opening on this line and closing on a later one has the
    // end of the line inside it, so appending would edit the author's prose.
    if (!onLine(comment.end)) {
      return null;
    }
  }

  final content = unitResult.content;
  final int endOfLine;
  if (line >= lineInfo.lineCount) {
    endOfLine = content.length;
  } else {
    var end = lineInfo.getOffsetOfLine(line) - 1;
    // Leave a `\r\n` intact.
    if (end > 0 && content.codeUnitAt(end - 1) == 0x0d) {
      end--;
    }
    endOfLine = end;
  }

  // Extending a trailing `//` comment is enough, because the finder looks for
  // NON-NLS anywhere in the comment's text. A block comment is not extended:
  // it may be followed by a line comment, and only the trailing one reliably
  // covers the rest of the line.
  final trailing = comments.lastOrNull;
  final extendsLineComment =
      trailing != null &&
      trailing.type == TokenType.SINGLE_LINE_COMMENT &&
      // A `///` comment documents whatever follows it, so appending the marker
      // would put it in the next declaration's rendered documentation.
      !trailing.lexeme.startsWith('///') &&
      trailing.end == endOfLine;
  return (
    offset: endOfLine,
    text: extendsLineComment ? ' NON-NLS' : ' // NON-NLS',
  );
}

void _collectComments(
  Token token,
  List<Token> into,
  bool Function(int offset) onLine,
) {
  for (
    Token? comment = token.precedingComments;
    comment != null;
    comment = comment.next
  ) {
    if (onLine(comment.offset)) {
      into.add(comment);
    }
  }
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
///
/// `nonNls()` is an ordinary function call, so wrapping a literal anywhere
/// constant is required turns compiling code into an error.
bool _isConstantContext(AstNode node) => switch (node) {
  Annotation() => true,
  ConstantPattern() => true,
  SwitchCase() => true,
  // Arguments of an enum constant are always const.
  EnumConstantArguments() => true,
  // A const generative constructor has no body, so anything reached through
  // one is an initializer or an assert message -- both constant.
  ConstructorDeclaration(:final constKeyword) => constKeyword != null,
  InstanceCreationExpression(:final isConst) => isConst,
  TypedLiteral(:final isConst) => isConst,
  VariableDeclarationList(:final isConst) => isConst,
  FieldDeclaration() => _isConstFieldDeclaration(node),
  FormalParameterDefaultClause() => true,
  _ => false,
};

/// Whether a field's initializer has to be constant.
///
/// Beyond an explicitly `const` field, a non-late instance field initialized
/// inline must be constant if its class declares a const constructor.
bool _isConstFieldDeclaration(FieldDeclaration node) {
  if (node.fields.isConst) {
    return true;
  }
  if (node.isStatic || node.fields.isLate) {
    return false;
  }
  // Since analyzer 12 members hang off a `ClassBody`/`EnumBody`, so the
  // field's parent is the body rather than the declaration.
  return switch (node.parent) {
    // Every enum constructor is const whether or not it says so, so an enum's
    // instance field initializer is always a constant context.
    BlockEnumBody() => true,
    BlockClassBody(:final members) => members.any(
      _isConstGenerativeConstructor,
    ),
    _ => false,
  };
}

/// Whether [member] is a const constructor that forces field initializers to
/// be constant.
///
/// A `const factory` does not: it redirects, and declares no fields of its own.
bool _isConstGenerativeConstructor(ClassMember member) =>
    member is ConstructorDeclaration &&
    member.constKeyword != null &&
    member.factoryKeyword == null;
