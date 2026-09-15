import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';
import 'package:test/test.dart';

void main() {
  test('nonNls returns its argument unchanged', () {
    // The whole point is that it is invisible at runtime: it exists so that
    // `string_literal_finder` has something to recognise.
    const value = 'not translated';
    expect(nonNls(value), same(value));

    const map = {'key': 'value'};
    expect(nonNls(map), same(map));
  });

  test('nonNls preserves the static type', () {
    // Regression guard: if the signature stopped being generic, wrapping a
    // value would silently widen it to Object.
    final list = nonNls(<int>[1, 2, 3]);
    expect(list, isA<List<int>>());
  });

  test('NonNls is a const NonNlsArg, so it can annotate anything', () {
    // `@NonNls` and `@NonNlsArg()` have to be interchangeable, since the
    // finder recognises the *type*, not the name.
    expect(NonNls, isA<NonNlsArg>());
    expect(const NonNlsArg(), isA<NonNlsArg>());
  });
}
