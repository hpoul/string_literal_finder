/// Annotation for function/method/constructor parameters which are not
/// meant to be localized. Simply use [NonNls].
class NonNlsArg {
  const NonNlsArg();
}

/// Annotation for function/method/constructor parameters which are not meant
/// to be localized.
// ignore: constant_identifier_names
const NonNls = NonNlsArg();

/// Allows annotating of values which do not need translations.
///
/// Returns [arg] unchanged, so wrapping a value never changes what the code
/// does — but it must not change the value's *type* either, and that is why
/// [T] is bound to [Object].
///
/// Without the bound, [T] is inferred from the surrounding context rather than
/// from [arg], so a nullable context widens the result. On the right of `??`
/// that is enough to break compilation somewhere else entirely:
///
/// ```dart
/// final user = entry.getString(k)?.getText() ?? nonNls('');
/// ```
///
/// [T] would bind to `String?`, making `user` nullable and the
/// `Map<String, String>` it feeds stop compiling. Since a string literal is
/// never null, nothing is lost by refusing to let [T] be nullable.
T nonNls<T extends Object>(@NonNls T arg) => arg;
