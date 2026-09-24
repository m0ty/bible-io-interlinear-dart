import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

InterlinearToken token(String id,
        {String surface = 'λόγος', String separator = ' '}) =>
    InterlinearToken(
        occurrenceId: id,
        surface: surface,
        language: 'grc',
        separatorAfter: separator);

InterlinearVerse verse(String label, {List<InterlinearToken>? tokens}) =>
    InterlinearVerse(
      location: BibleLocation.checked(
          book: BibleBookEnum.john,
          chapter: 1,
          verse: VerseLabel.parse(label).startVerse,
          verseLabel: label),
      tokens: tokens ?? [token('john.1.$label.1')],
    );

InterlinearMetadata metadata({Map<BibleBookEnum, List<int>>? coverage}) =>
    InterlinearMetadata(
      datasetId: 'test',
      datasetRevision: 'r1',
      source: 'test-source',
      sourceRevision: 'abc',
      profile: 'test-profile',
      referenceSystem: 'test-numbering',
      originalLanguages: ['grc'],
      glossLanguages: ['en'],
      coverage: coverage ??
          {
            BibleBookEnum.john: [1]
          },
    );

void main() {
  group('immutable linguistic models', () {
    test('defensively copies every nested collection', () {
      final glosses = {'en': 'word'};
      final lexemes = [
        LexicalReference(system: 'STEP-extended', value: 'G3056a')
      ];
      final tags = [MorphologyTag(scheme: 'TAGNT', code: 'N-NSM')];
      final segment = InterlinearSegment(
          text: 'λόγος',
          lexicalReferences: lexemes,
          morphology: tags,
          glosses: glosses);
      final segments = [segment];
      final word = InterlinearToken(
          occurrenceId: '1',
          surface: 'λόγος',
          language: 'grc',
          glosses: glosses,
          segments: segments);
      final words = [word];
      final provenance = {'file': 'source.txt'};
      final sourceVerse = InterlinearVerse(
          location: const BibleLocation(
              book: BibleBookEnum.john, chapter: 1, verse: 1),
          tokens: words,
          provenance: provenance);
      final verses = [sourceVerse];
      final chapter = InterlinearChapter(
          book: BibleBookEnum.john, chapter: 1, verses: verses);
      glosses.clear();
      lexemes.clear();
      tags.clear();
      segments.clear();
      words.clear();
      provenance.clear();
      verses.clear();
      expect(chapter.verses.single.tokens.single.glosses, {'en': 'word'});
      expect(segment.lexicalReferences.single.value, 'G3056a');
      expect(segment.lexicalReferences.single.traditionalStrongs, isNull);
      expect(segment.morphology.single.code, 'N-NSM');
      expect(sourceVerse.provenance, {'file': 'source.txt'});
      expect(() => word.glosses['en'] = 'changed', throwsUnsupportedError);
      expect(() => segment.lexicalReferences.clear(), throwsUnsupportedError);
      expect(() => segment.morphology.clear(), throwsUnsupportedError);
      expect(() => word.segments.clear(), throwsUnsupportedError);
      expect(() => chapter.verses.clear(), throwsUnsupportedError);
      expect(() => sourceVerse.tokens.clear(), throwsUnsupportedError);
    });

    test('coverage is copied, sorted and deeply immutable', () {
      final chapters = [3, 1];
      final coverage = {BibleBookEnum.john: chapters};
      final data = metadata(coverage: coverage);
      chapters.clear();
      coverage.clear();
      expect(data.coverage[BibleBookEnum.john], [1, 3]);
      expect(() => data.coverage.clear(), throwsUnsupportedError);
      expect(() => data.coverage[BibleBookEnum.john]!.clear(),
          throwsUnsupportedError);
      expect(
          () => metadata(coverage: {
                BibleBookEnum.john: [0]
              }),
          throwsArgumentError);
      expect(
          () => metadata(coverage: {
                BibleBookEnum.john: [1, 1]
              }),
          throwsArgumentError);
      expect(() => metadata(coverage: {}), throwsArgumentError);
    });

    test('preserves Unicode and Hebrew logical reading order', () {
      const first = 'בְּרֵאשִׁית';
      const second = 'בָּרָא';
      final source = InterlinearVerse(
        location: const BibleLocation(
            book: BibleBookEnum.genesis, chapter: 1, verse: 1),
        tokens: [
          InterlinearToken(occurrenceId: 'he1', surface: first, language: 'he'),
          InterlinearToken(
              occurrenceId: 'he2',
              surface: second,
              language: 'he',
              separatorAfter: '׃'),
        ],
        textIsReconstructed: true,
      );
      expect(source.tokens.map((word) => word.surface), [first, second]);
      expect(source.reconstructedText, '$first $second׃');
      expect(source.textIsReconstructed, isTrue);
      expect(source.surfaceText, isNull);
      expect(
          InterlinearToken(
                  occurrenceId: 'arc1', surface: 'מַלְכָּא', language: 'arc')
              .language,
          'arc');
    });

    test('retains source-supported segments and optional missing values', () {
      final word = InterlinearToken(
          occurrenceId: 'he1',
          surface: 'בְּרֵאשִׁית',
          language: 'he',
          segments: [
            InterlinearSegment(text: 'בְּ', kind: 'prefix'),
            InterlinearSegment(text: 'רֵאשִׁית')
          ]);
      expect(word.transliteration, isNull);
      expect(word.sourceRecordId, isNull);
      expect(word.segments.map((segment) => segment.text), ['בְּ', 'רֵאשִׁית']);
      expect(word.segments.last.kind, isNull);
      expect(word.segments.last.lemma, isNull);
      expect(word.glosses, isEmpty);
    });

    test('keys require dataset revision as well as occurrence ID', () {
      final key = token('1').keyFor(metadata());
      expect(
          key,
          InterlinearTokenKey(
              datasetId: 'test', datasetRevision: 'r1', occurrenceId: '1'));
      expect(
          key.hashCode,
          InterlinearTokenKey(
                  datasetId: 'test', datasetRevision: 'r1', occurrenceId: '1')
              .hashCode);
      expect(
          key,
          isNot(InterlinearTokenKey(
              datasetId: 'test', datasetRevision: 'r2', occurrenceId: '1')));
      expect(
          () => InterlinearTokenKey(
              datasetId: '', datasetRevision: 'r1', occurrenceId: '1'),
          throwsArgumentError);
    });
  });

  group('chapter source labels', () {
    test('exact spellings persist, normalized lookup and numeric coverage work',
        () {
      final combined = verse('３–４');
      final a = verse('5A');
      final b = verse('5b');
      final cross = verse('6a–7b');
      final chapter = InterlinearChapter(
          book: BibleBookEnum.john,
          chapter: 1,
          verses: [b, cross, combined, a]);
      expect(chapter.verses.map((entry) => entry.location.verseLabel),
          ['３–４', '5A', '5b', '6a–7b']);
      expect(chapter.getVerseByLabel('3-4'), same(combined));
      expect(chapter.getVerse(4), same(combined));
      expect(chapter.getVerseByLabel('5a'), same(a));
      expect(chapter.getVerse(5, subdivision: 'B'), same(b));
      expect(chapter.getVersesByNumber(5), [a, b]);
      expect(() => chapter.getVerse(5),
          throwsA(isA<InterlinearAmbiguousVerseException>()));
      expect(
          chapter.getVerseAt(BibleLocation.checked(
              book: BibleBookEnum.john,
              chapter: 1,
              verse: 7,
              verseLabel: '7a')),
          same(cross));
      expect(() => chapter.getVerseByLabel('4'),
          throwsA(isA<InterlinearVerseNotFoundException>()));
      expect(() => chapter.getVerse(9),
          throwsA(isA<InterlinearVerseNotFoundException>()));
    });

    test('rejects overlapping labels, parent mismatch and duplicate token IDs',
        () {
      expect(
          () => InterlinearChapter(
              book: BibleBookEnum.john,
              chapter: 1,
              verses: [verse('3-4'), verse('4')]),
          throwsArgumentError);
      expect(
          () => InterlinearChapter(
              book: BibleBookEnum.john,
              chapter: 1,
              verses: [verse('5a'), verse('5A')]),
          throwsArgumentError);
      expect(
          () => InterlinearChapter(
              book: BibleBookEnum.john, chapter: 2, verses: [verse('1')]),
          throwsArgumentError);
      expect(
          () =>
              InterlinearChapter(book: BibleBookEnum.john, chapter: 1, verses: [
                verse('1', tokens: [token('dup')]),
                verse('2', tokens: [token('dup')])
              ]),
          throwsArgumentError);
      expect(() => verse('1', tokens: [token('dup'), token('dup')]),
          throwsArgumentError);
      expect(
          () => InterlinearVerse(
              location:
                  const BibleLocation(book: BibleBookEnum.john, chapter: 1),
              tokens: []),
          throwsArgumentError);
    });

    test('special entries remain separate without inventing a verse', () {
      final entry = InterlinearSpecialEntry(
          sourceLabel: '0', kind: 'superscription', tokens: [token('title')]);
      final entries = [entry];
      final chapter = InterlinearChapter(
          book: BibleBookEnum.psalms,
          chapter: 3,
          verses: [],
          specialEntries: entries);
      entries.clear();
      expect(chapter.verses, isEmpty);
      expect(chapter.specialEntries.single.sourceLabel, '0');
      expect(() => chapter.specialEntries.clear(), throwsUnsupportedError);
      expect(() => chapter.getVerse(1),
          throwsA(isA<InterlinearVerseNotFoundException>()));
    });
  });
}
