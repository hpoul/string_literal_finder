import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

class NonNlsArg {
  const NonNlsArg();
}

const NonNls = NonNlsArg();

/// Allows annotating of values which do not need translations.
T nonNls<T>(@NonNls T arg) => arg;
