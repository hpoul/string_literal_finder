/// Annotation for function/method/constructor parameters which are not
/// meant to be localized. Simply use [NonNls].
class NonNlsArg {
  const NonNlsArg();
}

/// Annotation for function/method/constructor parameters which are not meant
/// to be localized.
const NonNls = NonNlsArg();

/// Allows annotating of values which do not need translations.
T nonNls<T>(@NonNls T arg) => arg;
