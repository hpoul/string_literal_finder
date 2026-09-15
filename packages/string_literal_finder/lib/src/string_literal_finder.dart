// `byteStore` is only reachable through the implementation class; the public
// `AnalysisContextCollection` factory exposes neither it nor `sdkPath`.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/file_byte_store.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:source_gen/source_gen.dart';
import 'package:string_literal_finder/src/analysis_options.dart';
import 'package:string_literal_finder/src/sdk.dart';
import 'package:string_literal_finder/src/utils.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

final _logger = Logger('string_literal_finder');

/// Upper bound for the on-disk analyzer cache. A full Flutter application's
/// linked summaries come to roughly 70 MB.
const _cacheSizeBytes = 512 * 1024 * 1024;

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
  const _ExcludePathCheckerImpl({
    required this.predicate,
    required this.description,
  });
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
    this.analysisOptions,
    this.cachePath,
    this.sdkPath,
  });

  /// Base path of the library.
  final String basePath;

  /// Paths which should be ignored. Usually something like `l10n/' to ignore
  /// the actual translation files.
  final List<ExcludePathChecker> excludePaths;

  /// `exclude_globs` from `analysis_options.yaml`, honoured so that the same
  /// configuration silences a file in the IDE and on the command line.
  final AnalysisOptions? analysisOptions;

  /// Directory for the analyzer's linked summary cache. Reusing it across runs
  /// roughly halves the wall clock time; see `--cache-dir`.
  final String? cachePath;

  /// Root of the Dart SDK to analyse against.
  ///
  /// Null means "work it out", which is right whenever the tool runs on the
  /// Dart VM. It has to be given for a binary produced by `dart compile exe`,
  /// because the analyzer derives the SDK from `Platform.resolvedExecutable`
  /// and that is the binary itself; see [resolveSdkPath].
  final String? sdkPath;

  final List<FoundStringLiteral> foundStringLiterals = [];
  final Set<String> filesSkipped = <String>{};
  final Set<String> filesAnalyzed = <String>{};

  /// Number of files which the syntactic pre-pass proved could not contain a
  /// finding, and which were therefore never resolved.
  int filesSkippedBySyntacticPrePass = 0;

  /// Starts the analyser and returns information about the found
  /// string literals.
  Future<List<FoundStringLiteral>> start() async {
    _logger.fine('Starting analysis.');
    final byteStore = cachePath?.let((cachePath) {
      Directory(cachePath).createSync(recursive: true);
      return EvictingFileByteStore(cachePath, _cacheSizeBytes);
    });
    // `byteStore` and `sdkPath` are only exposed on the implementation class;
    // the public `AnalysisContextCollection` factory does not forward them.
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [basePath],
      byteStore: byteStore,
      sdkPath: resolveSdkPath(sdkPath),
    );
    try {
      _logger.finer('Finding contexts.');
      for (final context in collection.contexts) {
        for (final filePath in context.contextRoot.analyzedFiles()) {
          if (_isExcluded(filePath)) {
            filesSkipped.add(filePath);
            continue;
          }
          filesAnalyzed.add(filePath);
          await _analyzeSingleFile(context, filePath);
        }
      }
    } finally {
      await collection.dispose();
    }
    // Reporting the findings is the caller's job -- the library only says how
    // many there were.
    _logger.fine(() => 'Found ${foundStringLiterals.length} literals.');
    return foundStringLiterals;
  }

  bool _isExcluded(String filePath) {
    // Generated code is never worth reporting.
    if (filePath.endsWith('.g.dart')) {
      return true;
    }
    final relative = path.relative(filePath, from: basePath);
    if (excludePaths.any((checker) => checker.shouldExclude(relative))) {
      return true;
    }
    return analysisOptions?.isExcluded(filePath) ?? false;
  }

  Future<void> _analyzeSingleFile(
    AnalysisContext context,
    String filePath,
  ) async {
    _logger.fine('analyzing $filePath');
    final session = context.currentSession;
    // Resolving a file costs roughly a hundred times as much as parsing it, so
    // parse first and skip resolution entirely for files which cannot produce a
    // finding. Resolution only ever *suppresses* literals (it is what makes the
    // `Logger`, `@NonNls` and ignored-constructor rules work), so a file with
    // no syntactic candidate has no findings either way.
    final parsed = session.getParsedUnit(filePath);
    if (parsed is! ParsedUnitResult) {
      _logger.warning('Unable to parse $filePath: $parsed');
      return;
    }
    if (!_MayContainLiteralVisitor.check(parsed.unit)) {
      filesSkippedBySyntacticPrePass++;
      return;
    }
    final result = await session.getResolvedUnit(filePath);
    if (result is! ResolvedUnitResult) {
      _logger.warning('Unable to resolve $filePath: $result');
      return;
    }
    final unit = result.unit;
    final visitor = StringLiteralVisitor<dynamic>(
      filePath: filePath,
      unit: unit,
      foundStringLiteral: foundStringLiterals.add,
    );
    unit.visitChildren(visitor);
  }
}

