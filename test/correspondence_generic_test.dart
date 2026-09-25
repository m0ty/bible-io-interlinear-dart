import 'dart:convert';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

const _codec = CorrespondenceJsonCodec();
final _editionHash = resourceSha256(utf8.encode('An independent edition'));
final _invalid = throwsA(isA<InterlinearDataException>());

PreparedInterlinearDataset _dataset(String id, BibleBookEnum book,
    {required String revision,
    required String profile,
    required String referenceSystem,
    String language = 'heb'}) {
  InterlinearToken token(String name) => InterlinearToken(
      occurrenceId: '$id:$name', surface: name, language: language);
  return PreparedInterlinearDataset.build(
    metadata: InterlinearMetadata(
      datasetId: id,
      datasetRevision: 'prepared-$revision',
      source: 'Independent provider $id',
      sourceRevision: revision,
      profile: profile,
      referenceSystem: referenceSystem,
      originalLanguages: [language],
      glossLanguages: const [],
      coverage: {
        book: [1],
      },
    ),
    chapters: [
      InterlinearChapter(
        book: book,
        chapter: 1,
        verses: [
          InterlinearVerse(
            location: BibleLocation.checked(book: book, chapter: 1, verse: 1),
            tokens: [token('one'), token('two')],
          ),
        ],
        specialEntries: [
          InterlinearSpecialEntry(
              sourceLabel: 'heading',
              kind: 'heading',
              tokens: [token('title')]),
        ],
      ),
    ],
  );
}

CorrespondenceDatasetBinding _binding(PreparedInterlinearDataset dataset) {
  final metadata = dataset.manifest.metadata;
  return CorrespondenceDatasetBinding(
    datasetId: metadata.datasetId,
    datasetRevision: metadata.datasetRevision,
    sourceRevision: metadata.sourceRevision,
    profile: metadata.profile,
    referenceSystem: metadata.referenceSystem,
    manifestSha256: resourceSha256(dataset.resources['manifest.json']!),
  );
}

InterlinearSourceSelection _selection(String id,
        {BibleBookEnum book = BibleBookEnum.genesis}) =>
    InterlinearSourceSelection(
        datasetId: id, book: book, chapter: 1, verseLabel: '1');

CorrespondenceIndex _index({
  Map<String, CorrespondenceDatasetBinding>? datasets,
  Map<String, CorrespondenceEntry>? entries,
  Map<String, String> provenance = const {},
}) =>
    CorrespondenceIndex(
      sourceEdition: 'independent-edition',
      sourceAssetSha256: _editionHash,
      sourceReferenceSystem: 'publisher-numbering',
      datasets: datasets ??
          {
            'original': _binding(_dataset('original', BibleBookEnum.genesis,
                revision: '2026-01',
                profile: 'reading-a',
                referenceSystem: 'archive-numbering')),
          },
      entries: entries ??
          {
            'GEN.1.1': CorrespondenceEntry(
                datasetId: 'original',
                status: VerseMappingStatus.matched,
                sources: [_selection('original')]),
          },
      provenance: provenance,
    );

Map<String, dynamic> _document() =>
    jsonDecode(_codec.encode(_index())) as Map<String, dynamic>;

