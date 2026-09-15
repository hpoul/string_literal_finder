## 2.0.0-dev.2

**Analyzer plugins are configured differently now.** Replace

```yaml
analyzer:
  plugins:
    - string_literal_finder
```

with a **top-level** `plugins:` key:

```yaml
plugins:
  string_literal_finder: ^2.0.0
```

The old form only loads the legacy `analyzer_plugin` mechanism, so since
2.0.0-dev.1 it has silently loaded nothing.

### Fixed

* A **hang**: a literal on the last line of a file with no trailing newline
  spun forever while scanning for a `// NON-NLS` comment, because the EOF
  token's `next` is itself. Synchronous, so nothing timed out.
* `@NonNls` could bind to the **wrong parameter** when a named argument was
  written before a positional one, which since Dart 2.17 is legal. In the bad
  direction it silently suppressed a visible string.
* The plugin reported literals nested inside an interpolation twice.
* `@NonNls` on the target of an index access — documented since 0.2.1 — only
  ever worked for a **local** variable. A top-level variable, a field or a
  static is read through its synthetic getter, whose metadata is empty, so the
  annotation was never seen; `this.map[...]` missed for a second reason, its
  target being a `PropertyAccess` rather than a plain name. All of those now
  work. `c.map[...]` and `C.map[...]` deliberately still do not: the
  annotation is on another declaration, and honouring it there is a wider
  claim than the feature makes. The example in the README uses a local, which
  is presumably why this went unnoticed.
* An unresolved annotation hid any `@NonNls` written after it, because
  source_gen stops at the first annotation whose constant is null.
* `export` URIs were reported as literals.
* `--format=json` wrote log records to stdout, corrupting the report.
* Piping to a consumer that stops reading (`... | head`) printed an unhandled
  `Broken pipe` stack trace over its output.
* `--prose-only` discarded phrases whose first word ended in punctuation,
  such as `'Hello, world'`, and its pattern backtracked quadratically -- 41
  seconds to reject a 200,000 character literal with no whitespace. It now
  counts whitespace-separated words containing a letter, which also **reports
  more** than before: `'a - b'`, `'Yes / No'` and `'word 42 word'` were
  discarded and no longer are.
* `@NonNls` on a **named** parameter silently stopped suppressing. analyzer 13
  replaced `NamedExpression` with `NamedArgument`, which is not an `Expression`,
  so the check either skipped the argument or threw and swallowed it.
* Adjacent strings were reported three times — once for `'foo' 'bar'` and once
  for each operand. They are now one finding.
* The analyzer plugin never saw string interpolations: it registered
  `SimpleStringLiteral` and `AdjacentStrings` but not `StringInterpolation`, so
  `'$distance km'` was reported by the CLI and missed in the IDE.
* `exclude_globs` from `analysis_options.yaml` was documented but only ever
  honoured by the plugin; the command line ignored it entirely.

### Added

* `--baseline` / `--write-baseline`: record the literals a project already has
  and fail only on new ones, which is what makes this adoptable on a code base
  with thousands of them. Entries are keyed by literal source text, not by line.
* `--max-literals=<n>`: fail only above a threshold.
* `--format=json`: every finding on stdout, for CI annotations. The previous
  JSON was counts only.
* `--cache-dir`: reuse the analyzer's linked summaries between runs. 12.6s to
  5.4s on a 146-file Flutter `lib/` (16.0s in 1.5.0+1).
* `--dart-sdk`, and SDK auto-detection, so `dart compile exe` produces a
  working binary. That removes JIT warm-up, which dominates once the analysis
  is cached: the same run takes **1.8s**.
* Opt-in noise filters, all off by default: `--ignore-symbols` (literals with
  no word in them, -16%), `--min-length`, `--ignore-pattern` and
  `--prose-only`. See the README for measured trade-offs. No filter, including
  a hand-written `--ignore-pattern`, can discard an interpolated literal that
  has text between the holes — `' $unit'` and
  `'$count $noun${count == 1 ? '' : 's'}'` are safe from all of them.
* `--no-analysis-options` to ignore `analysis_options.yaml` from the CLI.

### Changed

* Requires Dart 3.11 (analyzer 14 does). The constraint said `>=3.3.0`.
* analyzer 14, `analysis_server_plugin` 0.3.20, source_gen 4.3.
* Exit code 2 now means "bad command line"; it used to share exit 1 with
  "literals found", which CI cannot tell apart. Usage and errors go to stderr.
* `StringLiteralFinder.start()` no longer logs every finding at INFO.
* A syntactic pre-pass skips resolving files that cannot contain a finding.
* Removed the unused `recase` dependency and the dead pre-2.0 plugin
  implementation.
* Quick fixes in the IDE: **Wrap with `nonNls()`** (adds the import; declines
  in a constant context or when the annotations package is not a dependency)
  and **Add `// NON-NLS` comment** (placed on the line the literal ends on).

## 2.0.0-dev.1

* Migrate to `analysis_server_plugin` instead of `analyzer_plugin`
  * Still missing: quick fixes!

## 1.5.0+1

* Allow logging_appenders 2.0

## 1.5.0

* Support for analyzer 10.x

## 1.5.0-dev.2

* Migrate to source_gen 4.x, analyzer 9.x

## 1.5.0-dev.1

* Migrate to Element2 https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/doc/element_model_migration_guide.md
  * source_gen 3.0
  * analyzer 7.4

## 1.4.0

* Analyzer 7.0.0
* source_gen 2.0.0

## 1.3.0+2

* Analyzer 6.0.0
* Upgrade dependency constraints.

## 1.3.0+1

* Analyzer 5.0.0

## 1.3.0

* Upgrade to analyzer_plugin 0.11.0
* Support for Enhanced enums of dart 2.17

## 1.1.0+2

* First version of supporting extracting to arb file.

## 1.0.4

* Upgrade dependencies (analyzer 3.4)

## 1.0.3

* Upgrade dependencies (support for analyzer 3.0.0)

## 1.0.2

* Use analyzer >= 2.1.0

## 1.0.1+3

* If a class is annotated with `@NonNls` ignore static field definitions.

## 1.0.1+2

* Ignore strings in default parameters of `@NonNls` annotated parameters.
* Ignore strings in variable definitions annotated with `@NonNls`.

## 1.0.1

* Upgrade dependencies (analyzer 2.0.0, analyzer_plugin 1.7.0)

## 1.0.0+6

* Ignore all strings found in functions and methods annotated with `@NonNls`

## 1.0.0+5

* Remove direct dependency on `meta`
* Add note about `dependency_overrides` for `analyzer` package to `README.md`.

## 1.0.0+4

* Allow configuring analysis_options.yaml additional `exclude_globs`

## 1.0.0

* Allow usage as analyser plugin.

## 0.3.0

* Migrate to null safety.

## 0.2.1

* Ignore index accesses for variables annotated with `@NonNls`.
* Ignore string literals in annotations `@SomeAnnotation('test')`.

## 0.2.0

* Allow exclude suffix configuration.
* Generate a github annotations file for https://github.com/Attest/annotations-action/


## 0.1.1+4

- Improve NonNls annotation checker for named parameters.
- Improve dartdoc.

## 0.1.1+3

- added 'filesWithoutLiterals' to metrics output.

## 0.1.1+2

- allow configuring of excludes, exclude .g.dart files, output statistics at end.

## 0.1.1+1

- Use better command line parsing, implement help command.

## 0.1.1

- Update documentation and made available through `pub global`

## 0.1.0

- Initial version, created by Stagehand
