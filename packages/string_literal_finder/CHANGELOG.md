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
