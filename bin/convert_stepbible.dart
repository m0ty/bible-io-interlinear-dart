import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:bible_io_interlinear/stepbible.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addOption('source-type',
        allowed: ['tagnt', 'tahot'], help: 'Pinned STEPBible source format.')
    ..addMultiOption('input',
        splitCommas: false, help: 'Input file; repeat for multiple files.')
    ..addOption('profile',
        allowed: ['N', 'L+Q+R'],
        help: 'TAGNT: N (Ancient source reading). TAHOT: L+Q+R.')
    ..addOption('reading-policy',
        allowed: ['qere'],
        help: 'Required for TAHOT; variants in notes are not selected.')
    ..addOption('output', help: 'New output dataset directory.')
    ..addOption('dataset-id', help: 'Dataset identity chosen by the producer.')
    ..addOption('dataset-revision',
        help: 'Dataset revision chosen by the producer.')
    ..addOption('source-revision',
        defaultsTo: 'b99716b0cddb648ddb95cc786a197180f2f97d48',
        help: 'Recorded upstream revision; inputs are always hashed.')
    ..addOption('report',
        help: 'Also write the JSON import report to this file.')
    ..addFlag('overwrite',
        negatable: false,
        help: 'Explicitly replace an existing dataset directory.')
    ..addFlag('diagnostic',
        negatable: false,
        help: 'Validate and report only; never write a dataset.');
  Directory? staging;
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln(
          'Prepare STEPBible data (no network access).\n${parser.usage}\n'
          'N is a source reading profile, not an exact published NA27 edition.\n'
          'L+Q+R includes main L/Q and restored R, excluding X additions.');
      return;
    }
    String requiredOption(String name) {
      final value = options.option(name);
      if (value == null || value.isEmpty) {
        throw FormatException('--$name is required');
      }
      return value;
    }

    if (options.rest.isNotEmpty) {
      throw FormatException('Unexpected arguments: ${options.rest.join(' ')}');
    }
    final sourceType = requiredOption('source-type') == 'tagnt'
        ? StepSourceType.tagnt
        : StepSourceType.tahot;
    final inputs = options.multiOption('input');
    if (inputs.isEmpty) {
      throw const FormatException('At least one --input is required');
    }
    final config = StepImportConfig(
        sourceType: sourceType,
        datasetId: requiredOption('dataset-id'),
        datasetRevision: requiredOption('dataset-revision'),
        sourceRevision: requiredOption('source-revision'),
        profile: requiredOption('profile'),
        readingPolicy: options.option('reading-policy'));
    final reportPath = options.option('report');
    final configuredOutput = options.option('output');
    if (reportPath != null) {
      if (configuredOutput != null &&
          _withinDirectory(File(reportPath), Directory(configuredOutput))) {
        throw const FormatException(
          '--report must be outside the output dataset directory; '
          'the dataset already includes import-report.json',
        );
      }
      if (inputs.any((input) =>
          _normalizedFilePath(File(input)) ==
          _normalizedFilePath(File(reportPath)))) {
        throw const FormatException('--report must not replace a source input');
      }
    }
    final sources = <StepSource>[];
    for (final path in inputs) {
      final file = File(path);
      final text = utf8.decode(await file.readAsBytes());
      sources
          .add(StepSource(text: text, sourceFile: file.uri.pathSegments.last));
    }
    final importer = StepImporter();
    if (options.flag('diagnostic')) {
      final report = importer.validateSources(sources: sources, config: config);
      await _report(report.toJson(), options.option('report'));
      if (report.hasErrors) exitCode = 1;
      return;
    }
    final output = Directory(requiredOption('output')).absolute;
    final existingType =
        await FileSystemEntity.type(output.path, followLinks: false);
    if (existingType != FileSystemEntityType.notFound) {
      if (existingType != FileSystemEntityType.directory ||
          !options.flag('overwrite')) {
        throw const FormatException(
            'Output already exists; use --overwrite for an existing dataset directory');
      }
      // Refuse to replace an arbitrary directory, even with --overwrite.
      final old = File('${output.path}${Platform.pathSeparator}manifest.json');
      if (!await old.exists()) {
        throw const FormatException(
            'Overwrite requires an existing dataset manifest');
      }
      const InterlinearJsonCodec().decodeManifest(await old.readAsString());
    }
    final result = importer.importSources(sources: sources, config: config);
    final prepared = PreparedInterlinearDataset.build(
        metadata: result.metadata, chapters: result.chapters);
    await output.parent.create(recursive: true);
    staging = await output.parent.createTemp('.interlinear-');
    for (final entry in prepared.resources.entries) {
      validateResourcePath(entry.key);
      final file = File('${staging.path}${Platform.pathSeparator}${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
    }
    await File('${staging.path}/import-report.json')
        .writeAsString('${jsonEncode(result.report.toJson())}\n');
    // Verify staged bytes through the same reader used by applications.
    final checked = JsonInterlinearDataSource(
        reader: (path) => File('${staging!.path}/$path').readAsBytes());
    final manifest = await checked.loadManifest();
    for (final entry in manifest.chapters) {
      await checked.loadChapter(entry.book, entry.chapter);
    }
    Directory? backup;
    if (await output.exists()) {
      final backupPath =
          '${output.path}.previous-${DateTime.now().microsecondsSinceEpoch}';
      backup = await output.rename(backupPath);
    }
    try {
      await staging.rename(output.path);
      staging = null;
    } catch (_) {
      if (backup != null && !await output.exists()) {
        await backup.rename(output.path);
      }
      rethrow;
    }
    // Preserve replaced data as a sibling backup: no destructive recursive delete.
    if (backup != null) {
      stderr.writeln('Previous dataset retained at ${backup.path}');
    }
    await _report(result.report.toJson(), options.option('report'));
    stdout.writeln('Dataset written to ${output.path}');
  } on StepImportException catch (error) {
    stderr.writeln(error);
    // Parse only to recover an optional report target for a failed strict import.
    String? reportPath;
    try {
      reportPath = parser.parse(arguments).option('report');
    } catch (_) {/* usage error */}
    await _report(error.report.toJson(), reportPath);
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Conversion failed: $error');
    exitCode = 1;
  } finally {
    if (staging != null) {
      stderr.writeln(
          'Incomplete staging directory retained for inspection: ${staging.path}');
    }
  }
}

Future<void> _report(Map<String, Object?> report, String? path) async {
  final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  if (path != null) {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }
  stdout.write(text);
}

bool _withinDirectory(File file, Directory directory) {
  String normalize(String value) =>
      Platform.isWindows ? value.toLowerCase() : value;
  final root = normalize(directory.absolute.uri.normalizePath().toString());
  final target = normalize(file.absolute.uri.normalizePath().toString());
  return target.startsWith(root);
}

String _normalizedFilePath(File file) {
  final value = file.absolute.uri.normalizePath().toString();
  return Platform.isWindows ? value.toLowerCase() : value;
}
