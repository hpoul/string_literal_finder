library example;

import 'package:logging/logging.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

final _logger = Logger('example');

class Example {
  // ignore: avoid_unused_constructor_parameters
  const Example(@NonNls String test);
}

void exampleFunc(@NonNls String ignored, String warning) {}

// parameters to annotations are ignored.
@SomeAnnotation('test')
void main() {
  const Example('Lorem ipsum');
  exampleFunc('Hello world', 'not translated');
  exampleFunc('lorem'.split('').join(''), 'not translated2'.split('').join(''));
  _logger.finer('Lorem ipsum');

  nonNls({
    'nonNlsKey1': 'nonNlsValue1',
  });

  @NonNls
  final testMap = nonNls({
    'key': 'value',
  });
  // since `testMap` is annotated with @NonNls, accessing the key with
  // a string literal will be ignored.
  print(testMap['key']);
}

class SomeAnnotation {
  const SomeAnnotation(String test);
}
