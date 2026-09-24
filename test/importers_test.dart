import 'dart:convert';
import 'dart:io';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:bible_io_interlinear/stepbible.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const revision = 'b99716b0cddb648ddb95cc786a197180f2f97d48';
final greek = File('test/fixtures/stepbible/tagnt.txt').readAsStringSync();
final hebrew = File('test/fixtures/stepbible/tahot.txt').readAsStringSync();

StepImportConfig config(StepSourceType type) => StepImportConfig(
      sourceType: type,
      datasetId: 'fixture-${type.name}',
      datasetRevision: '1',
      sourceRevision: revision,
      profile: type == StepSourceType.tagnt ? 'N' : 'L+Q+R',
      readingPolicy: type == StepSourceType.tahot ? 'qere' : null,
    );

StepImportResult run(String text,
        {StepSourceType type = StepSourceType.tagnt}) =>
    StepImporter().importSources(
        sources: [StepSource(text: text, sourceFile: 'fixture.txt')],
        config: config(type));

String row(String text, String id) => const LineSplitter()
    .convert(text)
    .firstWhere((line) => line.startsWith('$id\t'));

String mutate(String original, Map<int, String> fields) {
  final parts = original.split('\t');
  for (final field in fields.entries) {
    parts[field.key] = field.value;
  }
  return parts.join('\t');
}

InterlinearVerse verse(
        StepImportResult result, BibleBookEnum book, int chapter, int number) =>
    result.chapters
        .singleWhere((c) => c.book == book && c.chapter == chapter)
        .getVerse(number);

Iterable<InterlinearToken> tokens(StepImportResult result) sync* {
  for (final chapter in result.chapters) {
    for (final verse in chapter.verses) {
      yield* verse.tokens;
    }
    for (final entry in chapter.specialEntries) {
      yield* entry.tokens;
    }
  }
}

