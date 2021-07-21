import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:test/test.dart';

final _logger = Logger('string_literal_finder_test');

List<FoundStringLiteral> _findStrings(String source) {
  final parsed = parseString(content: source);
  final foundStrings = <FoundStringLiteral>[];
  final x = StringLiteralVisitor<dynamic>(
    filePath: 'foo.dart',
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
    test('find string', () {
      final found = _findStrings('''
final _string = 'example';
''');
      expect(found, hasLength(1));
      expect(found.first.stringValue, 'example');
    });
  });
}
