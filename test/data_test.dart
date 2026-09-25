import 'dart:async';
import 'dart:convert';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

final book = bibleBookFromUsfmIdentifier('JHN');
InterlinearChapter chapter(int number) =>
    InterlinearChapter(book: book, chapter: number, verses: [
      InterlinearVerse(
          location:
              BibleLocation.checked(book: book, chapter: number, verse: 1),
          textIsReconstructed: true,
          tokens: [
            InterlinearToken(
                occurrenceId: 'JHN.$number.1#1',
                surface: 'λόγος',
                language: 'grc',
                glosses: {
                  'en': 'word'
                },
                segments: [
                  InterlinearSegment(
                      kind: 'whole',
                      lemma: 'λόγος',
                      lexicalReferences: [
                        LexicalReference(
                            system: 'STEPBible:dStrong', value: 'G3056')
                      ],
                      morphology: [
                        MorphologyTag(scheme: 'STEPBible:TEGMC', code: 'N-NSM')
                      ])
                ])
          ]),
    ]);
InterlinearMetadata metadata() => InterlinearMetadata(
        datasetId: 'test',
        datasetRevision: '1',
        source: 'test',
        sourceRevision: 'fixture',
        profile: 'N',
        referenceSystem: 'test',
        originalLanguages: [
          'grc'
        ],
        glossLanguages: [
          'en'
        ],
        coverage: {
          book: [1, 2]
        },
        attribution: {
          'license': 'fixture'
        });
PreparedInterlinearDataset prepared() => PreparedInterlinearDataset.build(
    metadata: metadata(), chapters: [chapter(1), chapter(2)]);

