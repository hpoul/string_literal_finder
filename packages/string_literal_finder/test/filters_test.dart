import 'package:string_literal_finder/src/filters.dart';
import 'package:test/test.dart';

import 'src/fake_literal.dart';

void main() {
  bool ignores(LiteralFilter filter, String source) =>
      filter.shouldIgnore(fakeLiteral('a.dart', source));

  group('NoLetterFilter', () {
    const filter = NoLetterFilter();

    test('discards punctuation, digits and whitespace', () {
      for (final source in [
        "''",
        "' '",
        "'/'",
        "'-'",
        "','",
        "': '",
        "'0'",
        "'0.00'",
        r"'\n'",
        "' · '",
      ]) {
        expect(ignores(filter, source), isTrue, reason: source);
      }
    });

    test('keeps anything with a letter, however short', () {
      for (final source in ["'OK'", "'s'", "'.jpg'", "'de'", "'Cancel'"]) {
        expect(ignores(filter, source), isFalse, reason: source);
      }
    });

    test('looks past interpolation to the literal text', () {
      // ` km` is visible copy; the interpolated value is not part of it.
      expect(ignores(filter, r"'$distance km'"), isFalse);
      expect(ignores(filter, r"'$a/$b'"), isTrue);
    });

    test('sees non-latin letters', () {
      expect(ignores(filter, "'Ünicode'"), isFalse);
      expect(ignores(filter, "'日本語'"), isFalse);
    });
  });

  group('MinLengthFilter', () {
    test('measures the visible text, ignoring surrounding space', () {
      const filter = MinLengthFilter(3);
      expect(ignores(filter, "'ab'"), isTrue);
      expect(ignores(filter, "'  ab  '"), isTrue);
      expect(ignores(filter, "'abc'"), isFalse);
    });

    test('discards the empty string at any length above zero', () {
      expect(ignores(const MinLengthFilter(1), "''"), isTrue);
      expect(ignores(const MinLengthFilter(0), "''"), isFalse);
    });
  });

  group('PatternFilter', () {
    test('matches against the visible text', () {
      final filter = PatternFilter.parse(r'^\.[a-z0-9]+$');
      expect(ignores(filter, "'.jpg'"), isTrue);
      expect(ignores(filter, "'a .jpg file'"), isFalse);
    });
  });

  group('ProseOnlyFilter', () {
    const filter = ProseOnlyFilter();

    test('keeps phrases of two or more words', () {
      expect(ignores(filter, "'Hello world'"), isFalse);
      expect(ignores(filter, r"'Back to your tours'"), isFalse);
    });

    test('discards single words, including real labels', () {
      // Documented false negatives -- this is why it is not a gate.
      for (final source in ["'Cancel'", "'Back'", "'Hidden'"]) {
        expect(ignores(filter, source), isTrue, reason: source);
      }
    });

    test('discards identifiers and paths', () {
      for (final source in [
        "'user_id'",
        "'assets/icons/x.svg'",
        "'yyyy-MM-dd'",
      ]) {
        expect(ignores(filter, source), isTrue, reason: source);
      }
    });
  });

  group('apply', () {
    test('an empty filter list keeps everything', () {
      final found = [fakeLiteral('a.dart', "''")];
      expect(<LiteralFilter>[].apply(found), same(found));
    });

    test('a literal is dropped if any filter discards it', () {
      final found = [
        fakeLiteral('a.dart', "''"),
        fakeLiteral('a.dart', "'ab'"),
        fakeLiteral('a.dart', "'Hello world'"),
      ];
      final filters = <LiteralFilter>[
        const NoLetterFilter(),
        const MinLengthFilter(3),
      ];
      expect(filters.apply(found).map((e) => e.sourceText), ["'Hello world'"]);
    });
  });
}
