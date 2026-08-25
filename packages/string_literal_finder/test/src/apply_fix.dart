// The fix framework's context objects are only reachable through `src/`.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:analysis_server_plugin/edit/change_builder/change_builder.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/fix/dart_fix_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/instrumentation/service.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analysis_server_plugin/src/correction/dart_change_workspace.dart';
import 'package:path/path.dart' as p;
import 'package:string_literal_finder/main.dart';

/// Runs [producer] against the literal at [marker] in [source] and returns the
/// resulting file content, or null if the fix declined to produce an edit.
///
/// Written against the real `CorrectionProducerContext` rather than a mock, so
/// that a fix which the analysis server would refuse to offer also declines
/// here. [source] is written into the `example/` package, which already depends
/// on `string_literal_finder_annotations`; pass `resolveAnnotations: false` to
/// simulate a project that does not.
Future<String?> applyFix(
  ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  producer,
  String source, {
  required String marker,
  bool resolveAnnotations = true,
}) async {
  final offset = source.indexOf(marker);
  if (offset == -1) {
    throw ArgumentError('Marker $marker not found in source.');
  }

  // `example/` depends on the annotations package; the bare package written by
  // [_packageWithoutAnnotations] deliberately does not, which is how the
  // dependency gate on `WrapWithNonNls` gets exercised.
  final root = resolveAnnotations
      ? p.normalize(p.join(Directory.current.absolute.path, 'example'))
      : _packageWithoutAnnotations().path;
  final filePath = p.join(root, 'lib', '__fix_test__.dart');
  _overlay.setOverlay(
    filePath,
    content: source,
    modificationStamp: DateTime.now().microsecondsSinceEpoch,
  );

  // Building an analysis context costs seconds, so one is kept per root and
  // the file is edited in place. Without this the suite takes minutes.
  final collection = _collections.putIfAbsent(
    root,
    () => AnalysisContextCollectionImpl(
      includedPaths: [root],
      resourceProvider: _overlay,
    ),
  );
  {
    final analysisContext = collection.contextFor(filePath);
    analysisContext.changeFile(filePath);
    await analysisContext.applyPendingFileChanges();
    final session = analysisContext.currentSession;
    final unit = await session.getResolvedUnit(filePath) as ResolvedUnitResult;
    final library =
        await session.getResolvedLibrary(filePath) as ResolvedLibraryResult;

    // The producers read the reported literal off the selection, so point the
    // selection at the literal exactly as the analysis server would.
    final literal = _literalAt(unit, offset);
    final diagnostic = Diagnostic.tmp(
      source: unit.libraryElement.firstFragment.source,
      offset: literal.offset,
      length: literal.length,
      diagnosticCode: LiteralStringRule.code,
      arguments: [literal.toSource()],
    );
    final context = CorrectionProducerContext.createResolved(
      libraryResult: library,
      unitResult: unit,
      selectionOffset: literal.offset,
      selectionLength: literal.length,
      diagnostic: diagnostic,
      dartFixContext: DartFixContext(
        instrumentationService: InstrumentationService.NULL_SERVICE,
        workspace: DartChangeWorkspace([session]),
        libraryResult: library,
        unitResult: unit,
        error: diagnostic,
      ),
    );

    final builder = ChangeBuilder(session: session);
    await producer(context: context).compute(builder);
    final edits = builder.sourceChange.edits;
    if (edits.isEmpty || edits.single.edits.isEmpty) {
      return null;
    }
    var result = source;
    // Apply back to front so earlier offsets stay valid.
    final sorted = edits.single.edits.toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));
    for (final edit in sorted) {
      result = result.replaceRange(
        edit.offset,
        edit.offset + edit.length,
        edit.replacement,
      );
    }
    return result;
  }
}

final _overlay = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
final _collections = <String, AnalysisContextCollectionImpl>{};
final _temporaryRoots = <Directory>[];

/// Tears down the shared analysis contexts. Call from `tearDownAll`.
Future<void> disposeFixHarness() async {
  for (final collection in _collections.values) {
    await collection.dispose();
  }
  _collections.clear();
  for (final dir in _temporaryRoots) {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
  _temporaryRoots.clear();
}

/// A resolved package whose package config contains only itself, so that
/// `package:string_literal_finder_annotations` cannot be resolved from it.
Directory _packageWithoutAnnotations() {
  if (_temporaryRoots.isNotEmpty) {
    return _temporaryRoots.single;
  }
  final dir = Directory.systemTemp.createTempSync('slf_fix_test');
  _temporaryRoots.add(dir);
  Directory(p.join(dir.path, 'lib')).createSync();
  Directory(p.join(dir.path, '.dart_tool')).createSync();
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: slf_fix_test
environment:
  sdk: ^3.11.0
''');
  File(p.join(dir.path, '.dart_tool', 'package_config.json')).writeAsStringSync(
    '''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "slf_fix_test",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.11"
    }
  ]
}
''',
  );
  return dir;
}

StringLiteral _literalAt(ResolvedUnitResult unit, int offset) {
  final node = unit.unit.nodeCovering(offset: offset, length: 1);
  final literal = node?.thisOrAncestorOfType<StringLiteral>();
  if (literal == null) {
    throw StateError('No string literal at offset $offset.');
  }
  return literal;
}
