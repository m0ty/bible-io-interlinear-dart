import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

const _codec = CorrespondenceJsonCodec();
final _book = BibleBookEnum.john;
final _translation = BibleLocation.checked(book: _book, chapter: 1, verse: 9);
final _hash = resourceSha256(utf8.encode('test edition'));
InterlinearToken _token(String id) => InterlinearToken(
    occurrenceId: id,
    surface: id,
    language: 'grc',
    sourceRecordId: 'source:$id');

PreparedInterlinearDataset _dataset() => PreparedInterlinearDataset.build(
      metadata: InterlinearMetadata(
          datasetId: 'test',
          datasetRevision: '1',
          source: 'test',
          sourceRevision: 'fixture',
          profile: 'N',
          referenceSystem: 'native',
          originalLanguages: [
            'grc'
          ],
          glossLanguages: [
            'en'
          ],
          coverage: {
            _book: [1]
          }),
      chapters: [
        InterlinearChapter(book: _book, chapter: 1, verses: [
          InterlinearVerse(
              location:
                  BibleLocation.checked(book: _book, chapter: 1, verse: 1),
              tokens: [_token('first'), _token('second')]),
          InterlinearVerse(
              location:
                  BibleLocation.checked(book: _book, chapter: 1, verse: 2),
              tokens: [_token('third')]),
        ], specialEntries: [
          InterlinearSpecialEntry(
              sourceLabel: 'native.title',
              kind: 'heading',
              tokens: [_token('title')])
        ])
      ],
    );

Map<String, dynamic> _document(PreparedInterlinearDataset dataset) =>
    jsonDecode(jsonEncode({
      'schemaVersion': 1,
      'sourceEdition': 'translation',
      'sourceEditionSha256': _hash,
      'sourceAssetSha256': _hash,
      'sourceReferenceSystem': 'translation-numbering',
      'sourceRevision': 'fixture',
      'targetReferenceSystem': 'native',
      'datasets': {
        'test': {
          'datasetRevision': '1',
          'sourceRevision': 'fixture',
          'profile': 'N',
          'manifestSha256': resourceSha256(dataset.resources['manifest.json']!)
        }
      },
      'provenance': {
        'authority': 'test',
        'source': 'test',
        'license': 'test',
        'licenseUrl': 'test',
        'evidence': 'test',
        'tvtmsSha256': _hash,
        'scope': 'test',
        'method': 'test',
        'modifications': 'test'
      },
      'coverage': {
        'books': 1,
        'chapters': 1,
        'verses': 1,
        'matched': 1,
        'unavailable': <String>[],
        'resegmented': 1,
        'superscriptions': 1,
        'tokens': 4,
        'movedGreekTokens': 0,
        'filteredSources': 1
      },
      'entries': {
        'JHN.1.9': {
          'datasetId': 'test',
          'status': 'matched',
          'sources': [
            {'book': 'JHN', 'chapter': 1, 'specialEntryLabel': 'native.title'},
            {
              'book': 'JHN',
              'chapter': 1,
              'verseLabel': '1',
              'occurrenceIds': ['second', 'first']
            },
            {'book': 'JHN', 'chapter': 1, 'verseLabel': '2'},
          ]
        }
      },
    })) as Map<String, dynamic>;

Map<String, dynamic> _entry(Map<String, dynamic> value) =>
    value['entries']['JHN.1.9'] as Map<String, dynamic>;
Map<String, dynamic> _selected(Map<String, dynamic> value) =>
    _entry(value)['sources'][1] as Map<String, dynamic>;
Future<CorrespondenceDataset> _open(PreparedInterlinearDataset dataset) async =>
    CorrespondenceDataset.open(
        reader: (path) async => dataset.resources[path]!,
        manifestBytes: dataset.resources['manifest.json']!);

