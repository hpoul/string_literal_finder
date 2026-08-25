import 'package:string_literal_finder/src/filters.dart';
import 'package:test/test.dart';

import 'src/fake_literal.dart';

void main() {
  bool ignores(LiteralFilter filter, String source) =>
      filter.discards(fakeLiteral('a.dart', source));

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

    test('discards an interpolation with no literal text at all', () {
      // Pure substitution -- there is nothing there to translate.
      for (final source in [r"'$error'", r"'$url'", r"'${entry.key}'"]) {
        expect(ignores(filter, source), isTrue, reason: source);
      }
    });

    test('keeps an interpolation with letterless text between the holes', () {
      // These have no word in them either, but each is a template whose
      // separator, ordering or pluralisation can differ by locale. Dropping
      // them would hide exactly the bugs this tool is best at finding.
      for (final source in [
        r"' $unit'",
        r"'$a – $b'",
        r"'${w} × ${h}'",
        r"'$monthDay, ${format.year(local)}'",
        r"'$count $noun${count == 1 ? '' : 's'}'",
      ]) {
        expect(ignores(filter, source), isFalse, reason: source);
      }
    });

    test('keeps interpolated copy', () {
      expect(ignores(filter, r"'$distance km'"), isFalse);
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

    test('keeps a phrase whose first word ends in punctuation', () {
      // The letter need not touch the space.
      for (final source in [
        "'Hello, world'",
        "'Yes, delete'",
        "'No, thanks'",
        "'Done!  Next'",
      ]) {
        expect(ignores(filter, source), isFalse, reason: source);
      }
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

  group('no filter can discard an interpolated template', () {
    // The whole class of bug: an interpolated literal's `textValue` is only
    // the fragments between the holes, so a rule about a whole string sees
    // `' '` for `' $unit'` and matches things it never meant to.
    const templates = [
      r"' $unit'",
      r"'$a – $b'",
      r"'${w} × ${h}'",
      r"'$monthDay, ${format.year(local)}'",
      r"'$count $noun${count == 1 ? '' : 's'}'",
    ];

    for (final filters in <(String, List<LiteralFilter>)>[
      ('--ignore-symbols', [const NoLetterFilter()]),
      ('--min-length=2', [const MinLengthFilter(2)]),
      ('--min-length=20', [const MinLengthFilter(20)]),
      (r"--ignore-pattern='^\s*$'", [PatternFilter.parse(r'^\s*$')]),
      (r"--ignore-pattern='^\P{L}*$'", [PatternFilter.parse(r'^\P{L}*$')]),
      (r"--ignore-pattern='.*'", [PatternFilter.parse('.*')]),
      ('--prose-only', [const ProseOnlyFilter()]),
    ]) {
      test(filters.$1, () {
        final found = [
          for (final source in templates) fakeLiteral('a.dart', source),
        ];
        expect(filters.$2.apply(found), hasLength(templates.length));
      });
    }
  });

  group('but a literal made only of holes has nothing to translate', () {
    test('and is discarded', () {
      final found = [
        fakeLiteral('a.dart', r"'$error'"),
        fakeLiteral('a.dart', r"'${entry.key}'"),
      ];
      expect(<LiteralFilter>[const NoLetterFilter()].apply(found), isEmpty);
    });
  });

  test('--ignore-symbols is exactly --ignore-pattern=^\\P{L}*\$', () {
    final found = [
      for (final source in [
        "''",
        "' '",
        "'/'",
        "'0'",
        "'2026-08-12'",
        "'Cancel'",
        r"'$error'",
        r"' $unit'",
        r"'$distance km'",
      ])
        fakeLiteral('a.dart', source),
    ];
    expect(
      <LiteralFilter>[
        const NoLetterFilter(),
      ].apply(found).map((e) => e.sourceText),
      <LiteralFilter>[
        PatternFilter.parse(r'^\P{L}*$'),
      ].apply(found).map((e) => e.sourceText),
    );
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
