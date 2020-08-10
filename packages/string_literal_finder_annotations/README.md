# string_literal_finder_annotations

Runtime helper for the [string_literal_finder](https://pub.dev/packages/string_literal_finder).

## Usage

A simple usage example:

```dart
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

void myFunc(@NonNls String nonTranslatable) {}

main() {
  // ignored, because of @NonNls annotation
  myFunc('Lorem ipsum');

  // ignored, because wrapped in `nonNls`
  final map = nonNls({
    'lorem': 'ipsum',
  });
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/hpoul/string_literal_finder/issues
