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
  final parsed = await resolveFile2(path: filePath, resourceProvider: overlay)
      as ResolvedUnitResult;
  if (!parsed.exists) {
    throw StateError('file not found?');
  }
  final foundStrings = <FoundStringLiteral>[];
  final x = StringLiteralVisitor<dynamic>(
    filePath: filePath,
    unit: parsed.unit!,
    foundStringLiteral: (found) {
      foundStrings.add(found);
      _logger.fine('Found String ${found.stringValue}');
    },
  );
  parsed.unit!.visitChildren(x);
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
  });
}
