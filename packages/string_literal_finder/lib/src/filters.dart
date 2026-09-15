import 'package:string_literal_finder/src/string_literal_finder.dart';

/// An additional, opt-in rule for discarding findings which are unlikely to be
/// user visible copy.
///
/// None of these are enabled by default. Each of them can hide a real
/// untranslated string, and a tool that silently drops findings is worse than a
/// noisy one — so the choice of how much to hide belongs to the project, not to
/// the tool.
///
/// The proportions described below were observed on a real Flutter
/// application rather than invented, but they vary a lot between code bases.
/// Measure your own with `--format=json` before trusting any of them.
sealed class LiteralFilter {
  const LiteralFilter();

  /// Whether [literal] should be discarded.
  ///
  /// This is the entry point, and it enforces [textValueIsWholeLiteral] before
  /// consulting [shouldIgnore]. **No filter can discard an interpolated
  /// literal that has text between the holes**, whether it is a built-in rule
  /// or a `--ignore-pattern` someone wrote by hand.
  bool discards(FoundStringLiteral literal) =>
      textValueIsWholeLiteral(literal) && shouldIgnore(literal);

  /// The filter's own rule, given a literal that it is safe to judge.
  ///
  /// Subclasses implement this; callers want [discards].
  bool shouldIgnore(FoundStringLiteral literal);

  /// Human readable description, reported in the run summary so it is obvious
  /// which filters were active when a number was produced.
  String get description;

  /// Whether [FoundStringLiteral.textValue] describes the whole literal, and
  /// can therefore safely be tested against a rule meant for a whole string.
  ///
  /// It does not when a literal is interpolated and has text between the
  /// holes, because `textValue` then reports only the fragments: `' $unit'`
  /// reduces to `' '` and `'$a – $b'` to `' – '`. A rule such as "is only
  /// whitespace" or "has no letters" matches those, and they are templates
  /// whose separator, ordering or pluralisation can differ by locale — exactly
  /// the findings worth keeping.
  ///
  /// A literal made up of nothing but holes (`'$error'`) is fair game: there
  /// is nothing between them to translate.
  static bool textValueIsWholeLiteral(FoundStringLiteral literal) =>
      !literal.isInterpolated || literal.textValue.isEmpty;
}

/// Discards literals with no word in them, which therefore have nothing to
/// translate: `''`, `' '`, `'/'`, `'-'`, `'0'`, `'\n'`, `' · '`,
/// `'2026-08-12'`, and pure substitutions such as `'$error'`.
///
/// Exactly equivalent to `--ignore-pattern='^\P{L}*$'`; it exists only so the
/// common case does not have to be spelled as a regular expression. Removed
/// a useful slice of the findings on the corpus it was measured on.
final class NoLetterFilter extends LiteralFilter {
  const NoLetterFilter();

  static final _letter = RegExp(r'\p{L}', unicode: true);

  @override
  bool shouldIgnore(FoundStringLiteral literal) =>
      !_letter.hasMatch(literal.textValue);

  @override
  String get description => 'containing no words';
}

/// Discards literals whose visible text is shorter than [minLength].
///
/// Simple, but blunter than [NoLetterFilter] for the same job: `--min-length=2`
/// removed much the same set on the measured corpus, while also
/// discarding two-letter words. Real copy is often very short —
/// `'OK'`, `'No'`, `'de'`, `'Mo'` — so raising this much above 2 trades away
/// real findings quickly.
final class MinLengthFilter extends LiteralFilter {
  const MinLengthFilter(this.minLength);

  final int minLength;

  @override
  bool shouldIgnore(FoundStringLiteral literal) =>
      literal.textValue.trim().length < minLength;

  @override
  String get description => 'shorter than $minLength characters';
}

/// Discards literals whose visible text matches [pattern].
///
/// The escape hatch for project specific noise — asset extensions, analytics
/// event names, a naming convention for map keys:
/// `--ignore-pattern='^\.[a-z0-9]+$'`.
///
/// Interpolated literals with text between the holes are never matched; see
/// [LiteralFilter.textValueIsWholeLiteral]. Without that rule the obvious
/// patterns are traps: `'^\s*$'` looks like "empty or whitespace" and also
/// discards `' $unit'`.
final class PatternFilter extends LiteralFilter {
  PatternFilter(this.pattern);

  /// `unicode: true` is required for `\p{L}` and friends. Without it Dart
  /// treats them as a literal `p`, so a pattern using them silently matches
  /// nothing at all rather than failing.
  PatternFilter.parse(String source) : pattern = RegExp(source, unicode: true);

  final RegExp pattern;

  @override
  bool shouldIgnore(FoundStringLiteral literal) =>
      pattern.hasMatch(literal.textValue);

  @override
  String get description => 'matching /${pattern.pattern}/';
}

/// Discards literals that are not a phrase of two or more words.
///
/// The most aggressive filter here, and the only one that removed most of the
/// findings where it was measured. It is a triage tool — useful for finding
/// the largest, most obviously user facing strings first — and a poor gate,
/// because single-word labels are real copy: `'Cancel'`, `'Back'` and
/// `'Settings'` go with the noise.
///
/// Do not use this one to decide that a code base is localized.
final class ProseOnlyFilter extends LiteralFilter {
  const ProseOnlyFilter();

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _whitespace = RegExp(r'\s+');

  /// Whether the text has two or more whitespace-separated runs containing a
  /// letter.
  ///
  /// Slightly more generous than "two adjacent words": `'a - b'` and
  /// `'Yes / No'` count, because the letter-bearing runs need not be next to
  /// each other. That errs towards reporting, which is the right direction.
  ///
  /// Split rather than matched. The equivalent pattern, `\p{L}\S*\s+\S*\p{L}`,
  /// backtracks quadratically: on a 200,000 character literal with no
  /// whitespace -- an embedded data URI, say -- it took 41 seconds to decide
  /// there was no match, and this runs once per finding.
  static bool _isProse(String text) {
    var words = 0;
    for (final word in text.split(_whitespace)) {
      if (_letter.hasMatch(word) && ++words >= 2) {
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldIgnore(FoundStringLiteral literal) =>
      !_isProse(literal.textValue.trim());

  @override
  String get description => 'not a phrase of two or more words';
}

extension LiteralFilterList on List<LiteralFilter> {
  /// [found] minus everything any of these filters discards.
  List<FoundStringLiteral> apply(List<FoundStringLiteral> found) => isEmpty
      ? found
      : found
            .where((literal) => !any((filter) => filter.discards(literal)))
            .toList();
}