/// Cheap syntactic check for whether a compilation unit contains any string
/// literal that could possibly be reported.
///
/// Deliberately conservative: it must never answer `false` for a unit that the
/// full [StringLiteralVisitor] would report something in. It therefore only
/// applies the ignore rules that need no element resolution.
class _MayContainLiteralVisitor extends RecursiveAstVisitor<void> {
  _MayContainLiteralVisitor._();

  static bool check(CompilationUnit unit) {
    final visitor = _MayContainLiteralVisitor._();
    unit.visitChildren(visitor);
    return visitor._found;
  }

  bool _found = false;

  @override
  void visitAnnotation(Annotation node) {
    // Literals in annotations are always ignored.
  }

  @override
  void visitImportDirective(ImportDirective node) {}

  @override
  void visitExportDirective(ExportDirective node) {}

  @override
  void visitPartDirective(PartDirective node) {}

  @override
  void visitPartOfDirective(PartOfDirective node) {}

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _found = true;

  @override
  void visitStringInterpolation(StringInterpolation node) => _found = true;

  @override
  void visitAdjacentStrings(AdjacentStrings node) => _found = true;
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

  /// The literal exactly as written, e.g. `'$count items'`.
  ///
  /// Unlike [loc] this is stable across reformatting and unrelated edits, so it
  /// is what baselines are keyed on.
  String get sourceText => stringLiteral.toSource();

  /// The text a reader would see, with interpolated expressions removed.
  ///
  /// For `'$distance km'` this is ` km`. [stringValue] is null for anything
  /// containing interpolation, which makes it useless for judging whether a
  /// literal looks like prose.
  late final String textValue = _textValue(stringLiteral);

  static String _textValue(StringLiteral literal) {
    switch (literal) {
      case SimpleStringLiteral():
        return literal.value;
      case AdjacentStrings():
        return literal.strings.map(_textValue).join();
      case StringInterpolation():
        return literal.elements
            .whereType<InterpolationString>()
            .map((e) => e.value)
            .join();
    }
  }

  /// Whether anything is interpolated into this literal.
  ///
  /// This matters for filtering: `'/'` is a separator and can be discarded,
  /// but `'$a - $b'` has the same letterless [textValue] and is a template
  /// whose separator may well differ by locale.
  late final bool isInterpolated = _isInterpolated(stringLiteral);

