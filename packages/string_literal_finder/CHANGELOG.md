## 2.0.0-dev.2

**Breaking:** the plugin is enabled with a **top-level** `plugins:` key now.
The old `analyzer: plugins:` form has loaded nothing since 2.0.0-dev.1.

```yaml
plugins:
  string_literal_finder: ^2.0.0
```

Requires Dart 3.11. Exit code 2 now means "bad command line" (it used to share
exit 1 with "literals found").

### Added

* `--baseline` / `--write-baseline` — fail only on *new* literals, so this can
  be adopted on a code base that already has thousands.
* `--format=json` — every finding on stdout, not just counts.
* `--cache-dir` — reuse the analyzer's summaries between runs: 16.0s → 5.4s.
* `--dart-sdk` plus auto-detection, so `dart compile exe` works: **1.8s**.
* Quick fixes in the IDE — wrap with `nonNls()`, or add `// NON-NLS`.
* Opt-in noise filters, all off by default: `--ignore-symbols` (−16%),
  `--min-length`, `--ignore-pattern`, `--prose-only` (−67%, but drops real
  labels). See the README for the trade-offs.
* `--max-literals`, `--no-analysis-options`.

### Fixed

* `exclude_globs` was ignored by the CLI — it only ever worked in the IDE.
* The plugin never reported interpolations such as `'$distance km'`.
* Adjacent strings (`'foo' 'bar'`) were reported three times.
* `@NonNls` stopped suppressing named parameters under analyzer 13, and could
  bind to the wrong parameter when a named argument came first.
* `@NonNls` on an index target only worked for local variables; top-level
  variables, fields, statics and `this.map[...]` now work too. `c.map[...]`
  still does not, deliberately.
* An unresolved annotation hid any `@NonNls` written after it.
* A hang on a literal in the last line of a file with no trailing newline.
* `export` URIs were reported as literals.
* `--format=json` wrote log records to stdout, corrupting the report.
* Piping to `head` printed a `Broken pipe` stack trace.

### Changed

* analyzer 14, `analysis_server_plugin` 0.3.20, source_gen 4.3.
* `--prose-only` reports a little more than before.
* Dropped the dead pre-2.0 plugin implementation and the `recase` dependency.

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
