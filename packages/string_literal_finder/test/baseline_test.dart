import 'package:path/path.dart' as p;
import 'package:string_literal_finder/src/baseline.dart';
import 'package:test/test.dart';

import 'src/fake_literal.dart';

void main() {
  final basePath = p.join(p.rootPrefix(p.absolute('x')), 'project', 'lib');
  String file(String name) => p.join(basePath, name);

  group('Baseline', () {
    test('counts repeated literals per file', () {
      final baseline = Baseline.fromFound([
        fakeLiteral(file('a.dart'), "'-'"),
        fakeLiteral(file('a.dart'), "'-'"),
        fakeLiteral(file('b.dart'), "'-'"),
      ], basePath);
      expect(baseline.literals, {
        'a.dart': {"'-'": 2},
        'b.dart': {"'-'": 1},
      });
      expect(baseline.totalCount, 3);
    });

    test('survives a round trip through json', () {
      final baseline = Baseline.fromFound([
        fakeLiteral(file('a.dart'), "'hello'"),
        fakeLiteral(file(p.join('ui', 'b.dart')), r"'$count items'"),
      ], basePath);
      expect(Baseline.fromJson(baseline.toJson()).literals, baseline.literals);
    });

    test('stores paths with forward slashes so the file is portable', () {
      final baseline = Baseline.fromFound([
        fakeLiteral(file(p.join('ui', 'nested', 'b.dart')), "'x'"),
      ], basePath);
      expect(baseline.literals.keys, ['ui/nested/b.dart']);
    });

    test('is sorted, so it diffs cleanly', () {
      final baseline = Baseline.fromFound([
        fakeLiteral(file('z.dart'), "'b'"),
        fakeLiteral(file('z.dart'), "'a'"),
        fakeLiteral(file('a.dart'), "'c'"),
      ], basePath);
      final json = baseline.toJson();
      expect(json.indexOf('a.dart'), lessThan(json.indexOf('z.dart')));
      expect(json.indexOf("'a'"), lessThan(json.indexOf("'b'")));
      expect(json, endsWith('\n'));
    });

    test('rejects a future format version rather than misreading it', () {
      expect(
        () => Baseline.fromJson('{"version": 99, "literals": {}}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('--write-baseline'),
          ),
        ),
      );
    });

    group('compare', () {
      final baseline = Baseline.fromFound([
        fakeLiteral(file('a.dart'), "'known'"),
        fakeLiteral(file('a.dart'), "'twice'"),
        fakeLiteral(file('a.dart'), "'twice'"),
      ], basePath);

      test('accepts an unchanged set of findings', () {
        final result = baseline.compare([
          fakeLiteral(file('a.dart'), "'known'"),
          fakeLiteral(file('a.dart'), "'twice'"),
          fakeLiteral(file('a.dart'), "'twice'"),
        ], basePath);
        expect(result.newLiterals, isEmpty);
        expect(result.obsoleteCount, 0);
      });

      test('ignores the line a known literal now sits on', () {
        final result = baseline.compare([
          fakeLiteral(file('a.dart'), "'known'", line: 400),
          fakeLiteral(file('a.dart'), "'twice'", line: 401),
          fakeLiteral(file('a.dart'), "'twice'", line: 402),
        ], basePath);
        expect(result.newLiterals, isEmpty);
      });

      test('reports a literal that is new', () {
        final result = baseline.compare([
          fakeLiteral(file('a.dart'), "'known'"),
          fakeLiteral(file('a.dart'), "'brand new'"),
        ], basePath);
        expect(result.newLiterals.map((e) => e.sourceText), ["'brand new'"]);
      });

      test('reports an extra copy of a literal it already knows', () {
        final result = baseline.compare([
          fakeLiteral(file('a.dart'), "'twice'"),
          fakeLiteral(file('a.dart'), "'twice'"),
          fakeLiteral(file('a.dart'), "'twice'"),
        ], basePath);
        expect(result.newLiterals, hasLength(1));
      });

      test('reports a known literal that moved to another file', () {
        final result = baseline.compare([
          fakeLiteral(file('b.dart'), "'known'"),
        ], basePath);
        expect(result.newLiterals.map((e) => e.sourceText), ["'known'"]);
      });

      test('counts baseline entries that no longer exist', () {
        final result = baseline.compare([
          fakeLiteral(file('a.dart'), "'known'"),
        ], basePath);
        expect(result.newLiterals, isEmpty);
        expect(result.obsoleteCount, 2);
      });
    });
  });

  test('an empty baseline reports everything as new', () {
    final result = Baseline.empty().compare([
      fakeLiteral(file('a.dart'), "'x'"),
    ], basePath);
    expect(result.newLiterals, hasLength(1));
  });
}
