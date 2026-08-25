import 'package:string_literal_finder/src/string_literal_finder.dart';

/// An additional, opt-in rule for discarding findings which are unlikely to be
/// user visible copy.
///
/// None of these are enabled by default. Each of them can hide a real
/// untranslated string, and a tool that silently drops findings is worse than a
/// noisy one — so the choice of how much to hide belongs to the project, not to
/// the tool.
///
/// The percentages in the subclass documentation were measured over a real
/// Flutter application (2724 findings, 1357 of them under `lib/ui`), not
/// invented. Reproduce them on your own code with `--format=json`.
sealed class LiteralFilter {
  const LiteralFilter();

  /// Whether [literal] should be discarded.
  bool shouldIgnore(FoundStringLiteral literal);

  /// Human readable description, reported in the run summary so it is obvious
  /// which filters were active when a number was produced.
  String get description;
}

/// Discards literals with no word in them, which therefore have nothing to
/// translate.
///
/// Two shapes qualify:
///
///   * a plain literal containing no letter — `''`, `' '`, `'/'`, `'-'`,
///     `'0'`, `'\n'`, `' · '`, `'2026-08-12'`;
///   * an interpolation with no literal text at all — `'$error'`, `'$url'`,
///     `'${entry.key}'` — which is pure substitution.
///
/// It removed 16% of findings on the measured corpus. This is the filter to
/// reach for first.
///
/// **An interpolation with letterless text between the holes is deliberately
/// kept**, even though it also has no word in it. `' $unit'`, `'$a – $b'`,
/// `'${w} × ${h}'` and `'$count $noun${count == 1 ? '' : 's'}'` all look like
/// punctuation by this measure, and all of them are templates whose separator,
/// ordering or pluralisation can differ by locale. Those are among the most
/// valuable things this tool finds, so they are not filtered.
final class NoLetterFilter extends LiteralFilter {
  const NoLetterFilter();

  static final _letter = RegExp(r'\p{L}', unicode: true);

  @override
  bool shouldIgnore(FoundStringLiteral literal) {
    if (_letter.hasMatch(literal.textValue)) {
      return false;
    }
    return !literal.isInterpolated || literal.textValue.isEmpty;
  }

  @override
  String get description => 'containing no words';
}

/// Discards literals whose visible text is shorter than [minLength].
///
/// Simple, but blunter than [NoLetterFilter] for the same job: `--min-length=2`
/// removed 20% of findings on the measured corpus, almost exactly the same set,
/// while also discarding two-letter words. Real copy is often very short —
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
final class PatternFilter extends LiteralFilter {
  PatternFilter(this.pattern);

  PatternFilter.parse(String source) : pattern = RegExp(source);

  final RegExp pattern;

  @override
  bool shouldIgnore(FoundStringLiteral literal) =>
      pattern.hasMatch(literal.textValue);

  @override
  String get description => 'matching /${pattern.pattern}/';
}

/// Discards literals that are not a phrase of two or more words.
///
/// The most aggressive filter here: it removed 67% of findings on the measured
/// corpus. It is a triage tool — useful for finding the largest, most obviously
/// user facing strings first — and a poor gate, because single-word labels are
/// real copy. On the measured corpus it discarded `'Cancel'`, `'Back'`,
/// `'Hidden'`, `'Rides'` and `'Camera'` along with the noise.
///
/// Do not use this one to decide that a code base is localized.
final class ProseOnlyFilter extends LiteralFilter {
  const ProseOnlyFilter();

  /// Two letters separated by a space, i.e. at least two words.
  static final _prose = RegExp(r'\p{L}[ \t]+\p{L}', unicode: true);

  @override
  bool shouldIgnore(FoundStringLiteral literal) =>
      !_prose.hasMatch(literal.textValue.trim());

  @override
  String get description => 'not a phrase of two or more words';
}

extension LiteralFilterList on List<LiteralFilter> {
  /// [found] minus everything any of these filters discards.
  List<FoundStringLiteral> apply(List<FoundStringLiteral> found) => isEmpty
      ? found
      : found
            .where((literal) => !any((filter) => filter.shouldIgnore(literal)))
            .toList();
}
