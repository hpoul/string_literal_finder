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

    // A `// NON-NLS` names the line its literal ends on, so it only means what
    // it says for as long as the line breaks stay put -- and `dart format`
    // owns the line breaks. Four of eight applications in one real file were
    // dead after a single format run, which is why these decline instead.
    group('would not survive dart format', () {
      test('declines when the marker would cross the page width', () async {
        // Under the page width now, over it once the marker is appended: the
        // formatter re-splits the statement, the literal moves up a line, and
        // the marker is left behind on the closing one.
        final name = 'f' * 62;
        final line = "  $name('target');";
        expect(line.length, 75);
        expect(line.length + ' // NON-NLS'.length, greaterThan(80));
        expect(
          await fix('''
void $name(String v) {}
void g() {
$line
}
'''),
          isNull,
        );
      });

      test('still appends when the line is already over the width', () async {
        // Nothing can split a line whose length is one long literal, so the
        // marker is not what decides the layout here and appending is safe.
        final long = 'target${'x' * 90}';
        final result = await fix('''
void f(String v) {}
void g() {
  f('$long');
}
''', marker: "'target");
        expect(result, contains("f('$long'); // NON-NLS"));
      });

      test('declines when the line ends with an open collection', () async {
        // The observed case: the formatter reads the marker as the leading
        // comment of the first entry and moves it inside the map.
        expect(
          await fix('''
void f(String v, Map<String, String> m) {}
void g() {
  f('target', {
    'a': 'b',
  });
}
'''),
          isNull,
        );
      });

      test('declines when the line ends with an open argument list', () async {
        expect(
          await fix('''
void f(String v, String w) {}
void g() {
  f('target', f(
    'a',
    'b',
  ));
}
'''),
          isNull,
        );
      });

      test('still appends when the line ends with a block brace', () async {
        // A block brace does not pull a trailing comment inside it, and
        // `if (x == 'target') {` is an ordinary place to want a suppression --
        // so the rule has to ask what the bracket opens, not what it looks
        // like.
        final result = await fix('''
void g(String x) {
  if (x == 'target') {
    print(x);
  }
}
''');
        expect(result, contains("if (x == 'target') { // NON-NLS"));
      });
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
