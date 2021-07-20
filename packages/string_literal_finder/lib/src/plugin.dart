import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/driver.dart'
    show AnalysisDriver, AnalysisDriverGeneric;
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/driver_based_analysis_context.dart';
import 'package:analyzer_plugin/plugin/plugin.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart' as plugin;
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:string_literal_finder/src/string_literal_finder.dart';
import 'package:yaml/yaml.dart';

final _logger = Logger('string_literal_finder.plugin');

class StringLiteralFinderPlugin extends ServerPlugin {
  StringLiteralFinderPlugin(ResourceProvider provider) : super(provider);

  @override
  List<String> get fileGlobsToAnalyze => <String>['**/*.dart'];

  @override
  String get name => 'String Literal Finder';

  @override
  String get version => '1.0.0';

  var _filesFromSetPriorityFilesRequest = <String>[];

  @override
  AnalysisDriverGeneric createAnalysisDriver(plugin.ContextRoot contextRoot) {
    final rootPath = contextRoot.root;
    final locator =
        ContextLocator(resourceProvider: resourceProvider).locateRoots(
      includedPaths: <String>[rootPath],
      excludedPaths: <String>[
        ...contextRoot.exclude,
      ],
      optionsFile: contextRoot.optionsFile,
    );

    if (locator.isEmpty) {
      final error = StateError('Unexpected empty context');
      channel.sendNotification(plugin.PluginErrorParams(
        true,
        error.message,
        error.stackTrace.toString(),
      ).toNotification());

      throw error;
    }

    final builder = ContextBuilder(
      resourceProvider: resourceProvider,
    );

    final analysisContext = builder.createContext(contextRoot: locator.first);
    // ignore: avoid_as
    final context = analysisContext as DriverBasedAnalysisContext;
    final dartDriver = context.driver;
    try {
      final analysisOptions = _getAnalysisOptions(dartDriver);

      runZonedGuarded(
        () {
          dartDriver.results.listen((analysisResult) {
            _processResult(
              dartDriver,
              analysisOptions,
              analysisResult,
            );
          });
        },
        (Object e, StackTrace stackTrace) {
          channel.sendNotification(
            plugin.PluginErrorParams(
              false,
              'string_literal_finder. Unexpected error: ${e.toString()}',
              stackTrace.toString(),
            ).toNotification(),
          );
        },
      );
    } catch (e, stackTrace) {
      channel.sendNotification(
        plugin.PluginErrorParams(
          false,
          'string_literal_finder. Unexpected error: ${e.toString()}',
          stackTrace.toString(),
        ).toNotification(),
      );
    }

    return dartDriver;
  }

  @override
  Future<plugin.EditGetFixesResult> handleEditGetFixes(
      plugin.EditGetFixesParams parameters) async {
    try {
      final driver = driverForPath(parameters.file) as AnalysisDriver;
      final analysisResult = await driver.getResult2(parameters.file);

      if (analysisResult is! ResolvedUnitResult) {
        return plugin.EditGetFixesResult([]);
      }

      final fixes =
          _check(analysisResult.path!, analysisResult.unit!, analysisResult)
              .where((fix) =>
                  fix.error.location.file == parameters.file &&
                  fix.error.location.offset <= parameters.offset &&
                  parameters.offset <=
                      fix.error.location.offset + fix.error.location.length &&
                  fix.fixes.isNotEmpty)
              .toList();

      return plugin.EditGetFixesResult(fixes);
    } on Exception catch (e, stackTrace) {
      channel.sendNotification(
        plugin.PluginErrorParams(false, e.toString(), stackTrace.toString())
            .toNotification(),
      );

      return plugin.EditGetFixesResult([]);
    }
  }

