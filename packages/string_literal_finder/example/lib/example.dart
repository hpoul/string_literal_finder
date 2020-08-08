library example;

import 'package:logging/logging.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

final _logger = Logger('example');

class Example {
  // ignore: avoid_unused_constructor_parameters
  const Example(@NonNls String test);
}

void exampleFunc(@NonNls String ignored, String warning) {}

void main() {
  const Example('Lorem ipsum');
  exampleFunc('Hello world', 'not translated');
  _logger.finer('Lorem ipsum');

  final testMap = nonNls({
    'key': 'value',
  });
}