void main() {
  test(
      'independent providers resolve different revisions and reference systems',
      () async {
    final first = _dataset('archive-a', BibleBookEnum.genesis,
        revision: '2026-01',
        profile: 'reading-a',
        referenceSystem: 'archive-numbering');
    final second = _dataset('publisher-b', BibleBookEnum.matthew,
        revision: 'release-7',
        profile: 'critical',
        referenceSystem: 'publisher-native',
        language: 'grc');
    final prepared = {'archive-a': first, 'publisher-b': second};
    final index = _index(
      datasets: prepared.map((key, value) => MapEntry(key, _binding(value))),
      entries: {
        'GEN.1.7': CorrespondenceEntry(
          datasetId: 'archive-a',
          status: VerseMappingStatus.matched,
          sources: [
            InterlinearSourceSelection(
                datasetId: 'archive-a',
                book: BibleBookEnum.genesis,
                chapter: 1,
                specialEntryLabel: 'heading'),
            InterlinearSourceSelection(
                datasetId: 'archive-a',
                book: BibleBookEnum.genesis,
                chapter: 1,
                verseLabel: '1',
                occurrenceIds: ['archive-a:two', 'archive-a:one']),
          ],
        ),
        'MAT.1.9': CorrespondenceEntry(
            datasetId: 'publisher-b',
            status: VerseMappingStatus.partial,
            note: 'One surviving source entry',
            sources: [_selection('publisher-b', book: BibleBookEnum.matthew)]),
      },
      provenance: {'reviewedBy': 'An independent editor', 'method': 'manual'},
    );
    expect(index.sourceRevision, isNull);
    expect(index.targetReferenceSystem, isNull);
    index.validateSourceEdition(
        editionId: 'independent-edition',
        referenceSystem: 'publisher-numbering',
        assetSha256: _editionHash);
    final resolver = CorrespondenceResolver(
      index: _codec.decode(_codec.encode(index)),
      openDataset: (binding) async {
        final dataset = prepared[binding.datasetId]!;
        return CorrespondenceDataset.open(
          manifestBytes: dataset.resources['manifest.json']!,
          reader: (path) async => dataset.resources[path]!,
        );
      },
    );
    final a = await resolver.resolve(BibleLocation.checked(
        book: BibleBookEnum.genesis, chapter: 1, verse: 7));
    expect(a.tokens.map((token) => token.occurrenceId),
        ['archive-a:title', 'archive-a:two', 'archive-a:one']);
    expect(a.metadata!.referenceSystem, 'archive-numbering');
    final b = await resolver.resolve(BibleLocation.checked(
        book: BibleBookEnum.matthew, chapter: 1, verse: 9));
    expect(b.tokens.map((token) => token.occurrenceId),
        ['publisher-b:one', 'publisher-b:two']);
    expect(b.metadata!.referenceSystem, 'publisher-native');
    expect(b.mapping.status, VerseMappingStatus.partial);
    expect(index.coverage, {
      'books': 2,
      'chapters': 2,
      'verses': 2,
      'matched': 1,
      'partial': 1,
      'unmapped': 0,
      'ambiguous': 0,
    });
  });

  test('schema 2 encoding is deterministic and preserves selection order', () {
    final entries = {
      'GEN.1.2': CorrespondenceEntry(
          datasetId: 'original',
          status: VerseMappingStatus.unmapped,
          note: 'Absent'),
      'GEN.1.1': CorrespondenceEntry(
        datasetId: 'original',
        status: VerseMappingStatus.matched,
        sources: [
          InterlinearSourceSelection(
              datasetId: 'original',
              book: BibleBookEnum.genesis,
              chapter: 1,
              verseLabel: '1',
              occurrenceIds: ['b', 'a']),
        ],
      ),
    };
    final first =
        _index(entries: entries, provenance: {'z': 'last', 'a': 'first'});
    final reordered = _index(
      entries: Map.fromEntries(entries.entries.toList().reversed),
      provenance: {'a': 'first', 'z': 'last'},
    );
    final encoded = _codec.encode(first);
    expect(_codec.encode(reordered), encoded);
    expect(jsonDecode(encoded)['schemaVersion'], 2);
    expect(jsonDecode(encoded).containsKey('coverage'), isFalse);
    final decoded = _codec.decode(encoded);
    expect(_codec.encode(decoded), encoded);
    expect(
        decoded.entries['GEN.1.1']!.sources.single.occurrenceIds, ['b', 'a']);
    expect(decoded.unavailable, ['GEN.1.2']);
    expect(decoded.coverage['unmapped'], 1);
    expect(decoded.sourceRevision, '2026-01');
    expect(decoded.targetReferenceSystem, 'archive-numbering');
  });

  test('public constructors freeze collections and validate identity', () {
    final sources = [_selection('original')];
    final entry = CorrespondenceEntry(
        datasetId: 'original',
        status: VerseMappingStatus.matched,
        sources: sources);
    final entries = {'GEN.1.1': entry};
    final datasets =
        Map<String, CorrespondenceDatasetBinding>.of(_index().datasets);
    final provenance = {'evidence': 'manual review'};
    final index =
        _index(datasets: datasets, entries: entries, provenance: provenance);
    sources.clear();
    entries.clear();
    datasets.clear();
    provenance.clear();
    expect(index.entries, hasLength(1));
    expect(index.entries.values.single.sources, hasLength(1));
    expect(index.datasets, hasLength(1));
    expect(index.provenance, {'evidence': 'manual review'});
    expect(() => index.entries.clear(), throwsUnsupportedError);
    expect(() => entry.sources.clear(), throwsUnsupportedError);
    expect(() => index.datasets.clear(), throwsUnsupportedError);
    expect(() => index.provenance.clear(), throwsUnsupportedError);
    expect(() => index.coverage.clear(), throwsUnsupportedError);
    expect(() => index.unavailable.clear(), throwsUnsupportedError);

    expect(() => _index(datasets: {}), _invalid);
    expect(() => _index(datasets: {'wrong-id': index.datasets.values.single}),
        _invalid);
    expect(
        () => _index(entries: {
              'GEN.1.1': CorrespondenceEntry(
                datasetId: 'undeclared',
                status: VerseMappingStatus.unmapped,
              )
            }),
        _invalid);
    for (final key in ['gen.1.1', 'GEN.01.1', 'GEN.1.1A', 'GEN.1.2-1']) {
      expect(() => _index(entries: {key: entry}), _invalid);
    }
    expect(() => _index(provenance: {'': 'value'}), _invalid);
    final empty = _index(entries: {});
    expect(empty.coverage['verses'], 0);
    expect(_codec.decode(_codec.encode(empty)).entries, isEmpty);
  });

  test('entry constructor rejects cross-dataset and inconsistent status', () {
    expect(
        () => CorrespondenceEntry(
              datasetId: 'original',
              status: VerseMappingStatus.matched,
              sources: [_selection('other')],
            ),
        _invalid);
    expect(
        () => CorrespondenceEntry(
              datasetId: 'original',
              status: VerseMappingStatus.unmapped,
              sources: [_selection('original')],
            ),
        _invalid);
    for (final status in [
      VerseMappingStatus.matched,
      VerseMappingStatus.partial,
      VerseMappingStatus.ambiguous
    ]) {
      expect(() => CorrespondenceEntry(datasetId: 'original', status: status),
          _invalid);
    }
    expect(
        () => CorrespondenceEntry(
              datasetId: 'original',
              status: VerseMappingStatus.matched,
              sources: [
                InterlinearSourceSelection(
                    datasetId: 'original',
                    book: BibleBookEnum.genesis,
                    chapter: 1,
                    verseLabel: ' 1 '),
              ],
            ),
        _invalid);
  });

  test('source label spelling survives schema 2 round trips', () {
    for (final label in ['1A', '1–2', '1 - 2']) {
      final index = _index(entries: {
        'GEN.1.1': CorrespondenceEntry(
          datasetId: 'original',
          status: VerseMappingStatus.matched,
          sources: [
            InterlinearSourceSelection(
                datasetId: 'original',
                book: BibleBookEnum.genesis,
                chapter: 1,
                verseLabel: label),
          ],
        ),
      });
      expect(
          _codec
              .decode(_codec.encode(index))
              .entries['GEN.1.1']!
              .sources
              .single
              .verseLabel,
          label);
    }
  });

  test('schema 2 sync and cooperative decoding share strict validation',
      () async {
    final entry = _index().entries.values.single;
    final text = _codec.encode(_index(entries: {
      for (var verse = 1; verse <= 7; verse++) 'GEN.1.$verse': entry,
    }));
    var yields = 0;
    final async =
        await _codec.decodeAsync(text, batchSize: 2, yieldControl: () async {
      yields++;
    });
    expect(yields, 4);
    expect(_codec.encode(async), _codec.encode(_codec.decode(text)));
    final late = jsonDecode(text) as Map<String, dynamic>;
    late['entries']['GEN.1.7']['sources'][0]['occurrenceIdz'] = ['one'];
    yields = 0;
    expect(() => _codec.decode(jsonEncode(late)), _invalid);
    await expectLater(
        _codec.decodeAsync(jsonEncode(late), batchSize: 2,
            yieldControl: () async {
          yields++;
        }),
        _invalid);
    expect(yields, 4);

    for (final mutate in <void Function(Map<String, dynamic>)>[
      (v) => v['schemaVersion'] = 2.0,
      (v) => v['sourceEditionSha256'] = _editionHash,
      (v) => v['coverage'] = {'verses': 1},
      (v) => v['datasets']['original']['referenceSytem'] = 'typo',
      (v) => v['datasets']['original'].remove('referenceSystem'),
      (v) => v['datasets']['original']['manifestSha256'] = 'invalid',
      (v) => v['entries']['GEN.1.1']['datasetId'] = 'unknown',
      (v) => v['entries']['GEN.1.1']['status'] = 'success',
      (v) => v['entries']['GEN.1.1']['sources'][0]['datasetId'] = 'other',
      (v) => v['entries']['GEN.1.1']['sources'][0]['occurrenceIds'] = null,
      (v) => v['provenance']['numeric'] = 12,
    ]) {
      final value = _document();
      mutate(value);
      expect(() => _codec.decode(jsonEncode(value)), _invalid);
      await expectLater(
          _codec.decodeAsync(jsonEncode(value), yieldControl: () async {}),
          _invalid);
    }
  });

  test('resolver verifies each schema 2 native binding independently',
      () async {
    final dataset = _dataset('original', BibleBookEnum.genesis,
        revision: '2026-01',
        profile: 'reading-a',
        referenceSystem: 'archive-numbering');
    for (final field in ['sourceRevision', 'referenceSystem', 'profile']) {
      final value = _document();
      value['datasets']['original'][field] = 'another';
      final resolver = CorrespondenceResolver(
        index: _codec.decode(jsonEncode(value)),
        openDataset: (_) => CorrespondenceDataset.open(
            manifestBytes: dataset.resources['manifest.json']!,
            reader: (path) async => dataset.resources[path]!),
      );
      await expectLater(
          resolver.resolve(BibleLocation.checked(
              book: BibleBookEnum.genesis, chapter: 1, verse: 1)),
          throwsA(isA<InterlinearDataException>().having((error) => error.code,
              'code', 'correspondence_dataset_mismatch')));
    }
  });
}
