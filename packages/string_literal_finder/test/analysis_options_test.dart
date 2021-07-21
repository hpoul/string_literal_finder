import 'package:string_literal_finder/src/plugin.dart';
import 'package:test/test.dart';

void main() {
  group('options', () {
    test('load options', () {
      final opts = AnalysisOptions.loadFromYaml('''
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
      final opts = AnalysisOptions.loadFromYaml('''
include: loremIpsum

analyzer:
  plugins:
    - string_literal_finder

''');
      expect(opts.excludeGlobs, isEmpty);
    });
  });
}
