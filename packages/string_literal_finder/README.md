# string_literal_finder

Simple command line application to find non translated string literals
in dart code.

Tries to be smart about ignoring specific strings.

## Example

The following dart file:

```dart
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
import 'package:logging/logging.dart';

final _logger = Logger('example');

void exampleFunc(@NonNls String ignored, String warning) {}

void main() {
  exampleFunc('Hello world', 'not translated');
  _logger.finer('Lorem ipsum');

  final testMap = nonNls({
    'key': 'value',
  });
}
```

will result in those warnings:

```shell
$ dart bin/string_literal_finder.dart example
2020-08-08 14:21:18.259156 INFO string_literal_finder - Found 1 literals:
2020-08-08 14:21:18.259511 INFO string_literal_finder - /Users/herbert/dev/string_literal_finder/packages/string_literal_finder/example/lib/example.dart:18:30 'not translated'
Found 1 literals in 1 files.
$ 
```

# Ignored literal strings

* Any argument annotated with `@NonNls` or `@NonNlsArg()`
* Anything which is parsed into the `nonNls` function.
* Anything passed to `logging` library `Logger` class.
* Any line with a line end comment `// NON-NLS`