  void _processResult(
    AnalysisDriver dartDriver,
    AnalysisOptions analysisOptions,
    ResolvedUnitResult analysisResult,
  ) {
    final path = analysisResult.path;
    if (path == null) {
      _logger.warning('No path given for analysisResult.');
      return;
    }

    final unit = analysisResult.unit;
    final isAnalyzed =
        dartDriver.analysisContext?.contextRoot.isAnalyzed(path) ?? false;
    final isExcluded = !isAnalyzed || analysisOptions.isExcluded(path);
    if (unit == null || isExcluded) {
      if (unit == null) {
        _logger.warning('No unit for analysisResult.');
      } else {
        _logger.finer('is not analyzed: $path '
            '(analyzed: $isAnalyzed / isExcluded: $isExcluded)');
      }
      channel.sendNotification(
        plugin.AnalysisErrorsParams(
          path,
          <plugin.AnalysisError>[],
        ).toNotification(),
      );
      return;
    }

    try {
      final errors = _check(path, unit, analysisResult);

      channel.sendNotification(
        plugin.AnalysisErrorsParams(
          path,
          errors.map((e) => e.error).toList(),
        ).toNotification(),
      );
    } catch (e, stackTrace) {
      _logger.severe('Error while analysing file', e, stackTrace);
      channel.sendNotification(
        plugin.PluginErrorParams(
          false,
          e.toString(),
          stackTrace.toString(),
        ).toNotification(),
      );
    }
  }

  List<plugin.AnalysisErrorFixes> _check(
      String path, CompilationUnit unit, ResolvedUnitResult analysisResult) {
    final errors = <plugin.AnalysisErrorFixes>[];

    final visitor = StringLiteralVisitor<dynamic>(
      filePath: path,
      unit: unit,
      foundStringLiteral: (foundStringLiteral) {
        final location = plugin.Location(
          foundStringLiteral.filePath,
          foundStringLiteral.charOffset,
          foundStringLiteral.charLength,
          foundStringLiteral.loc.lineNumber,
          foundStringLiteral.loc.columnNumber,
          foundStringLiteral.locEnd.lineNumber,
          foundStringLiteral.locEnd.columnNumber,
        );

        plugin.PrioritizedSourceChange? fix;
        final content = analysisResult.content;
        if (content != null) {
          final semicolonOffset = content.lastIndexOf(
              ';',
              analysisResult.lineInfo
                  .getOffsetOfLineAfter(foundStringLiteral.charEnd));
          fix = plugin.PrioritizedSourceChange(
            1,
            plugin.SourceChange(
              'Add // NON-NLS',
              edits: [
                plugin.SourceFileEdit(
                  path,
                  analysisResult.libraryElement.source.modificationStamp,
                  edits: [
                    plugin.SourceEdit(semicolonOffset + 1, 0, ' // NON-NLS'),
                  ],
                ),
              ],
            ),
          );
        }

        String stringValue() {
          if (content == null || content.length < foundStringLiteral.charEnd) {
            return '';
          }
          return content
              .substring(
                foundStringLiteral.charOffset,
                foundStringLiteral.charEnd,
              )
              .trim();
        }

        final stringCode = foundStringLiteral.stringValue ?? stringValue();

        errors.add(
          plugin.AnalysisErrorFixes(
              plugin.AnalysisError(
                plugin.AnalysisErrorSeverity('WARNING'),
                plugin.AnalysisErrorType.LINT,
                location,
                'Found string literal: $stringCode',
                'found_string_literal',
                correction:
                    'Externalize string or add nonNls() decorator method, '
                    'or add // NON-NLS to end of line.',
                hasFix: fix != null,
              ),
              fixes: fix == null ? [] : [fix]),
        );
      },
    );
    unit.visitChildren(visitor);
    return errors;
  }

  AnalysisOptions _getAnalysisOptions(AnalysisDriver analysisDriver) {
    final optionsPath = analysisDriver.analysisContext?.contextRoot.optionsFile;
    final exists = optionsPath?.exists ?? false;
    if (!exists || optionsPath == null) {
      _logger.warning('Unable to resolve optionsFile.');
      return AnalysisOptions(excludeGlobs: []);
    }
    return AnalysisOptions.loadFromYaml(optionsPath.readAsStringSync());
  }

