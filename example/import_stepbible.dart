import 'dart:io';

import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:bible_io_interlinear/stepbible.dart';

/// Run from this repository's root. Optional arguments: INPUT_FILE OUTPUT_DIR.
Future<void> main(List<String> arguments) async {
  final input =
      arguments.isNotEmpty ? arguments[0] : 'test/fixtures/stepbible/tagnt.txt';
  final output =
      Directory(arguments.length > 1 ? arguments[1] : '.work/example-dataset');
  if (await output.exists()) {
    throw StateError(
        'Output already exists: ${output.path}; choose a new directory.');
  }
  final result = StepImporter().importSources(
    sources: [
      StepSource(
          text: await File(input).readAsString(),
          sourceFile: File(input).uri.pathSegments.last)
    ],
    config: StepImportConfig(
        sourceType: StepSourceType.tagnt,
        datasetId: 'example-tagnt-n',
        datasetRevision: '1',
        sourceRevision: 'b99716b0cddb648ddb95cc786a197180f2f97d48',
        profile: 'N'),
  );
  final prepared = PreparedInterlinearDataset.build(
      metadata: result.metadata, chapters: result.chapters);
  for (final entry in prepared.resources.entries) {
    final file = File('${output.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.value);
  }
  stdout.writeln('Wrote ${result.chapters.length} chapters to ${output.path}');
}
