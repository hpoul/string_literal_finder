import 'package:path/path.dart' as path;
import 'package:string_literal_finder/main.dart' show AnalysisOptions;
import 'package:test/test.dart';

/// Exclude globs are resolved relative to an absolute root directory, which is
/// spelled differently on Windows.
String _root(String name) =>
    path.join(path.rootPrefix(path.absolute(name)), name);

void main() {
  group('options', () {
    test('load options', () {
      final opts = AnalysisOptions.loadFromYaml(_root('test'), '''
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
      final opts = AnalysisOptions.loadFromYaml(_root('test'), '''
include: loremIpsum

analyzer:
  plugins:
    - string_literal_finder

''');
      expect(opts.excludeGlobs, isEmpty);
    });
  });
}