  // @override
  // void sendNotificationsForSubscriptions(
  //     Map<String, List<AnalysisService>> subscriptions) {
  //   TODO: implement sendNotificationsForSubscriptions
  // }

  @override
  void contentChanged(String path) {
    super.driverForPath(path)?.addFile(path);
  }

  @override
  Future<plugin.AnalysisSetContextRootsResult> handleAnalysisSetContextRoots(
    plugin.AnalysisSetContextRootsParams parameters,
  ) async {
    final result = await super.handleAnalysisSetContextRoots(parameters);
    // The super-call adds files to the driver, so we need to prioritize them so they get analyzed.
    _updatePriorityFiles();

    return result;
  }

  @override
  Future<plugin.AnalysisSetPriorityFilesResult> handleAnalysisSetPriorityFiles(
    plugin.AnalysisSetPriorityFilesParams parameters,
  ) async {
    _filesFromSetPriorityFilesRequest = parameters.files;
    _updatePriorityFiles();

    return plugin.AnalysisSetPriorityFilesResult();
  }

  // https://github.com/dart-code-checker/dart-code-metrics/blob/e8e14d44b940a5b29d33a782432f853ee42ac7a0/lib/src/analyzer_plugin/analyzer_plugin.dart#L274
  /// AnalysisDriver doesn't fully resolve files that are added via `addFile`; they need to be either explicitly requested
  /// via `getResult`/etc, or added to `priorityFiles`.
  ///
  /// This method updates `priorityFiles` on the driver to include:
  ///
  /// - Any files prioritized by the analysis server via [handleAnalysisSetPriorityFiles]
  /// - All other files the driver has been told to analyze via addFile (in [ServerPlugin.handleAnalysisSetContextRoots])
  ///
  /// As a result, [_processResult] will get called with resolved units, and thus all of our diagnostics
  /// will get run on all files in the repo instead of only the currently open/edited ones!
  void _updatePriorityFiles() {
    final filesToFullyResolve = {
      // Ensure these go first, since they're actually considered priority; ...
      ..._filesFromSetPriorityFilesRequest,

      // ... all other files need to be analyzed, but don't trump priority
      for (final driver2 in driverMap.values)
        ...(driver2 as AnalysisDriver).addedFiles,
    };

    // From ServerPlugin.handleAnalysisSetPriorityFiles
    final filesByDriver = <AnalysisDriverGeneric, List<String>>{};
    for (final file in filesToFullyResolve) {
      final contextRoot = contextRootContaining(file);
      if (contextRoot != null) {
        // TODO(dkrutskikh): Which driver should we use if there is no context root?
        final driver = driverMap[contextRoot];
        if (driver != null) {
          filesByDriver.putIfAbsent(driver, () => <String>[]).add(file);
        }
      }
    }
    filesByDriver.forEach((driver, files) {
      driver.priorityFiles = files;
    });
  }
}

class AnalysisOptions {
  AnalysisOptions({required this.excludeGlobs});

  static AnalysisOptions loadFromYaml(String yamlSource) {
    final yaml =
        json.decode(json.encode(loadYaml(yamlSource))) as Map<String, dynamic>;
    final options = yaml['string_literal_finder'] as Map<String, dynamic>?;
    final excludeGlobs = options?['exclude_globs'] as List<dynamic>?;
    if (options == null || excludeGlobs == null) {
      return AnalysisOptions(excludeGlobs: []);
    }
    return AnalysisOptions(
      excludeGlobs: excludeGlobs.cast<String>().map((e) => Glob(e)).toList(),
    );
  }

  final List<Glob> excludeGlobs;

  bool isExcluded(String path) {
    return excludeGlobs.any((glob) => glob.matches(path));
  }
}
