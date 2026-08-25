import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:string_literal_finder/main.dart';
import 'package:test/test.dart';

/// The plugin locates and parses `analysis_options.yaml` itself, because the
/// rule framework has no API for handing configuration to a rule.
void main() {
  late MemoryResourceProvider resources;
  late LiteralStringRule rule;
  late String root;

  setUp(() {
    resources = MemoryResourceProvider();
    rule = LiteralStringRule();
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