void main() {
  test('legacy correspondence can be re-encoded as provider-neutral schema 2',
      () async {
    final dataset = _dataset();
    final legacy = _codec.decode(jsonEncode(_document(dataset)));
    final text = _codec.encode(legacy);
    final serialized = jsonDecode(text) as Map<String, dynamic>;
    expect(serialized['schemaVersion'], 2);
    expect(serialized.containsKey('sourceEditionSha256'), isFalse);
    expect(serialized.containsKey('coverage'), isFalse);
    expect(serialized['datasets']['test']['referenceSystem'], 'native');
    final migrated = _codec.decode(text);
    expect(migrated.sourceRevision, legacy.sourceRevision);
    expect(migrated.targetReferenceSystem, legacy.targetReferenceSystem);
    expect(migrated.provenance, legacy.provenance);
    expect(migrated.sourceAssetSha256, legacy.sourceAssetSha256);
    expect(migrated.coverage['verses'], legacy.coverage['verses']);
    expect(migrated.coverage.containsKey('movedGreekTokens'), isFalse);
    final result = await CorrespondenceResolver(
        index: migrated,
        openDataset: (_) => _open(dataset)).resolve(_translation);
    expect(result.tokens.map((token) => token.occurrenceId),
        ['title', 'second', 'first', 'third']);
  });

  test('owned source rejects different chapter content with identical metadata',
      () async {
    final original = _dataset();
    const codec = InterlinearJsonCodec();
    final chapter = codec
        .decodeChapter(utf8.decode(original.resources['chapters/JHN.1.json']!));
    final changed = InterlinearChapter(
        book: chapter.book,
        chapter: chapter.chapter,
        verses: [
          for (final verse in chapter.verses)
            InterlinearVerse(location: verse.location, tokens: [
              for (final token in verse.tokens)
                InterlinearToken(
                    occurrenceId: token.occurrenceId,
                    surface: 'different',
                    language: token.language)
            ])
        ],
        specialEntries: chapter.specialEntries);
    final other = PreparedInterlinearDataset.build(
        metadata: original.manifest.metadata, chapters: [changed]);
    final resolver = CorrespondenceResolver(
        index: _codec.decode(jsonEncode(_document(original))),
        openDataset: (_) => CorrespondenceDataset.open(
            manifestBytes: original.resources['manifest.json']!,
            reader: (path) async => other.resources[path]!));
    await expectLater(
        resolver.resolve(_translation),
        throwsA(isA<InterlinearDataException>()
            .having((e) => e.code, 'code', 'integrity_mismatch')));
  });

  test(
      'exact bound noncanonical JSON bytes are accepted without model re-encoding',
      () async {
    final original = _dataset();
    final resources = Map<String, List<int>>.of(original.resources);
    const chapterPath = 'chapters/JHN.1.json';
    resources[chapterPath] = utf8.encode(const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(utf8.decode(resources[chapterPath]!))));
    final manifest = jsonDecode(utf8.decode(resources['manifest.json']!));
    manifest['chapters'][0]['sha256'] = resourceSha256(resources[chapterPath]!);
    resources['manifest.json'] = utf8.encode(jsonEncode(manifest));
    final document = _document(original);
    document['datasets']['test']['manifestSha256'] =
        resourceSha256(resources['manifest.json']!);
    for (final cooperative in [false, true]) {
      final resolver = CorrespondenceResolver(
          index: _codec.decode(jsonEncode(document)),
          openDataset: (_) => CorrespondenceDataset.open(
              manifestBytes: resources['manifest.json']!,
              reader: (path) async => resources[path]!,
              verifyAndDecodeChapter: cooperative
                  ? (bytes, hash) => decodeVerifiedInterlinearChapterAsync(
                      bytes, hash,
                      yieldControl: () async {})
                  : null));
      expect(
          (await resolver.resolve(_translation))
              .tokens
              .map((t) => t.occurrenceId),
          ['title', 'second', 'first', 'third']);
    }
  });

  test(
      'cooperative decoder shares all synchronous validation and late failures',
      () async {
    final value = _document(_dataset());
    final entry = _entry(value);
    value['entries'] = {
      for (var verse = 1; verse <= 7; verse++) 'JHN.1.$verse': entry
    };
    value['coverage']['verses'] = 7;
    value['coverage']['matched'] = 7;
    final text = jsonEncode(value);
    final synchronous = _codec.decode(text);
    var checkpoints = 0;
    final cooperative =
        await _codec.decodeAsync(text, batchSize: 2, yieldControl: () async {
      checkpoints++;
    });
    expect(checkpoints, 4);
    expect(cooperative.coverage, synchronous.coverage);
    expect(cooperative.provenance, synchronous.provenance);
    expect(cooperative.sourceAssetSha256, synchronous.sourceAssetSha256);
    expect(cooperative.entries.keys, synchronous.entries.keys);
    for (final key in synchronous.entries.keys) {
      final first = synchronous.entries[key]!;
      final second = cooperative.entries[key]!;
      expect(second.datasetId, first.datasetId);
      expect(second.status, first.status);
      expect(second.note, first.note);
      expect(second.sources.map((s) => s.specialEntryLabel),
          first.sources.map((s) => s.specialEntryLabel));
      expect(second.sources.map((s) => s.verseLabel),
          first.sources.map((s) => s.verseLabel));
      expect(second.sources.map((s) => s.occurrenceIds),
          first.sources.map((s) => s.occurrenceIds));
    }
    final late = jsonDecode(text) as Map<String, dynamic>;
    late['entries']['JHN.1.7']['sources'][1]['occurrenceIdz'] =
        late['entries']['JHN.1.7']['sources'][1].remove('occurrenceIds');
    checkpoints = 0;
    String? synchronousMessage;
    try {
      _codec.decode(jsonEncode(late));
    } on InterlinearDataException catch (error) {
      synchronousMessage = error.message;
    }
    expect(synchronousMessage, isNotNull);
    await expectLater(
        _codec.decodeAsync(jsonEncode(late), batchSize: 2,
            yieldControl: () async {
          checkpoints++;
        }),
        throwsA(isA<InterlinearDataException>()
            .having((e) => e.message, 'same failure', synchronousMessage)));
    expect(checkpoints, 4);
    await expectLater(
        _codec.decodeAsync(text, batchSize: 0, yieldControl: () async {}),
        throwsArgumentError);
  });

  test('cooperative SHA-256 matches exact bytes across chunk boundaries',
      () async {
    for (final bytes in <List<int>>[
      [],
      [0, 255, 1],
      Uint8List.fromList(List.generate(131073, (i) => i % 256)),
    ]) {
      var checkpoints = 0;
      expect(
          await resourceSha256Async(bytes, chunkSize: 65536,
              yieldControl: () async {
            checkpoints++;
          }),
          resourceSha256(bytes));
      expect(checkpoints, (bytes.length / 65536).ceil());
    }
  });

  test(
      'typed resolver retains ordered subsets, headings and translation identity',
      () async {
    final dataset = _dataset();
    final index = _codec.decode(jsonEncode(_document(dataset)));
    index.validateSourceEdition(
        editionId: 'translation',
        referenceSystem: 'translation-numbering',
        assetSha256: _hash);
    var opens = 0;
    final resolver = CorrespondenceResolver(
        index: index,
        openDataset: (_) {
          opens++;
          return _open(dataset);
        });
    final value = await resolver.resolve(_translation);
    expect(value.translationLocation, _translation);
    expect(value.tokens.map((t) => t.occurrenceId),
        ['title', 'second', 'first', 'third']);
    expect(value.reconstructedText, 'title second first third');
    expect(value.sourceSelections.first.specialEntryLabel, 'native.title');
    expect(value.sourceSelections[1].occurrenceIds, ['second', 'first']);
    expect(value.mapping.targets.map((t) => t.verse), [1, 2]);
    expect(value.metadata!.referenceSystem, 'native');
    expect(value.tokens.first.sourceRecordId, 'source:title');
    expect(() => value.tokens.clear(), throwsUnsupportedError);
    expect(() => value.sourceSelections[1].occurrenceIds!.clear(),
        throwsUnsupportedError);
    expect(() => index.entries.clear(), throwsUnsupportedError);
    await resolver.resolve(_translation);
    expect(opens, 1);
  });

  test(
      'unknown fields at every structured level and selector typos fail closed',
      () {
    final dataset = _dataset();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (v) => v['futureField'] = true,
      (v) => v['datasets']['test']['profil'] = 'N',
      (v) => _entry(v)['statuz'] = 'matched',
      (v) =>
          _selected(v)['occurrenceIdz'] = _selected(v).remove('occurrenceIds'),
      (v) => v['coverage']['tokenz'] = 4,
      (v) => v['provenance']['methodz'] = 'other',
    ]) {
      final value = _document(dataset);
      mutate(value);
      expect(() => _codec.decode(jsonEncode(value)),
          throwsA(isA<InterlinearDataException>()));
    }
  });

  test(
      'rejects null, empty, duplicate and malformed selectors and bad coverage',
      () {
    final dataset = _dataset();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (v) => _selected(v)['occurrenceIds'] = null,
      (v) => _selected(v)['occurrenceIds'] = [],
      (v) => _selected(v)['occurrenceIds'] = ['first', 'first'],
      (v) => _selected(v)['verseLabel'] = '5-4',
      (v) => _selected(v)['book'] = 'jhn',
      (v) => _selected(v)['chapter'] = 0,
      (v) => _selected(v)['specialEntryLabel'] = 'native.title',
      (v) => _selected(v).remove('verseLabel'),
      (v) => _entry(v)['datasetId'] = 'unknown',
      (v) => v['schemaVersion'] = 1.0,
      (v) => v['coverage']['matched'] = 99,
      (v) => v['sourceEditionSha256'] = List.filled(64, '0').join(),
    ]) {
      final value = _document(dataset);
      mutate(value);
      expect(() => _codec.decode(jsonEncode(value)),
          throwsA(isA<InterlinearDataException>()));
    }
  });

  test(
      'source binding checks edition ID, reference system and actual content hash',
      () {
    final index = _codec.decode(jsonEncode(_document(_dataset())));
    for (final identity in [
      ('wrong', 'translation-numbering', _hash),
      ('translation', 'wrong', _hash),
      ('translation', 'translation-numbering', List.filled(64, '0').join()),
    ]) {
      expect(
          () => index.validateSourceEdition(
              editionId: identity.$1,
              referenceSystem: identity.$2,
              assetSha256: identity.$3),
          throwsA(isA<InterlinearDataException>().having(
              (e) => e.code, 'code', 'correspondence_edition_mismatch')));
    }
  });

  test(
      'dataset binding checks exact manifest hash, profile and dataset revision',
      () async {
    final dataset = _dataset();
    for (final field in ['manifestSha256', 'profile', 'datasetRevision']) {
      final value = _document(dataset);
      value['datasets']['test'][field] =
          field == 'manifestSha256' ? List.filled(64, '0').join() : 'wrong';
      final resolver = CorrespondenceResolver(
          index: _codec.decode(jsonEncode(value)),
          openDataset: (_) => _open(dataset));
      await expectLater(resolver.resolve(_translation),
          throwsA(isA<InterlinearDataException>()));
    }
    final sourceRevision = _document(dataset);
    sourceRevision['datasets']['test']['sourceRevision'] = 'wrong';
    expect(() => _codec.decode(jsonEncode(sourceRevision)),
        throwsA(isA<InterlinearDataException>()));
  });

  test('manifest bytes cannot be substituted and failed opens retry/coalesce',
      () async {
    final dataset = _dataset();
    var calls = 0;
    final gate = Completer<CorrespondenceDataset>();
    final resolver = CorrespondenceResolver(
        index: _codec.decode(jsonEncode(_document(dataset))),
        openDataset: (_) => calls++ == 0 ? gate.future : _open(dataset));
    final first = resolver.resolve(_translation);
    final second = resolver.resolve(_translation);
    final checks = [
      expectLater(first, throwsA(isA<InterlinearDataException>())),
      expectLater(second, throwsA(isA<InterlinearDataException>()))
    ];
    final valid = await _open(dataset);
    gate.complete(await CorrespondenceDataset.open(
        reader: (path) async => dataset.resources[path]!,
        manifestBytes: [...valid.manifestBytes, 32]));
    await Future.wait(checks);
    expect(calls, 1);
    expect((await resolver.resolve(_translation)).tokens, hasLength(4));
    expect(calls, 2);
  });

  test(
      'missing and duplicate selected occurrences never fall back to whole entry',
      () async {
    final dataset = _dataset();
    for (final modify in <void Function(Map<String, dynamic>)>[
      (v) => _selected(v)['occurrenceIds'] = ['absent'],
      (v) => _entry(v)['sources']
          .add({'book': 'JHN', 'chapter': 1, 'verseLabel': '2'}),
      (v) => _entry(v)['sources'][0]['specialEntryLabel'] = 'absent',
    ]) {
      final value = _document(dataset);
      modify(value);
      final resolver = CorrespondenceResolver(
          index: _codec.decode(jsonEncode(value)),
          openDataset: (_) => _open(dataset));
      await expectLater(resolver.resolve(_translation),
          throwsA(isA<InterlinearDataException>()));
    }
  });

  test(
      'heading-only result has native selectors without inventing verse targets',
      () async {
    final dataset = _dataset();
    final value = _document(dataset);
    _entry(value)['sources'] = [_entry(value)['sources'][0]];
    final result = await CorrespondenceResolver(
        index: _codec.decode(jsonEncode(value)),
        openDataset: (_) => _open(dataset)).resolve(_translation);
    expect(result.mapping.status, VerseMappingStatus.matched);
    expect(result.mapping.targets, isEmpty);
    expect(result.sourceSelections.single.specialEntryLabel, 'native.title');
    expect(result.tokens.single.occurrenceId, 'title');
  });

  test(
      'unmapped and ambiguous entries do not open datasets or merge alternatives',
      () async {
    final dataset = _dataset();
    for (final status in ['unmapped', 'ambiguous']) {
      final value = _document(dataset);
      _entry(value)['status'] = status;
      value['coverage']['matched'] = 0;
      if (status == 'unmapped') {
        _entry(value)['sources'] = [];
        value['coverage']['unavailable'] = ['JHN.1.9'];
      }
      final result = await CorrespondenceResolver(
              index: _codec.decode(jsonEncode(value)),
              openDataset: (_) =>
                  throw StateError('Must not load alternatives'))
          .resolve(_translation);
      expect(result.mapping.status.name, status);
      expect(result.tokens, isEmpty);
    }
  });
}
