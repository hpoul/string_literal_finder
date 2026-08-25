@Timeout(Duration(minutes: 3))
library;

import 'package:test/test.dart';

import 'src/run_rule.dart';

/// Exercises the analyzer-plugin path, which reaches the shared visitor through
/// the rule framework rather than by walking the AST directly.
///
/// The two front ends have disagreed twice: the plugin missed string
/// interpolations entirely, and later reported literals nested inside one
/// twice. Both were found by hand, so both are pinned here.
void main() {
  test('a plain literal is reported once', () async {
    expect(
      await runRule('''
final a = 'plain';
'''),
      [(line: 1, column: 11, message: "Found string literal plain")],
    );
  });

  test(
    'an interpolation is reported — the plugin used to miss these',
    () async {
      final reported = await runRule(r'''
final distance = 1;
final a = '$distance km';
''');
      expect(reported, hasLength(1));
      expect(reported.single.line, 2);
    },
  );

  test('adjacent strings are one finding, not three', () async {
    // The framework dispatches the AdjacentStrings *and* both operands, so
    // this only holds because operands of an enclosing literal are skipped.
    expect(
      await runRule('''
final a = 'foo' 'bar';
'''),
      hasLength(1),
    );
  });

  test(
    'a literal nested in an interpolation is reported exactly once',
    () async {
      // The regression: the visitor descended into interpolated expressions
      // while the framework was already dispatching them, so 'inner' came back
      // twice.
      final reported = await runRule(r'''
String f(String a) => a;
final a = '${f('inner')} outer';
''');
      expect(reported, hasLength(2));
      expect(
        reported.map((e) => e.column),
        // The outer literal, then 'inner' within it — each once.
        [11, 16],
      );
    },
  );

  test('nesting several levels deep still reports each literal once', () async {
    final reported = await runRule(r'''
String f(String a) => a;
final a = '${f('${f('deep')} mid')} outer';
''');
    expect(reported.map((e) => e.message), [
      contains('outer'),
      contains('mid'),
      contains('deep'),
    ]);
  });

  test('adjacent strings inside an interpolation hole', () async {
    final reported = await runRule(r'''
String f(String a) => a;
final a = '${f('foo' 'bar')} outer';
''');
    expect(reported, hasLength(2));
  });

  test('suppressions apply on this path too', () async {
    expect(
      await runRule('''
import 'package:logging/logging.dart';
final _logger = Logger('name');
void f() {
  _logger.info('ignored');
}
final a = 'found'; // NON-NLS
'''),
      isEmpty,
    );
  });
}
