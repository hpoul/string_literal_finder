See [string_literal_finder][1] for details.

[1]: https://pub.dev/packages/string_literal_finder


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
