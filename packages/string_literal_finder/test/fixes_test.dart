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

    test('is not confused by // inside a string on the same line', () async {
      // A URL is the archetypal literal someone suppresses. Grepping the line
      // for `//` mistakes it for an existing comment and emits ` NON-NLS`
      // with no comment marker, which does not parse.
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('https://example.com/target');
}
''', marker: "'https"),
        contains("f('https://example.com/target'); // NON-NLS"),
      );
    });

    test('is not confused by // in another literal on the line', () async {
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('target'); f('http://example.com');
}
'''),
        contains("f('http://example.com'); // NON-NLS"),
      );
    });

    test('declines when a doc comment trails the line', () async {
      // A `///` runs to the end of the line, so there is nowhere to put the
      // marker that is not inside it -- appending after it lands in the token
      // just the same, and the marker ends up in the rendered documentation
      // of whatever follows.
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('target'); /// docs for something else
}
'''),
        isNull,
      );
    });

    test('a //// comment is not a doc comment and is extended', () async {
      final result = await fix('''
void f(String v) {}
void g() {
  f('target'); //// just a separator
}
''');
      expect(result, contains('//// just a separator NON-NLS'));
    });

    test('declines when a block comment on the line spans further', () async {
      // Appending at the end of this line would land inside the author's
      // comment prose.
      expect(
        await fix('''
void f(String v) {}
void g() {
  f('target'); /* a comment
  spanning lines */
}
'''),
        isNull,
      );
    });

    test('appends after a block comment rather than inside it', () async {
      final result = await fix('''
void f(String v) {}
void g() {
  f('target'); /* note */
}
''');
      expect(result, contains("f('target'); /* note */ // NON-NLS"));
    });

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

    test('declines for an enum constant argument', () async {
      expect(
        await fix('''
enum E {
  a('target');
  const E(this.s);
  final String s;
}
'''),
        isNull,
      );
    });

    test('declines in a const constructor initializer', () async {
      expect(
        await fix('''
class C {
  const C() : s = 'target';
  final String s;
}
'''),
        isNull,
      );
    });

    test('declines in a const constructor assert message', () async {
      expect(
        await fix('''
class C {
  const C(this.x) : assert(x != '', 'target');
  final String x;
}
'''),
        isNull,
      );
    });

    test('declines for a field initialized inline in a const class', () async {
      // The field initializer has to be constant because the class declares a
      // const constructor, even though nothing here says `const`.
      expect(
        await fix('''
class C {
  const C();
  final String s = 'target';
}
'''),
        isNull,
      );
    });

    test('declines for an enum instance field', () async {
      // Enum constructors are implicitly const even when none is written, so
      // the initializer has to be constant. Nothing here says `const`.
      expect(
        await fix('''
enum E {
  a;
  final String s = 'target';
}
'''),
        isNull,
      );
    });

    test('a const factory does not force const field initializers', () async {
      // `const factory` redirects and declares no fields, so wrapping is safe.
      final result = await fix('''
class C {
  C.gen();
  const factory C() = D;
  final String s = 'target';
}
class D implements C {
  const D();
  String get s => '';
}
''');
      expect(result, contains("final String s = nonNls('target');"));
    });

    test('still wraps a field in a class with no const constructor', () async {
      final result = await fix('''
class C {
  C();
  final String s = 'target';
}
''');
      expect(result, contains("final String s = nonNls('target');"));
    });

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
