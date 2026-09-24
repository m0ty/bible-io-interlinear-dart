import 'dart:io';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';

/// Run after import_stepbible.dart. Optional arguments: DATASET USFM CHAPTER LABEL.
Future<void> main(List<String> arguments) async {
  final root = arguments.isNotEmpty ? arguments[0] : '.work/example-dataset';
  final bible = await InterlinearBible.open(JsonInterlinearDataSource(
    reader: (path) => File('$root/$path').readAsBytes(),
  ));
  final book = arguments.length > 1
      ? bibleBookFromUsfmIdentifier(arguments[1])
      : bible.metadata.coverage.keys.first;
  final number = arguments.length > 2
      ? int.parse(arguments[2])
      : bible.metadata.coverage[book]!.first;
  final chapter = await bible.loadChapter(book, number);
  final verse = arguments.length > 3
      ? chapter.getVerseByLabel(arguments[3])
      : chapter.verses.first;
  stdout.writeln(
      '${book.usfmIdentifier} $number:${verse.label.source} (${bible.metadata.profile})');
  for (final token in verse.tokens) {
    stdout.writeln(
        '${token.surface}\t${token.glosses['en'] ?? ''}\t${token.transliteration ?? ''}');
    for (final segment in token.segments) {
      final lexical = segment.lexicalReferences
          .map((r) => '${r.system}:${r.value}')
          .join(', ');
      final morphology =
          segment.morphology.map((m) => '${m.scheme}:${m.code}').join(', ');
      stdout.writeln('  ${segment.text ?? ''}\t$lexical\t$morphology');
    }
  }
}
