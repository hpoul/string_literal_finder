/// Applies [cb] to a non-null receiver, so an optional value can be mapped
/// without naming it twice.
extension LetExtension<T extends Object> on T {
  U let<U>(U Function(T value) cb) => cb(this);
}
