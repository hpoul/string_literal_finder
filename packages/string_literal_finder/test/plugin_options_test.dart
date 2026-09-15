import 'dart:async';

import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:logging/logging.dart';
import 'package:string_literal_finder/main.dart';
import 'package:test/test.dart';

/// The plugin locates and parses `analysis_options.yaml` itself, because the
/// rule framework has no API for handing configuration to a rule.
void main() {
  late MemoryResourceProvider resources;
  late LiteralStringRule rule;
  late String root;
  late DateTime clock;

  setUp(() {
    resources = MemoryResourceProvider();
    clock = DateTime(2026);
    rule = LiteralStringRule(now: () => clock);
    root = resources.pathContext.join(
      resources.pathContext.rootPrefix(resources.pathContext.current),
      'project',
    );
  });

  String path(List<String> parts) =>
      resources.pathContext.joinAll([root, ...parts]);

  void writeOptions(String contents) =>
      resources.newFile(path(['analysis_options.yaml']), contents);

  void writeSource() => resources.newFile(path(['lib', 'a.dart']), '');

  const validOptions = '''
string_literal_finder:
  exclude_globs:
    - 'lib/**'
''';

  test('finds an options file above the analyzed file', () {
    writeOptions(validOptions);
    writeSource();
    final options = rule.findAnalysisOptions(
      resources.getFile(path(['lib', 'a.dart'])),
    );
    expect(options, isNotNull);
    expect(options!.isExcluded(path(['lib', 'a.dart'])), isTrue);
  });

  test('returns null when there is none', () {
    writeSource();
    expect(
      rule.findAnalysisOptions(resources.getFile(path(['lib', 'a.dart']))),
      isNull,
    );
  });

  test('a malformed options file does not poison later lookups', () {
    // The negative cache must not record "no options above here" when the
    // read failed -- that would outlive the commit that repairs the file.
    writeOptions('string_literal_finder: [oh: no');
    writeSource();
    final file = resources.getFile(path(['lib', 'a.dart']));
    expect(rule.findAnalysisOptions(file), isNull);

    resources.modifyFile(path(['analysis_options.yaml']), validOptions);
    expect(rule.findAnalysisOptions(file), isNotNull);
  });

  test('editing exclude_globs takes effect without a restart', () {
    writeOptions(validOptions);
    writeSource();
    final file = resources.getFile(path(['lib', 'a.dart']));
    expect(rule.findAnalysisOptions(file)!.excludeGlobs, hasLength(1));

    resources.modifyFile(path(['analysis_options.yaml']), '''
string_literal_finder:
  exclude_globs:
    - 'lib/**'
    - 'tool/**'
''');
    expect(rule.findAnalysisOptions(file)!.excludeGlobs, hasLength(2));
  });

  test('a broken options file is complained about once, not per literal', () {
    // `findAnalysisOptions` runs for every reported literal, so a warning per
    // call would bury the IDE's log in a findings-heavy session.
    writeOptions('string_literal_finder: [oh: no');
    writeSource();
    final file = resources.getFile(path(['lib', 'a.dart']));

    final warnings = <String>[];
    final subscription = Logger.root.onRecord
        .where((record) => record.level >= Level.WARNING)
        .listen((record) => warnings.add(record.message));
    addTearDown(subscription.cancel);

    for (var i = 0; i < 5; i++) {
      expect(rule.findAnalysisOptions(file), isNull);
    }
    return Future<void>.delayed(Duration.zero, () {
      expect(warnings, hasLength(1));
    });
  });

  test('a file that breaks again is complained about again', () {
    // The once-per-file guard must not outlive the repair, or the second
    // breakage goes unreported.
    writeOptions('string_literal_finder: [oh: no');
    writeSource();
    final file = resources.getFile(path(['lib', 'a.dart']));

    final warnings = <String>[];
    final subscription = Logger.root.onRecord
        .where((record) => record.level >= Level.WARNING)
        .listen((record) => warnings.add(record.message));
    addTearDown(subscription.cancel);

    expect(rule.findAnalysisOptions(file), isNull);
    resources.modifyFile(path(['analysis_options.yaml']), validOptions);
    expect(rule.findAnalysisOptions(file), isNotNull);
    resources.modifyFile(
      path(['analysis_options.yaml']),
      'string_literal_finder: [broken again',
    );
    expect(rule.findAnalysisOptions(file), isNull);

    return Future<void>.delayed(Duration.zero, () {
      expect(warnings, hasLength(2));
    });
  });

  test('a deleted then recreated broken file is complained about again', () {
    // The stale-complaint guard has to clear on deletion too, not only on a
    // successful parse, or a file that vanishes and comes back broken is
    // silently un-reported.
    writeOptions('string_literal_finder: [oh: no');
    writeSource();
    final file = resources.getFile(path(['lib', 'a.dart']));

    final warnings = <String>[];
    final subscription = Logger.root.onRecord
        .where((record) => record.level >= Level.WARNING)
        .listen((record) => warnings.add(record.message));
    addTearDown(subscription.cancel);

    expect(rule.findAnalysisOptions(file), isNull);
    resources.deleteFile(path(['analysis_options.yaml']));
    // Past the negative-cache TTL, so the walk actually runs again.
    clock = clock.add(const Duration(seconds: 11));
    expect(rule.findAnalysisOptions(file), isNull);
    writeOptions('string_literal_finder: [broken again');
    clock = clock.add(const Duration(seconds: 11));
    expect(rule.findAnalysisOptions(file), isNull);

    return Future<void>.delayed(Duration.zero, () {
      expect(warnings, hasLength(2));
    });
  });

  test('an options file created later is picked up once the cache expires', () {
    // The negative cache exists to collapse thousands of directory walks into
    // one, not to decide for the lifetime of the analyzer that a project will
    // never gain a config file.
    writeSource();
    final file = resources.getFile(path(['lib', 'a.dart']));
    expect(rule.findAnalysisOptions(file), isNull);

    writeOptions(validOptions);
    expect(
      rule.findAnalysisOptions(file),
      isNull,
      reason: 'still cached as absent',
    );

    clock = clock.add(const Duration(seconds: 11));
    expect(rule.findAnalysisOptions(file), isNotNull);
  });

  test('an options file at the filesystem root is still found', () {
    final rootPrefix = resources.pathContext.rootPrefix(
      resources.pathContext.current,
    );
    resources.newFile(
      resources.pathContext.join(rootPrefix, 'analysis_options.yaml'),
      validOptions,
    );
    resources.newFile(resources.pathContext.join(rootPrefix, 'a.dart'), '');
    expect(
      rule.findAnalysisOptions(
        resources.getFile(resources.pathContext.join(rootPrefix, 'a.dart')),
      ),
      isNotNull,
    );
  });
}
