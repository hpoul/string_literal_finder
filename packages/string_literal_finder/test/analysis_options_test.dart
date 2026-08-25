import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:string_literal_finder/main.dart' show AnalysisOptions;
import 'package:test/test.dart';

/// [MemoryResourceProvider] only accepts absolute paths, which are spelled
/// differently on Windows.
Folder _root(MemoryResourceProvider resource, String name) {
  final context = resource.pathContext;
  return resource
      .getFolder(context.join(context.rootPrefix(context.current), name));
}

void main() {
  group('options', () {
    test('load options', () {
      final resource = MemoryResourceProvider();
      final opts = AnalysisOptions.loadFromYaml(_root(resource, 'test'), '''
string_literal_finder:
  exclude_globs:
    - '_tools/**'
    - '**/*.g.dart'
    - '**/*.freezed.dart'

''');
      expect(opts.excludeGlobs, hasLength(3));
      expect(opts.isExcluded('lorem/ipsum/test.dart'), isFalse);
      expect(opts.isExcluded('lorem/ipsum/test.freezed.dart'), isTrue);
      expect(opts.isExcluded('_tools/_flutter_version_update.dart'), isTrue);
    });
    test('empty options', () {
      final resource = MemoryResourceProvider();
      final opts = AnalysisOptions.loadFromYaml(_root(resource, 'test'), '''
include: loremIpsum

analyzer:
  plugins:
    - string_literal_finder

''');
      expect(opts.excludeGlobs, isEmpty);
    });
  });
}
