// The rule dispatch machinery is analyzer-internal; there is no public way to
// run an `AnalysisRule` outside the analysis server.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/analysis_rule/rule_context.dart';
import 'package:analyzer/src/lint/linter_visitor.dart';
import 'package:path/path.dart' as p;
import 'package:string_literal_finder/main.dart';

/// One diagnostic reported by the rule, flattened for readability in
/// expectations.
typedef ReportedLiteral = ({int line, int column, String message});

/// Runs [LiteralStringRule] the way the analysis server does, and returns every
/// diagnostic it reports.
///
/// This is the plugin half of the tool. It matters that it is exercised
/// separately from the command line: the two drive the same visitor in
/// different ways. The CLI walks the AST itself and stops descending at a
/// reported literal, while the rule framework walks the whole unit and
/// dispatches every registered node type independently — which is how nested
/// literals came to be reported twice.
Future<List<ReportedLiteral>> runRule(String source) async {
  final overlay = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final filePath = p.join(
    Directory.current.absolute.path,
    'test',
    '__rule_test__.dart',
  );
  overlay.setOverlay(
    filePath,
    content: source,
    modificationStamp: DateTime.now().microsecondsSinceEpoch,
  );
  final unitResult =
      await resolveFile(path: filePath, resourceProvider: overlay)
          as ResolvedUnitResult;

  final rule = LiteralStringRule();
  // `RecordingDiagnosticListener` stores diagnostics in a Set, which would
  // quietly collapse exactly the duplicates this harness exists to catch.
  final listener = _ListDiagnosticListener();
  final reporter = DiagnosticReporter(
    listener,
    unitResult.libraryElement.firstFragment.source,
  );
  rule.reporter = reporter;

  final contextUnit = RuleContextUnit(
    file: overlay.getFile(filePath),
    content: source,
    diagnosticReporter: reporter,
    unit: unitResult.unit,
  );
  final context = RuleContextWithResolvedResults(
    [contextUnit],
    contextUnit,
    unitResult.typeProvider,
    unitResult.typeSystem,
    null,
  )..currentUnit = contextUnit;

  final registry = RuleVisitorRegistryImpl(enableTiming: false);
  rule.registerNodeProcessors(registry, context);
  unitResult.unit.accept(
    AnalysisRuleVisitor(registry, shouldPropagateExceptions: true),
  );

  final lineInfo = unitResult.lineInfo;
  return [
    for (final diagnostic in listener.diagnostics)
      (
        line: lineInfo.getLocation(diagnostic.offset).lineNumber,
        column: lineInfo.getLocation(diagnostic.offset).columnNumber,
        message: diagnostic.message,
      ),
  ]..sort((a, b) {
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  });
}

class _ListDiagnosticListener implements DiagnosticListener {
  final diagnostics = <Diagnostic>[];

  @override
  void onDiagnostic(Diagnostic diagnostic) => diagnostics.add(diagnostic);
}