void main() {
  const codec = InterlinearJsonCodec();
  test('cooperative chapter decoding matches sync data and rejects late errors',
      () async {
    final value =
        jsonDecode(codec.encodeChapter(chapter(1))) as Map<String, dynamic>;
    final verse = (value['verses'] as List).single as Map<String, dynamic>;
    final token = (verse['tokens'] as List).single as Map<String, dynamic>;
    verse['tokens'] = [
      for (var i = 0; i < 9; i++) {...token, 'occurrenceId': 'word:$i'}
    ];
    value['specialEntries'] = [
      {
        'sourceLabel': 'native.title',
        'kind': 'heading',
        'tokens': [
          for (var i = 0; i < 2; i++) {...token, 'occurrenceId': 'title:$i'}
        ],
        'surfaceText': null,
        'provenance': <String, String>{},
      }
    ];
    final text = jsonEncode(value);
    var checkpoints = 0;
    final actual = await codec.decodeChapterAsync(text, batchSize: 2,
        yieldControl: () async {
      checkpoints++;
    });
    expect(checkpoints, 6);
    expect(codec.encodeChapter(actual),
        codec.encodeChapter(codec.decodeChapter(text)));
    expect(actual.specialEntries.single.tokens.last.occurrenceId, 'title:1');
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (last) => last['surface'] = 42,
      (last) => last['occurrenceId'] = 'word:0',
      (last) => last['unknown'] = true,
    ]) {
      final broken = jsonDecode(text) as Map<String, dynamic>;
      mutate(broken['specialEntries'][0]['tokens'][1] as Map<String, dynamic>);
      String? expectedCode;
      try {
        codec.decodeChapter(jsonEncode(broken));
      } on InterlinearDataException catch (error) {
        expectedCode = error.code;
      }
      expect(expectedCode, isNotNull);
      checkpoints = 0;
      await expectLater(
          codec.decodeChapterAsync(jsonEncode(broken), batchSize: 2,
              yieldControl: () async {
            checkpoints++;
          }),
          throwsA(isA<InterlinearDataException>()
              .having((e) => e.code, 'same code', expectedCode)));
      expect(checkpoints, greaterThan(1));
    }
    await expectLater(
        codec.decodeChapterAsync(text, batchSize: 0, yieldControl: () async {}),
        throwsArgumentError);
  });

  test('deterministic serialization, round trip, Unicode and optional nulls',
      () {
    final first = prepared();
    final second = PreparedInterlinearDataset.build(
        metadata: metadata(), chapters: [chapter(2), chapter(1)]);
    expect(first.resources, second.resources);
    final original = codec.encodeChapter(chapter(1));
    final restored = codec.decodeChapter(original);
    expect(codec.encodeChapter(restored), original);
    expect(restored.getVerse(1).tokens.single.surface, 'λόγος');
    expect(restored.getVerse(1).tokens.single.transliteration, isNull);
    expect(
        codec.encodeManifest(codec
            .decodeManifest(utf8.decode(first.resources['manifest.json']!))),
        utf8.decode(first.resources['manifest.json']!));
    expect(
        () => first.resources['manifest.json']![0] = 0, throwsUnsupportedError);
  });
  test(
      'strict decoder rejects versions, missing and unknown fields and wrong types',
      () {
    final value =
        jsonDecode(codec.encodeChapter(chapter(1))) as Map<String, dynamic>;
    for (final change in <Map<String, dynamic>>[
      {...value, 'schemaVersion': 2},
      {...value, 'chapter': '1'},
      {...value, 'unexpected': true},
      {...value}..remove('verses'),
      {...value, 'book': 'jhn'},
    ]) {
      expect(() => codec.decodeChapter(jsonEncode(change)),
          throwsA(isA<InterlinearDataException>()));
    }
    expect(() => codec.decodeChapter('{'),
        throwsA(isA<InterlinearDataException>()));
  });
  test('unsafe resource paths are rejected before reader invocation', () {
    for (final path in [
      '../x',
      '/tmp/x',
      'C:/x',
      'a\\b',
      'a/../b',
      'a//b',
      'https://x',
      'a/%2e%2e/b',
      './a',
      'a/',
      'a./b',
      '.../b',
      'NUL',
      'a/con.json',
      'COM1/data.json',
      'Lpt9.txt'
    ]) {
      expect(() => validateResourcePath(path),
          throwsA(isA<InterlinearDataException>()),
          reason: path);
    }
    validateResourcePath('chapters/JHN.1.json');
  });
  test('manifest coverage/resource mismatch is malformed', () {
    final value =
        jsonDecode(utf8.decode(prepared().resources['manifest.json']!))
            as Map<String, dynamic>;
    (value['chapters'] as List).removeLast();
    expect(() => codec.decodeManifest(jsonEncode(value)),
        throwsA(isA<InterlinearDataException>()));
  });
  test('loads requested chapter only, verifies integrity, distinguishes errors',
      () async {
    final resources = Map<String, List<int>>.of(prepared().resources);
    final calls = <String>[];
    final source = JsonInterlinearDataSource(reader: (path) async {
      calls.add(path);
      final value = resources[path];
      if (value == null) throw StateError('missing');
      return value;
    });
    final bible = await InterlinearBible.open(source);
    expect(calls, ['manifest.json', 'attribution.json']);
    expect((await bible.loadChapter(book, 1)).getVerse(1).tokens.single.surface,
        'λόγος');
    expect(calls, contains('chapters/JHN.1.json'));
    expect(calls, isNot(contains('chapters/JHN.2.json')));
    await expectLater(bible.loadChapter(book, 3),
        throwsA(isA<UnsupportedCoverageException>()));
    final loaded = await bible.loadChapter(book, 1);
    expect(() => loaded.getVerse(9),
        throwsA(isA<InterlinearVerseNotFoundException>()));
    resources['chapters/JHN.2.json'] = utf8.encode('{}');
    await expectLater(
        bible.loadChapter(book, 2),
        throwsA(isA<InterlinearDataException>()
            .having((e) => e.code, 'code', 'integrity_mismatch')));
    resources.remove('chapters/JHN.2.json');
    await expectLater(bible.loadChapter(book, 2),
        throwsA(isA<InterlinearResourceException>()));
    resources['chapters/JHN.2.json'] =
        prepared().resources['chapters/JHN.2.json']!;
    expect((await bible.loadChapter(book, 2)).chapter, 2);
  });
  test('deduplicates concurrent loads and evicts least recently used chapter',
      () async {
    final resources = prepared().resources;
    final calls = <String, int>{};
    Completer<void>? gate = Completer<void>();
    final bible = await InterlinearBible.open(
        JsonInterlinearDataSource(reader: (path) async {
      calls.update(path, (n) => n + 1, ifAbsent: () => 1);
      if (path.startsWith('chapters/')) await gate?.future;
      return resources[path]!;
    }), cacheCapacity: 1);
    final a = bible.loadChapter(book, 1);
    final b = bible.loadChapter(book, 1);
    expect(identical(a, b), isTrue);
    gate.complete();
    gate = null;
    expect(identical(await a, await b), isTrue);
    await bible.loadChapter(book, 1);
    expect(calls['chapters/JHN.1.json'], 1);
    await bible.loadChapter(book, 2);
    await bible.loadChapter(book, 1);
    expect(calls['chapters/JHN.1.json'], 2);
    expect(bible.cachedChapterCount, 1);
    bible.clearCache();
    expect(bible.cachedChapterCount, 0);
  });
  test('zero capacity still deduplicates in-flight loads and does not cache',
      () async {
    var calls = 0;
    final resources = prepared().resources;
    final bible = await InterlinearBible.open(
        JsonInterlinearDataSource(reader: (path) async {
      if (path.startsWith('chapters/')) calls++;
      return resources[path]!;
    }), cacheCapacity: 0);
    await Future.wait([bible.loadChapter(book, 1), bible.loadChapter(book, 1)]);
    expect(calls, 1);
    await bible.loadChapter(book, 1);
    expect(calls, 2);
    expect(bible.cachedChapterCount, 0);
  });
  test('failed manifest can be retried; invalid UTF-8 is a data error',
      () async {
    var broken = true;
    final resources = prepared().resources;
    final source = JsonInterlinearDataSource(
        reader: (path) async => broken ? [0xff] : resources[path]!);
    await expectLater(
        source.loadMetadata(),
        throwsA(isA<InterlinearDataException>()
            .having((e) => e.code, 'code', 'invalid_utf8')));
    broken = false;
    expect((await source.loadMetadata()).datasetId, 'test');
  });
  test('attribution is integrity checked on open', () async {
    final resources = Map<String, List<int>>.of(prepared().resources)
      ..['attribution.json'] = utf8.encode('{}');
    await expectLater(
        InterlinearBible.open(JsonInterlinearDataSource(
            reader: (path) async => resources[path]!)),
        throwsA(isA<InterlinearDataException>()
            .having((e) => e.code, 'code', 'integrity_mismatch')));
  });

  test('memory source rejects duplicate chapters before indexing', () {
    final replacement = InterlinearChapter(book: book, chapter: 1, verses: [
      InterlinearVerse(
          location: BibleLocation.checked(book: book, chapter: 1, verse: 1),
          tokens: [
            InterlinearToken(
                occurrenceId: 'replacement',
                surface: 'different',
                language: 'grc')
          ]),
    ]);
    expect(
        () => MemoryInterlinearDataSource(
            metadata: metadata(),
            chapters: [chapter(1), replacement, chapter(2)]),
        throwsArgumentError);
  });

  test('malformed labels, books and nested fields use package data errors', () {
    Map<String, dynamic> value() =>
        jsonDecode(codec.encodeChapter(chapter(1))) as Map<String, dynamic>;
    for (final label in ['0', '5ab', '5-4', '1000']) {
      final data = value();
      (data['verses'] as List).first['label'] = label;
      expect(
          () => codec.decodeChapter(jsonEncode(data)),
          throwsA(isA<InterlinearDataException>()
              .having((e) => e.code, 'code', 'invalid_verse_label')),
          reason: label);
    }
    for (final invalid in ['UNKNOWN', 'John', 'jhn', ' JHN', 42, null]) {
      final data = value()..['book'] = invalid;
      expect(() => codec.decodeChapter(jsonEncode(data)),
          throwsA(isA<InterlinearDataException>()),
          reason: '$invalid');
    }
    final data = value();
    ((data['verses'] as List).first['tokens'] as List).first['glosses'] = {
      'en': 42
    };
    expect(() => codec.decodeChapter(jsonEncode(data)),
        throwsA(isA<InterlinearDataException>()));
    final manifest =
        jsonDecode(utf8.decode(prepared().resources['manifest.json']!))
            as Map<String, dynamic>;
    manifest['metadata']['coverage'] = {
      'UNKNOWN': [1, 2]
    };
    expect(() => codec.decodeManifest(jsonEncode(manifest)),
        throwsA(isA<InterlinearDataException>()));
  });

  test(
      'manifest rejects resource aliases that collide on case-insensitive filesystems',
      () {
    final hash = resourceSha256([]);
    expect(
        () => InterlinearManifest(
                metadata: metadata(),
                attribution:
                    InterlinearResource(path: 'attr.json', sha256: hash),
                chapters: [
                  InterlinearChapterResource(
                      book: book,
                      chapter: 1,
                      path: 'chapters/entry.json',
                      sha256: hash),
                  InterlinearChapterResource(
                      book: book,
                      chapter: 2,
                      path: 'CHAPTERS/ENTRY.JSON',
                      sha256: hash),
                ]),
        throwsArgumentError);
    expect(
        () => InterlinearManifest(
            metadata: metadata(),
            chapters: [],
            attribution:
                InterlinearResource(path: 'MANIFEST.JSON', sha256: hash)),
        throwsArgumentError);
  });

  test(
      'attribution rejects extra fields, numeric schema aliases and mismatched identities',
      () async {
    for (final change in <String, Object?>{
      'extra': true,
      'schemaVersion': 1.0,
      'datasetId': 'wrong'
    }.entries) {
      final resources = Map<String, List<int>>.of(prepared().resources);
      final attribution =
          jsonDecode(utf8.decode(resources['attribution.json']!))
              as Map<String, dynamic>;
      attribution[change.key] = change.value;
      resources['attribution.json'] = utf8.encode(jsonEncode(attribution));
      final manifest = jsonDecode(utf8.decode(resources['manifest.json']!))
          as Map<String, dynamic>;
      manifest['attribution']['sha256'] =
          resourceSha256(resources['attribution.json']!);
      resources['manifest.json'] = utf8.encode(jsonEncode(manifest));
      await expectLater(
          JsonInterlinearDataSource(reader: (path) async => resources[path]!)
              .loadMetadata(),
          throwsA(isA<InterlinearDataException>()
              .having((e) => e.code, 'code', 'invalid_attribution')),
          reason: change.key);
    }
  });

  test('manifest requests are coalesced and a shared failure remains retryable',
      () async {
    final resources = prepared().resources;
    var manifestCalls = 0;
    final gate = Completer<List<int>>();
    final source = JsonInterlinearDataSource(reader: (path) async {
      if (path == 'manifest.json' && manifestCalls++ == 0) return gate.future;
      return resources[path]!;
    });
    final first = source.loadManifest();
    final second = source.loadManifest();
    expect(identical(first, second), isTrue);
    final failures = [
      expectLater(first, throwsA(isA<InterlinearResourceException>())),
      expectLater(second, throwsA(isA<InterlinearResourceException>())),
    ];
    gate.completeError(StateError('transient reader failure'));
    await Future.wait(failures);
    expect((await source.loadManifest()).metadata.datasetId, 'test');
    expect(manifestCalls, 2);
  });

  test('reader values outside byte range fail as malformed data', () async {
    for (final value in [-1, 256]) {
      await expectLater(
          JsonInterlinearDataSource(reader: (_) async => [value])
              .loadMetadata(),
          throwsA(isA<InterlinearDataException>()
              .having((e) => e.code, 'code', 'invalid_bytes')));
    }
  });

  test(
      'cache hits update recency and failures from custom sources are retryable',
      () async {
    final threeMetadata = InterlinearMetadata(
        datasetId: 'test',
        datasetRevision: '1',
        source: 'test',
        sourceRevision: 'fixture',
        profile: 'N',
        referenceSystem: 'test',
        originalLanguages: [
          'grc'
        ],
        glossLanguages: [
          'en'
        ],
        coverage: {
          book: [1, 2, 3]
        });
    final calls = <int, int>{};
    final source = _Source(threeMetadata, (requestedBook, number) {
      calls.update(number, (value) => value + 1, ifAbsent: () => 1);
      return chapter(number);
    });
    final bible = await InterlinearBible.open(source, cacheCapacity: 2);
    await bible.loadChapter(book, 1);
    await bible.loadChapter(book, 2);
    await bible.loadChapter(book, 1); // 2 becomes least recently used.
    await bible.loadChapter(book, 3);
    await bible.loadChapter(book, 1);
    expect(calls[1], 1);
    await bible.loadChapter(book, 2);
    expect(calls[2], 2);
    expect(bible.cachedChapterCount, 2);

    var attempt = 0;
    final retryBible =
        await InterlinearBible.open(_Source(metadata(), (_, number) {
      attempt++;
      if (attempt == 1) throw StateError('synchronous source failure');
      if (attempt == 2) return chapter(2);
      return chapter(number);
    }));
    await expectLater(retryBible.loadChapter(book, 1), throwsStateError);
    await expectLater(
        retryBible.loadChapter(book, 1),
        throwsA(isA<InterlinearDataException>()
            .having((e) => e.code, 'code', 'chapter_mismatch')));
    expect(retryBible.cachedChapterCount, 0);
    expect((await retryBible.loadChapter(book, 1)).chapter, 1);
    expect(attempt, 3);
  });
}

class _Source implements InterlinearDataSource {
  _Source(this.metadata, this.read);
  final InterlinearMetadata metadata;
  final InterlinearChapter Function(BibleBookEnum, int) read;
  @override
  Future<InterlinearMetadata> loadMetadata() async => metadata;
  @override
  Future<InterlinearChapter> loadChapter(BibleBookEnum book, int chapter) =>
      Future.value(read(book, chapter));
}
