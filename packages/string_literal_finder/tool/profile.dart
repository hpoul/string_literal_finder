import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as path;
import 'package:string_literal_finder/src/string_literal_finder.dart';

Future<void> main(List<String> args) async {
  final basePath = path.absolute(args[0]);
  final total = Stopwatch()..start();
  final sw = Stopwatch()..start();
  final collection = AnalysisContextCollection(includedPaths: [basePath]);
  print('collection creation: ${sw.elapsedMilliseconds}ms');

  sw.reset();
  final files = <String>[];
  for (final context in collection.contexts) {
    files.addAll(context.contextRoot.analyzedFiles());
  }
  print('contexts: ${collection.contexts.length}, analyzedFiles(): '
      '${files.length} files in ${sw.elapsedMilliseconds}ms');

  final excludes = ExcludePathChecker.excludePathDefaults;
  var resolveMs = 0;
  var visitMs = 0;
  var found = 0;
  var analyzed = 0;
  sw.reset();
  for (final context in collection.contexts) {
    for (final filePath in context.contextRoot.analyzedFiles()) {
      final relative = path.relative(filePath, from: basePath);
      if (excludes.any((e) => e.shouldExclude(relative)) ||
          filePath.endsWith('.g.dart')) {
        continue;
      }
      analyzed++;
      final r = Stopwatch()..start();
      final result = await context.currentSession.getResolvedUnit(filePath);
      resolveMs += r.elapsedMicroseconds;
      if (result is! ResolvedUnitResult) {
        continue;
      }
      final v = Stopwatch()..start();
      final visitor = StringLiteralVisitor<dynamic>(
        filePath: filePath,
        unit: result.unit,
        foundStringLiteral: (f) => found++,
      );
      result.unit.visitChildren(visitor);
      visitMs += v.elapsedMicroseconds;
    }
  }
  print('analyzed $analyzed files, found $found literals');
  print('  resolve: ${(resolveMs / 1000).round()}ms');
  print('  visit:   ${(visitMs / 1000).round()}ms');
  print('  loop total: ${sw.elapsedMilliseconds}ms');
  print('TOTAL: ${total.elapsedMilliseconds}ms');
}
