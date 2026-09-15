import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as p;
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:test/test.dart';

final _logger = Logger('string_literal_finder_test');

Future<List<FoundStringLiteral>> _findStrings(String source) async {
  final overlay = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final filePath = p.join(Directory.current.absolute.path, 'test/mytest.dart');
  overlay.setOverlay(
    filePath,
    content: source,
    modificationStamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
  // final parsed = parseString(content: source);
  final parsed =
      await resolveFile(path: filePath, resourceProvider: overlay)
          as ResolvedUnitResult;
  if (!parsed.exists) {
    throw StateError('file not found?');
  }
  final foundStrings = <FoundStringLiteral>[];
  final x = StringLiteralVisitor<dynamic>(
    filePath: filePath,
    unit: parsed.unit,
    foundStringLiteral: (found) {
      foundStrings.add(found);
      _logger.fine('Found String ${found.stringValue}');
    },
  );
  parsed.unit.visitChildren(x);
  return foundStrings;
}

void main() {
  PrintAppender.setupLogging();
  group('simple finder test', () {
    test('find string', () async {
      final found = await _findStrings('''
final _string = 'example';
''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'example');
    });
    test('NON-NLS end of line comment', () async {
      final found = await _findStrings('''
      final _string = 'example'; // NON-NLS
      ''');
      expect(found, isEmpty);
    });
    test('nonNls() function', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      final _string = nonNls('ignored');
      final _string2 = 'found';
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
  });
  group('literal shapes', () {
    test('adjacent strings are one literal, not three', () async {
      final found = await _findStrings('''
      final _string = 'foo' 'bar';
      ''');
      expect(found, hasLength(1));
      expect(found.single.sourceText, "'foo' 'bar'");
      expect(found.single.textValue, 'foobar');
    });
    test('interpolation is reported, with its literal text', () async {
      final found = await _findStrings(r'''
      final distance = 1;
      final _string = '$distance km';
      ''');
      expect(found, hasLength(1));
      expect(found.single.sourceText, r"'$distance km'");
      // `stringValue` is null for anything interpolated, which is why
      // `textValue` exists.
      expect(found.single.stringValue, isNull);
      expect(found.single.textValue, ' km');
    });
    test('a literal inside an interpolation is still found', () async {
      final found = await _findStrings(r'''
      String f(String a) => a;
      final _string = '${f('inner')} outer';
      ''');
      expect(
        found.map((e) => e.sourceText),
        containsAll([r"'${f('inner')} outer'", "'inner'"]),
      );
    });
    test('raw and multi-line strings are found', () async {
      final found = await _findStrings("""
      final a = r'raw';
      final b = '''multi
line''';
      """);
      expect(found.map((e) => e.textValue), ['raw', 'multi\nline']);
    });
    test('an unresolvable constructor does not throw', () async {
      // A project whose generated files are missing has plenty of types that
      // do not resolve. Force-unwrapping the type threw once per such literal
      // -- 191 times on one real Flutter app.
      //
      // `new`/`const` matter: without them the parser produces a
      // `MethodInvocation`, and only resolution rewrites a call to an
      // `InstanceCreationExpression` -- which it cannot do for a name that
      // does not resolve. So a bare `NoSuchType('x')` never reaches the branch
      // this covers.
      //
      // The literal is reported either way, so asserting on findings alone
      // cannot tell the fix from the bug; what changed is that nothing is
      // logged at SEVERE any more.
      final severe = <String>[];
      final subscription = Logger.root.onRecord
          .where((record) => record.level >= Level.SEVERE)
          .listen((record) => severe.add(record.message));
      addTearDown(subscription.cancel);

      final found = await _findStrings('''
      final a = new NoSuchType('found');
      final b = const NoSuchOtherType('alsoFound');
      ''');
      expect(found.map((e) => e.stringValue), ['found', 'alsoFound']);
      await Future<void>.delayed(Duration.zero);
      expect(severe, isEmpty);
    });
    test('an unresolvable index target does not warn', () async {
      // `target.element!` threw for an index expression whose target does not
      // resolve, and an inner catch logged a warning with a stack trace per
      // literal. An unresolved target is simply not one carrying `@NonNls`.
      final warnings = <String>[];
      final subscription = Logger.root.onRecord
          .where((record) => record.level >= Level.WARNING)
          .listen((record) => warnings.add(record.message));
      addTearDown(subscription.cancel);

      final found = await _findStrings('''
      final a = noSuchMap['found'];
      ''');
      expect(found.map((e) => e.stringValue), ['found']);
      await Future<void>.delayed(Duration.zero);
      expect(warnings, isEmpty);
    });
    test('@NonNls on the target of an index expression', () async {
      // A top-level variable or field is read through its synthetic getter,
      // whose metadata is empty, so checking the referenced element alone
      // only ever worked for a local variable.
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      @NonNls
      final topMap = <String, String>{};
      class C {
        @NonNls
        final fieldMap = <String, String>{};
        void m() {
          @NonNls
          final localMap = <String, String>{};
          final a = topMap['ignored'];
          final b = fieldMap['ignored'];
          final c = localMap['ignored'];
        }
      }
      ''');
      expect(found, isEmpty);
    });
    test('directive URIs are not literals', () async {
      // `export` was missing from the ignore list even though the README
      // promised directive URIs were ignored.
      final found = await _findStrings('''
      import 'dart:math';
      export 'dart:convert';
      final a = 'found';
      ''');
      expect(found.map((e) => e.stringValue), ['found']);
    });
    test('a literal on the last line without a trailing newline', () async {
      // The EOF token's `next` is the EOF token itself, so scanning forward
      // for a line-end comment used to spin forever -- a hard hang in the CLI
      // and in the analyzer plugin isolate.
      final found = await _findStrings("final a = 'x';");
      expect(found.map((e) => e.sourceText), ["'x'"]);
    });
    test('NON-NLS on the last line without a trailing newline', () async {
      final found = await _findStrings("final a = 'x'; // NON-NLS");
      expect(found, isEmpty);
    });
    test('an empty string is still reported by default', () async {
      // Filtering it out is opt-in; the finder itself does not decide.
      final found = await _findStrings('''
      final _string = '';
      ''');
      expect(found, hasLength(1));
    });
  });
  group('ignore annotations', () {
    test('function annotation', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
      
      @NonNls
      String test() {
        return 'ignored';
      }
      
      String test2() {
        return 'found';
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('method annotation', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
      
      class Example {
        @NonNls
        String test() {
          return 'ignored';
        }
        
        String test2() {
          return 'found';
        }
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('default values with annotation', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
      
      abstract class Example {
        String test([@NonNls String foo = 'ignored']);
        
        String test2([String foo = 'found']);
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('properties with annotation', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
      
      abstract class Example {
        @NonNls
        static const test1 = 'ignored';
        
        static const test2 = 'found';
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('static properties of classes', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
      
      @NonNls
      abstract class Example {
        static const test1 = 'ignored';
      }
      @NonNls
      abstract class Example2 {
        final test2 = 'found';
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('enhanced enums', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
      
      enum EnumWithString1 {
        value('found'),
        ;
        EnumWithString1(this.val);
        String val;
      }
      enum EnumWithString2 {
        value('ignored'),
        ;
        EnumWithString2(@NonNls this.val);
        String val;
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('@NonNls after an annotation that does not resolve', () async {
      // source_gen walks annotations in order and, by default, throws at the
      // first whose constant is null -- so `@NonNls` sitting *after* an
      // unresolved annotation was never reached and everything below it was
      // reported. Order-dependent: swapping the two used to suppress fine.
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      @SomeGeneratedThing()
      @NonNls
      String keys() {
        return 'ignored';
      }
      ''');
      expect(found, isEmpty);
    });
    test('@NonNls before an annotation that does not resolve', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      @NonNls
      @SomeGeneratedThing()
      String keys() {
        return 'ignored';
      }
      ''');
      expect(found, isEmpty);
    });
    test('named arguments of a method invocation', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      void func({@NonNls String? key, String? label}) {}

      void main() {
        func(key: 'ignored', label: 'found');
      }
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
    test('a named argument written before a positional one', () async {
      // Since Dart 2.17 the call site may order these freely, so an
      // argument's index in the list is not its parameter index.
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      void func(String label, {@NonNls String? key}) {}

      void main() {
        func(key: 'ignored', 'found');
      }
      ''');
      expect(found.map((e) => e.stringValue), ['found']);
    });
    test('a positional @NonNls after a named argument', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      void func(@NonNls String key, {String? label}) {}

      void main() {
        func(label: 'found', 'ignored');
      }
      ''');
      expect(found.map((e) => e.stringValue), ['found']);
    });
    test('named arguments of a constructor invocation', () async {
      final found = await _findStrings('''
      import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

      class Example {
        Example({@NonNls this.key, this.label});
        final String? key;
        final String? label;
      }

      final example = Example(key: 'ignored', label: 'found');
      ''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'found');
    });
  });
}
