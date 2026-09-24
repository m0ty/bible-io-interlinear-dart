import 'dart:io';

import 'package:bible_io_interlinear/bible_io_interlinear.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr
        .writeln('Usage: dart run tool/verify_dataset.dart DATASET_DIRECTORY');
    exitCode = 64;
    return;
  }
  try {
    final source = JsonInterlinearDataSource(
        reader: (path) => File('${arguments.single}/$path').readAsBytes());
    final manifest = await source.loadManifest();
    final ids = <String>{};
    var tokens = 0;
    for (final resource in manifest.chapters) {
      final chapter = await source.loadChapter(resource.book, resource.chapter);
      for (final token in [
        ...chapter.verses.expand((v) => v.tokens),
        ...chapter.specialEntries.expand((e) => e.tokens)
      ]) {
        if (!ids.add(token.occurrenceId)) {
          throw FormatException(
              'Duplicate occurrence ID ${token.occurrenceId}');
        }
        tokens++;
      }
    }
    stdout.writeln(
        'Verified ${manifest.chapters.length} chapters and $tokens tokens in ${manifest.metadata.datasetId}@${manifest.metadata.datasetRevision}.');
  } catch (error) {
    stderr.writeln('Verification failed: $error');
    exitCode = 1;
  }
}