  static bool _isInterpolated(StringLiteral literal) => switch (literal) {
    SimpleStringLiteral() => false,
    StringInterpolation() => true,
    AdjacentStrings() => literal.strings.any(_isInterpolated),
  };
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
           filePath: filePath,
           unit: unit,
           lineInfo: unit.lineInfo,
         ),
         foundStringLiteral: foundStringLiteral,
       );

  StringLiteralVisitor.context({
    required this.context,
    required this.foundStringLiteral,
    this.descendIntoInterpolations = true,
  });

  /// Whether to visit the expressions interpolated into a reported literal.
  ///
  /// True when driving the traversal directly, as the command line does: this
  /// visitor stops at a reported literal, so `'${f('inner')}'` would otherwise
  /// never reach `'inner'`.
  ///
  /// False under the analysis rule framework, which walks the whole unit itself
  /// and dispatches every registered node type independently. Descending again
  /// there would report every nested literal twice.
  final bool descendIntoInterpolations;

  static const loggerChecker = TypeChecker.typeNamed(Logger);
  static const nonNlsChecker = TypeChecker.typeNamed(NonNlsArg);
  static const exceptionChecker = TypeChecker.typeNamed(Exception);
  static const errorChecker = TypeChecker.typeNamed(Error);
  static const ignoredConstructorCalls = [
    TypeChecker.typeNamed(Uri),
    TypeChecker.typeNamed(RegExp),
    // Named by type + package, not by URI. `TypeChecker.fromUrl` matches on
    // the *declaring* library, so it needs Flutter's private implementation
    // paths -- and those move: `AssetImage` has already been relocated once,
    // and there are ~120 renames under `packages/flutter/lib/src/` in
    // Flutter's history. Each move would have silently stopped the exemption
    // matching, surfacing as a wave of unexplained new findings.
    TypeChecker.typeNamedLiterally('AssetImage', inPackage: 'flutter'),
    TypeChecker.typeNamedLiterally('RouteSettings', inPackage: 'flutter'),
    TypeChecker.typeNamedLiterally('ValueKey', inPackage: 'flutter'),
    TypeChecker.typeNamedLiterally('MethodChannel', inPackage: 'flutter'),
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
    StringLiteral node,
  ) sync* {
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
    _logger.finest(
      () =>
          'Found string literal (${loc.lineNumber}:${loc.columnNumber}) $node '
          '- parent: ${node.parent.runtimeType}',
    );
    foundStringLiteral(
      FoundStringLiteral(
        filePath: context().filePath,
        loc: loc,
        locEnd: locEnd,
        stringValue: node.stringValue,
        stringLiteral: node,
      ),
    );
    // Descend only into interpolated expressions. Visiting all children would
    // re-report the operands of an `AdjacentStrings` as literals of their own.
    if (descendIntoInterpolations) {
      for (final expression in _interpolatedExpressions(node)) {
        expression.accept(this);
      }
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
    if (!argumentList.arguments.contains(argument)) {
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
      // Since Dart 2.17 a named argument may appear *before* a positional one
      // at the call site, so the argument's index in the list is not its
      // parameter index. Count only the positional arguments ahead of it.
      var positionalIndex = 0;
      for (final other in argumentList.arguments) {
        if (identical(other, argument)) {
          break;
        }
        if (other is! NamedArgument) {
          positionalIndex++;
        }
      }
      final positionals = formalParameters
          .where((e) => e.isPositional)
          .toList();
      param = positionalIndex < positionals.length
          ? positionals[positionalIndex]
          : null;
    }
    if (param == null) {
      return false;
    }
    return _hasNonNls(param);
  }

  /// Whether [element] carries `@NonNls` / `@NonNlsArg()`.
  ///
  /// `throwOnUnresolved: false` is the whole point. source_gen walks an
  /// element's annotations in order and, by default, throws at the *first* one
  /// whose constant is null — before it has looked at any later annotation. So
  /// an unresolved annotation sitting above `@NonNls`:
  ///
  /// ```dart
  /// @SomeGeneratedThing @NonNls
  /// void logKeys() { ... }
  /// ```
  ///
  /// meant the `@NonNls` was never reached and every literal below it was
  /// reported. Order-dependent, too: swapping the two annotations suppressed
  /// correctly. Asking for `null` instead of a throw lets the walk continue.
  static bool _hasNonNls(Element element) =>
      nonNlsChecker.hasAnnotationOf(element, throwOnUnresolved: false);

  bool _shouldIgnore(AstNode origNode) {
    late final lineInfo = context().lineInfo;
    AstNode? node = origNode;
    AstNode? nodeChild;
    AstNode? nodeChildChild;
    for (
      ;
      node != null;
      nodeChildChild = nodeChild, nodeChild = node, node = node.parent
    ) {
      try {
        if (node is UriBasedDirective || node is PartOfDirective) {
          return true;
        }
        if (node is Annotation) {
          _logger.finest('Ignoring annotation parameters $node');
          return true;
        }
        if (node is ClassDeclaration) {
          if (_hasNonNls(node.declaredFragment!.element)) {
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
            // The target does not always resolve, and force-unwrapping it
            // logged a warning with a stack trace per literal. An unresolved
            // target is simply not one that carries `@NonNls`.
            final element = target.element;
            if (element != null && _hasNonNls(element)) {
              return true;
            }
            // A top-level variable or field is read through its synthetic
            // getter, whose metadata is empty: the annotation sits on the
            // variable. Only a local variable resolves to itself.
            if (element is PropertyAccessorElement &&
                _hasNonNls(element.variable)) {
              return true;
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
              _checkArgumentAnnotation(
                node.argumentList,
                node.constructorName.element,
                nodeChildChild,
              )) {
            return true;
          }
          // The type does not always resolve -- a project whose generated
          // files are missing has plenty that do not. Force-unwrapping threw
          // once per such literal, which aborted the remaining checks for this
          // ancestor and logged a stack trace: 191 of them on one real Flutter
          // app. An unresolvable type simply is not one of the ignored ones.
          final createdType = node.staticType?.element;
          if (createdType != null) {
            for (final ignoredConstructorCall in ignoredConstructorCalls) {
              if (ignoredConstructorCall.isAssignableFrom(createdType)) {
                return true;
              }
            }
          }
        }
        if (node is VariableDeclaration) {
          final element = node.declaredFragment?.element;
          if (element != null && _hasNonNls(element)) {
            return true;
          }
        }
        if (node is FormalParameter) {
          final element = node.declaredFragment?.element;
          if (element != null && _hasNonNls(element)) {
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
                nodeChildChild,
              )) {
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
            if (_hasNonNls(node.declaredFragment!.element)) {
              return true;
            }
          }
        }
      } catch (e, stackTrace) {
        final loc = lineInfo!.getLocation(origNode.offset);
        _logger.severe(
          'Error while analysing node $origNode at ${context().filePath} $loc',
          e,
          stackTrace,
        );
      }
    }
    // See if we can find a line end comment. Comments are attached to the
    // token that follows them, so this walks to the first token on a later
    // line and looks at what precedes it.
    final lineNumber = lineInfo!.getLocation(origNode.end).lineNumber;
    var nextToken = origNode.endToken.next;
    while (nextToken != null &&
        // The EOF token's `next` is the EOF token itself, so a literal on the
        // last line of a file with no trailing newline would loop forever.
        nextToken.type != TokenType.EOF &&
        lineInfo.getLocation(nextToken.offset).lineNumber == lineNumber) {
      nextToken = nextToken.next;
    }
    // Every comment on the line, not just the first: `/* a */ // NON-NLS`
    // attaches both to the same token, and only the second one carries the
    // marker.
    for (
      Token? comment = nextToken?.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      if (lineInfo.getLocation(comment.offset).lineNumber == lineNumber &&
          comment.lexeme.contains('NON-NLS')) {
        return true;
      }
    }
    return false;
  }
}