void main() {
  late StepImportResult tagnt;
  late StepImportResult tahot;
  setUpAll(() {
    tagnt = run(greek);
    tahot = run(hebrew, type: StepSourceType.tahot);
  });

  test('authentic fixture bytes have committed provenance and hashes', () {
    final manifest = jsonDecode(
            File('test/fixtures/stepbible/provenance.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(manifest['revision'], revision);
    expect(manifest['license'], 'CC BY 4.0');
    for (final name in ['tagnt.txt', 'tahot.txt']) {
      final bytes = File('test/fixtures/stepbible/$name').readAsBytesSync();
      expect(sha256.convert(bytes).toString(),
          manifest['fixtures'][name]['sha256']);
    }
  });

  test(
      'Greek surface, supplied transliteration, glosses and extended identifiers survive',
      () {
    final first = verse(tagnt, BibleBookEnum.matthew, 1, 1);
    expect(first.tokens.map((t) => t.surface).toList(), [
      'Βίβλος',
      'γενέσεως',
      'Ἰησοῦ',
      'Χριστοῦ',
      'υἱοῦ',
      'Δαυὶδ',
      'υἱοῦ',
      'Ἀβραάμ.',
    ]);
    expect(first.tokens.first.transliteration, 'Biblos');
    expect(first.tokens.first.glosses, {'en': '[The] book', 'es': 'Libro'});
    expect(first.tokens[2].segments.single.lexicalReferences.single.value,
        'G2424G');
    expect(
        first.tokens[2].segments.single.lexicalReferences.single
            .traditionalStrongs,
        isNull);
    expect(first.textIsReconstructed, isTrue);
    expect(first.surfaceText, isNull);
    expect(tagnt.metadata.sourceRevision, revision);
    expect(tagnt.metadata.profile, 'N');
    expect(tagnt.metadata.referenceSystem, 'STEPBible-NRSV');
  });

  test(
      'N selection excludes traditional word and alternate ending even when editions say NA27',
      () {
    final mark = verse(tagnt, BibleBookEnum.mark, 16, 8);
    expect(mark.tokens, hasLength(18));
    expect(mark.tokens.last.surface, 'γάρ.¶');
    expect(mark.tokens.any((t) => t.surface == 'ταχὺ'), isFalse);
    expect(mark.tokens.any((t) => t.sourceRecordId!.contains('#20=')), isFalse);
    expect(tagnt.report.parsedRecords, 156);
    expect(tagnt.report.selectedRecords, 117);
    expect(tagnt.report.excludedRecords, 39);
  });

  test(
      'N profile preserves logical source order and exposes edition-order limitations',
      () {
    final mark = verse(tagnt, BibleBookEnum.mark, 1, 13);
    expect(mark.tokens[5].surface, 'τεσσεράκοντα');
    expect(mark.tokens[6].surface, 'ἡμέρας');
    final warning = tagnt.report.diagnostics
        .firstWhere((d) => d.recordId == 'Mrk.1.13#07=NKO');
    expect(warning.code, 'edition_order_annotation');
    expect(warning.severity, ImportSeverity.warning);
    expect(warning.field, 'editions');
    expect(warning.lineNumber, greaterThan(0));
    expect(mark.provenance['editionAnnotations'], contains('NA27»1'));
    expect(
        () => StepImportConfig(
            sourceType: StepSourceType.tagnt,
            datasetId: 'x',
            datasetRevision: '1',
            sourceRevision: revision,
            profile: 'NA27'),
        throwsArgumentError);
  });

  test(
      'multiple Greek analyses do not fabricate surface boundaries; five-digit IDs survive',
      () {
    final compound =
        tokens(tagnt).singleWhere((t) => t.sourceRecordId == 'Act.4.25#14=NKO');
    expect(compound.segments, hasLength(1));
    expect(compound.segments.single.kind, 'whole-word');
    expect(compound.segments.single.lexicalReferences.map((r) => r.value),
        ['G2443', 'G5101']);
    final extended = tokens(tagnt)
        .singleWhere((t) => t.sourceRecordId == 'Act.24.12#12=N(k)O');
    expect(extended.segments.single.lexicalReferences.single.value, 'G20447');
  });

  test(
      'TAHOT Hebrew segments preserve exact Unicode, root, morphology and punctuation',
      () {
    final genesis = verse(tahot, BibleBookEnum.genesis, 1, 1);
    final first = genesis.tokens.first;
    expect(first.surface, 'בְּרֵאשִׁ֖ית');
    expect(first.sourceText, 'בְּ/רֵאשִׁ֖ית');
    expect(first.language, 'hbo');
    expect(first.segments.map((s) => s.text), ['בְּ', 'רֵאשִׁ֖ית']);
    expect(first.segments[1].kind, 'root');
    expect(first.segments[1].lexicalReferences.single.value, 'H7225G');
    expect(first.segments[1].morphology.single.code, 'Ncfsa');
    expect(first.segments[1].morphology.single.scheme, 'STEPBible-TAHOT');
    expect(genesis.tokens.last.surface, 'הָאָֽרֶץ׃');
    expect(genesis.tokens.last.segments.last.kind, 'punctuation');
  });

  test(
      'qere chooses main forms, includes R, excludes X and reports explicit omissions',
      () {
    expect(tahot.metadata.profile, 'L+Q+R');
    expect(tahot.metadata.readingPolicy, 'qere');
    final qere = tokens(tahot)
        .singleWhere((t) => t.sourceRecordId == 'Gen.8.17#14=Q(k)');
    expect(qere.surface, 'הַיְצֵ֣א');
    expect(tokens(tahot).any((t) => t.sourceRecordId!.endsWith('=X')), isFalse);
    expect(verse(tahot, BibleBookEnum.joshua, 21, 36).tokens, hasLength(10));
    expect(tokens(tahot).any((t) => t.sourceRecordId == 'Jdg.16.25#02=Q(K)'),
        isFalse);
    final omission = tahot.report.diagnostics.single;
    expect(omission.code, 'qere_omission');
    expect(omission.severity, ImportSeverity.info);
    expect(omission.recordId, 'Jdg.16.25#02=Q(K)');
    expect(tahot.report.excludedRecords, 3);
  });

  test('Hebrew and Aramaic remain distinct within one verse', () {
    final daniel = verse(tahot, BibleBookEnum.daniel, 2, 4);
    expect(daniel.tokens.take(4).map((t) => t.language), everyElement('hbo'));
    expect(daniel.tokens.skip(4).map((t) => t.language), everyElement('arc'));
    expect(tahot.metadata.originalLanguages, ['arc', 'hbo']);
    expect(daniel.tokens[4].segments.first.morphology.single.code, 'ANcbsd');
  });

  test(
      'double slash word boundary and in-word punctuation do not create empty segments',
      () {
    final doubleWord = tokens(tahot)
        .singleWhere((t) => t.sourceRecordId == 'Gen.30.11#03=Q(K)');
    expect(doubleWord.surface, 'בָּ֣א גָ֑ד');
    expect(doubleWord.segments.map((s) => s.text), ['בָּ֣א', 'גָ֑ד']);
    final exodus =
        tokens(tahot).singleWhere((t) => t.sourceRecordId == 'Exo.4.2#04=Q(K)');
    expect(exodus.surface, 'מַה־זֶּ֣ה');
    expect(exodus.segments[1].kind, 'punctuation');
    expect(exodus.segments[1].morphology, isEmpty);
    expect(
        tokens(tahot).firstWhere((t) => t.surface.endsWith('־')).separatorAfter,
        '');
  });

  test(
      'documented Kedorlaomer exception preserves complete root around internal maqaf',
      () {
    final name = tokens(tahot)
        .singleWhere((t) => t.sourceRecordId == 'Gen.14.17#09=LBH(A)');
    expect(name.surface, 'כְּדָרְ־לָעֹ֔מֶר');
    expect(name.segments, hasLength(1));
    expect(name.segments.single.kind, 'root');
    expect(name.segments.single.text, name.surface);
    expect(name.segments.single.lexicalReferences.map((r) => r.value),
        ['H3540', 'H9014']);
  });

  test(
      'verse zero is an explicit superscription with its original alternate reference',
      () {
    final psalm =
        tahot.chapters.singleWhere((c) => c.book == BibleBookEnum.psalms);
    expect(psalm.verses, isEmpty);
    expect(psalm.specialEntries.single.kind, 'superscription');
    expect(psalm.specialEntries.single.sourceLabel, 'Psa.3.0(3.1)');
    expect(psalm.specialEntries.single.tokens.first.sourceRecordId,
        'Psa.3.0(3.1)#01=L');
  });

  test(
      'BOM, CRLF, CR, UTF-8 bytes, headers and empty optional cells are handled',
      () {
    for (final eol in ['\r\n', '\r']) {
      final source = StepSource.fromBytes(
          bytes: utf8.encode('\uFEFF${greek.replaceAll('\n', eol)}'),
          sourceFile: 'encoded.txt');
      final result = StepImporter().importSources(
          sources: [source], config: config(StepSourceType.tagnt));
      expect(tokens(result).map((t) => t.surface),
          tokens(tagnt).map((t) => t.surface));
    }
    // Deliberately synthetic absence of optional contextual translations.
    final missing = run(mutate(row(greek, 'Mat.1.1#01=NKO'), {2: '', 8: ''}));
    expect(tokens(missing).single.glosses, isEmpty);
  });

  test('synthetic combined/subdivided labels pass through Bible-IO labels', () {
    final base = row(greek, 'Mat.1.1#01=NKO');
    final result = run([
      mutate(base, {0: 'Mat.1.2-3#01=NKO'}),
      mutate(base, {0: 'Mat.1.4a#01=NKO'}),
      mutate(base, {0: 'Mat.1.4b#01=NKO'}),
    ].join('\n'));
    expect(result.chapters.single.verses.map((v) => v.location.verseLabel),
        ['2-3', '4a', '4b']);
    expect(result.chapters.single.getVerse(3).location.verseLabel, '2-3');
  });

  test(
      'synthetic malformed and excluded rows collect structured errors and no data',
      () {
    final base = row(greek, 'Mat.1.1#01=NKO');
    final broken = [
      'broken leading record\tgarbage',
      mutate(base, {0: 'Mat.1.1#01=NKO', 3: 'G12=bad!'}),
      mutate(base, {0: 'Mat.1.2#01=O', 1: 'missing transliteration'}),
      mutate(base, {0: 'Mat.1.1000#01=NKO'}),
      mutate(base, {0: 'Qqq.1.1#01=NKO'}),
      mutate(base, {0: 'Mat.1.3#01=Z'}),
    ].join('\n');
    final report = StepImporter().validateSources(
        sources: [StepSource(text: broken, sourceFile: 'synthetic.txt')],
        config: config(StepSourceType.tagnt));
    expect(report.hasErrors, isTrue);
    expect(report.tokenCount, 0);
    expect(
        report.diagnostics.map((d) => d.code),
        containsAll([
          'invalid_record_reference',
          'invalid_lexical_morphology',
          'invalid_greek',
          'invalid_verse_label',
          'unsupported_book',
          'unsupported_word_type',
        ]));
    final lexical = report.diagnostics
        .firstWhere((d) => d.code == 'invalid_lexical_morphology');
    expect(lexical.sourceFile, 'synthetic.txt');
    expect(lexical.lineNumber, 2);
    expect(lexical.field, 'dStrongs = Grammar');
    expect(() => run(broken), throwsA(isA<StepImportException>()));
  });

  test('synthetic malformed Hebrew analyses cannot be silently lost', () {
    final base = row(hebrew, 'Gen.30.11#03=Q(K)');
    for (final broken in [
      mutate(base, {4: '{H0935G}/H9999/{H1409}'}),
      mutate(base, {4: 'garbage//{H1409}'}),
      mutate(base, {4: '{H0935G//{H1409}'}),
      mutate(base, {5: 'HVqp3ms/Ncmsa'}),
    ]) {
      expect(() => run(broken, type: StepSourceType.tahot),
          throwsA(isA<StepImportException>()));
    }
  });

  test(
      'duplicate IDs, duplicate source names and reversed rows fail before publication',
      () {
    final first = row(greek, 'Mat.1.1#01=NKO');
    final second = row(greek, 'Mat.1.1#02=NKO');
    expect(() => run('$first\n$first'), throwsA(isA<StepImportException>()));
    expect(() => run('$second\n$first'), throwsA(isA<StepImportException>()));
    expect(
        () => StepImporter().importSources(sources: [
              StepSource(text: first, sourceFile: 'same'),
              StepSource(text: second, sourceFile: 'same'),
            ], config: config(StepSourceType.tagnt)),
        throwsA(isA<StepImportException>()));
  });

  test('synthetic unbalanced edition markers are rejected', () {
    expect(
        () => run(mutate(row(greek, 'Mat.1.1#01=NKO'), {0: 'Mat.1.1#01=N)'})),
        throwsA(isA<StepImportException>()));
    expect(
        () => run(mutate(row(hebrew, 'Gen.1.1#01=L'), {0: 'Gen.1.1#01=L(K'}),
            type: StepSourceType.tahot),
        throwsA(isA<StepImportException>()));
  });
}
