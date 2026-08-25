@Timeout(Duration(minutes: 5))
library;

import 'package:string_literal_finder/src/fixes.dart';
import 'package:test/test.dart';

import 'src/apply_fix.dart';

void main() {
  tearDownAll(disposeFixHarness);

  group('AddNonNlsComment', () {
    Future<String?> fix(String source, {String marker = "'target'"}) =>
        applyFix(AddNonNlsComment.new, source, marker: marker);

    test('appends the comment to the end of the line', () async {
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('target');
}
'''),
        '''
void f(String v) {}
void g() {
  f('target'); // NON-NLS
}
''',
      );
    });

    test(
      'extends an existing trailing comment rather than replacing it',
      () async {
        // The finder looks for NON-NLS anywhere in the comment text, so
        // appending is enough and the author's note survives.
        expect(
          await fix('''
void f(String v) {}
void g() {
  f('target'); // keep me
}
'''),
          contains('f(\'target\'); // keep me NON-NLS'),
        );
      },
    );

    test(
      'uses the line the literal ENDS on, not the one it starts on',
      () async {
        // This is the actual semantics of the suppression, and the reason a
        // comment on the closing `);` of a multi-line call does nothing.
        final result = await fix("""
void f(String v) {}
void g() {
  f('''target
spanning''');
}
""", marker: "'''target");
        expect(result, contains("spanning'''); // NON-NLS"));
      },
    );

    test('declines when the line continues into a multi-line string', () async {
      // Appending at the end of this line would put the comment *inside* the
      // contents of `multi`, silently changing the program.
      expect(
        await fix("""
void f(String v) {}
void g() {
  f('target'); final multi = '''
inside
''';
  print(multi);
}
"""),
        isNull,
      );
    });
  });

  group('WrapWithNonNls', () {
    Future<String?> fix(
      String source, {
      String marker = "'target'",
      bool resolveAnnotations = true,
    }) => applyFix(
      WrapWithNonNls.new,
      source,
      marker: marker,
      resolveAnnotations: resolveAnnotations,
    );

    test('wraps the literal and adds the import', () async {
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('target');
}
'''),
        '''
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

void f(String v) {}
void g() {
  f(nonNls('target'));
}
''',
      );
    });

    test('reuses an existing import', () async {
      final result = await fix('''
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

void f(String v) {}
void g() {
  f('target');
}
''');
      expect(result, contains("f(nonNls('target'));"));
      expect(
        'import '.allMatches(result!).length,
        1,
        reason: 'should not add a second import',
      );
    });

    test('wraps the whole AdjacentStrings, not one operand', () async {
      // Wrapping a single operand would suppress nothing, because the finder
      // reports the adjacent strings as one literal.
      final result = await fix('''
void f(String v) {}
void g() {
  f('target' 'and more');
}
''');
      expect(result, contains("f(nonNls('target' 'and more'));"));
    });

    test(
      'declines in a const context, where a call does not compile',
      () async {
        expect(
          await fix('''
class C {
  const C(this.s);
  final String s;
}
const value = C('target');
'''),
          isNull,
        );
      },
    );

    test('declines in a default parameter value', () async {
      expect(
        await fix('''
void f([String v = 'target']) {}
'''),
        isNull,
      );
    });

    test('declines when the annotations package is not a dependency', () async {
      // Offering a fix that produces uncompilable code would be worse than
      // offering none.
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('target');
}
''', resolveAnnotations: false),
        isNull,
      );
    });
  });
}
