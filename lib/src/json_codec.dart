import 'dart:convert';
import 'dart:typed_data';

import 'package:bible_io/bible_io.dart';
import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'models.dart';

/// Resource names are portable relative paths, never URLs or host paths.
void validateResourcePath(String path) {
  final parts = path.split('/');
  final windowsDevice = RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$',
      caseSensitive: false);
  if (path.isEmpty ||
      !RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path) ||
      path.startsWith('/') ||
      parts.any((part) =>
          part.isEmpty || part.endsWith('.') || windowsDevice.hasMatch(part))) {
    throw InterlinearDataException('invalid_resource_path',
        'Expected a safe relative resource path: $path',
        path: path);
  }
}

String resourceSha256(List<int> bytes) => sha256.convert(bytes).toString();

/// Hashes exact resource bytes with caller-controlled scheduling checkpoints.
Future<String> resourceSha256Async(List<int> bytes,
    {required Future<void> Function() yieldControl,
    int chunkSize = 65536}) async {
  if (chunkSize < 1) throw ArgumentError.value(chunkSize, 'chunkSize');
  final result = _DigestResult();
  final input = sha256.startChunkedConversion(result);
  for (var start = 0; start < bytes.length; start += chunkSize) {
    final end =
        (start + chunkSize < bytes.length) ? start + chunkSize : bytes.length;
    input.add(bytes is Uint8List
        ? Uint8List.sublistView(bytes, start, end)
        : bytes.sublist(start, end));
    await yieldControl();
  }
  input.close();
  return result.value!.toString();
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class InterlinearResource {
  final String path;
  final String sha256;
  InterlinearResource({required this.path, required this.sha256}) {
    validateResourcePath(path);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(sha256, 'sha256', 'Expected lowercase SHA-256');
    }
  }
}

class InterlinearChapterResource extends InterlinearResource {
  final BibleBookEnum book;
  final int chapter;
  InterlinearChapterResource(
      {required this.book,
      required this.chapter,
      required super.path,
      required super.sha256}) {
    if (chapter < 1) throw ArgumentError.value(chapter, 'chapter');
  }
}

class InterlinearManifest {
  final InterlinearMetadata metadata;
  final List<InterlinearChapterResource> chapters;
  final InterlinearResource attribution;
  InterlinearManifest(
      {required this.metadata,
      required Iterable<InterlinearChapterResource> chapters,
      required this.attribution})
      : chapters = List.unmodifiable(chapters) {
    final found = <String>{};
    final paths = <String>{'manifest.json', attribution.path.toLowerCase()};
    for (final entry in this.chapters) {
      final key = chapterKey(entry.book, entry.chapter);
      if (!found.add(key) || !paths.add(entry.path.toLowerCase())) {
        throw ArgumentError('Duplicate chapter or resource path: $key');
      }
      if (!(metadata.coverage[entry.book]?.contains(entry.chapter) ?? false)) {
        throw ArgumentError('Resource outside declared coverage: $key');
      }
    }
    if (attribution.path.toLowerCase() == 'manifest.json' ||
        found.length !=
            metadata.coverage.values.fold<int>(0, (n, v) => n + v.length)) {
      throw ArgumentError('Manifest resources must exactly match coverage');
    }
  }

  InterlinearChapterResource resourceFor(BibleBookEnum book, int chapter) {
    for (final resource in chapters) {
      if (resource.book == book && resource.chapter == chapter) return resource;
    }
    throw UnsupportedCoverageException(
        'unsupported_coverage', 'No resource for ${chapterKey(book, chapter)}');
  }
}

String chapterKey(BibleBookEnum book, int chapter) =>
    '${book.usfmIdentifier}.$chapter';

/// Schema 1 codec. JSON object keys are sorted; list order remains meaningful.
class InterlinearJsonCodec {
  const InterlinearJsonCodec();
  static const schemaVersion = 1;

  String encodeManifest(InterlinearManifest manifest) => encodeJson({
        'schemaVersion': schemaVersion,
        'bookNamespace': 'USFM',
        'metadata': _metadataJson(manifest.metadata),
        'chapters': [...manifest.chapters]..sort((a, b) =>
            chapterKey(a.book, a.chapter)
                .compareTo(chapterKey(b.book, b.chapter))),
        'attribution': _resourceJson(manifest.attribution),
      }, convertResources: true);

  InterlinearManifest decodeManifest(String text) => _decode(() {
        final root = _object(jsonDecode(text), 'manifest');
        _fields(root, {
          'schemaVersion',
          'bookNamespace',
          'metadata',
          'chapters',
          'attribution'
        });
        _version(root);
        if (_string(root, 'bookNamespace') != 'USFM') {
          _bad('Unknown book namespace');
        }
        final metadata = _metadata(_object(root['metadata'], 'metadata'));
        final chapters = _list(root, 'chapters').map((value) {
          final item = _object(value, 'chapter resource');
          _fields(item, {'book', 'chapter', 'path', 'sha256'});
          return InterlinearChapterResource(
              book: _book(_string(item, 'book')),
              chapter: _integer(item, 'chapter'),
              path: _string(item, 'path'),
              sha256: _string(item, 'sha256'));
        });
        return InterlinearManifest(
            metadata: metadata,
            chapters: chapters,
            attribution:
                _resource(_object(root['attribution'], 'attribution')));
      });

  String encodeChapter(InterlinearChapter chapter) => encodeJson({
        'schemaVersion': schemaVersion,
        'book': chapter.book.usfmIdentifier,
        'chapter': chapter.chapter,
        'verses': chapter.verses
            .map((verse) => {
                  'label': verse.location.verseLabel,
                  'tokens': verse.tokens.map(_tokenJson).toList(),
                  'surfaceText': verse.surfaceText,
                  'textIsReconstructed': verse.textIsReconstructed,
                  'provenance': verse.provenance,
                })
            .toList(),
        'specialEntries': chapter.specialEntries
            .map((entry) => {
                  'sourceLabel': entry.sourceLabel,
                  'kind': entry.kind,
                  'tokens': entry.tokens.map(_tokenJson).toList(),
                  'surfaceText': entry.surfaceText,
                  'provenance': entry.provenance,
                })
            .toList(),
      });

  InterlinearChapter decodeChapter(String text) => _decode(
      () => _chapterSteps(_object(jsonDecode(text), 'chapter'), 64).last!);

  /// Constructs and validates tokens in bounded batches using the same decoder
  /// as [decodeChapter]. Callers supply scheduling; JSON parsing itself remains
  /// synchronous. A complete valid chapter is returned, never a partial result.
  Future<InterlinearChapter> decodeChapterAsync(String text,
      {required Future<void> Function() yieldControl,
      int batchSize = 64}) async {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    try {
      final root = _object(jsonDecode(text), 'chapter');
      await yieldControl();
      for (final result in _chapterSteps(root, batchSize)) {
        if (result != null) return result;
        await yieldControl();
      }
      throw StateError('The chapter decoder produced no result.');
    } catch (error, stack) {
      _decodeFailure(error, stack);
    }
  }

  Iterable<InterlinearChapter?> _chapterSteps(
      Map<String, Object?> root, int batchSize) sync* {
    _fields(root,
        const {'schemaVersion', 'book', 'chapter', 'verses', 'specialEntries'});
    _version(root);
    final book = _book(_string(root, 'book'));
    final chapter = _integer(root, 'chapter');
    final verses = <InterlinearVerse>[];
    final specialEntries = <InterlinearSpecialEntry>[];
    var batchTokens = 0;
    for (final value in _list(root, 'verses')) {
      final item = _object(value, 'verse');
      _fields(item, const {
        'label',
        'tokens',
        'surfaceText',
        'textIsReconstructed',
        'provenance'
      });
      final label = _string(item, 'label');
      final parsed = VerseLabel.parse(label);
      final tokens = <InterlinearToken>[];
      for (final raw in _list(item, 'tokens')) {
        tokens.add(_token(raw));
        if (++batchTokens == batchSize) {
          batchTokens = 0;
          yield null;
        }
      }
      verses.add(InterlinearVerse(
          location: BibleLocation.checked(
              book: book,
              chapter: chapter,
              verse: parsed.startVerse,
              verseLabel: label),
          tokens: tokens,
          surfaceText: _optionalString(item, 'surfaceText'),
          textIsReconstructed: _boolean(item, 'textIsReconstructed'),
          provenance: _strings(item, 'provenance')));
    }
    for (final value in _list(root, 'specialEntries')) {
      final item = _object(value, 'special entry');
      _fields(item,
          const {'sourceLabel', 'kind', 'tokens', 'surfaceText', 'provenance'});
      final tokens = <InterlinearToken>[];
      for (final raw in _list(item, 'tokens')) {
        tokens.add(_token(raw));
        if (++batchTokens == batchSize) {
          batchTokens = 0;
          yield null;
        }
      }
      specialEntries.add(InterlinearSpecialEntry(
          sourceLabel: _string(item, 'sourceLabel'),
          kind: _string(item, 'kind'),
          tokens: tokens,
          surfaceText: _optionalString(item, 'surfaceText'),
          provenance: _strings(item, 'provenance')));
    }
    yield InterlinearChapter(
        book: book,
        chapter: chapter,
        verses: verses,
        specialEntries: specialEntries);
  }

  String encodeJson(Object? value, {bool convertResources = false}) {
    Object? canonical(Object? value) {
      if (convertResources && value is InterlinearChapterResource) {
        return canonical({
          ..._resourceJson(value),
          'book': value.book.usfmIdentifier,
          'chapter': value.chapter
        });
      }
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      if (value is Iterable) return value.map(canonical).toList();
      return value;
    }

    return '${jsonEncode(canonical(value))}\n';
  }

  Map<String, Object?> _metadataJson(InterlinearMetadata m) => {
        'datasetId': m.datasetId,
        'datasetRevision': m.datasetRevision,
        'schemaVersion': m.schemaVersion,
        'source': m.source,
        'sourceRevision': m.sourceRevision,
        'profile': m.profile,
        'readingPolicy': m.readingPolicy,
        'referenceSystem': m.referenceSystem,
        'originalLanguages': m.originalLanguages,
        'glossLanguages': m.glossLanguages,
        'coverage': {
          for (final e in m.coverage.entries)
            e.key.usfmIdentifier: [...e.value]..sort()
        },
        'provenance': m.provenance,
        'attribution': m.attribution,
      };
  InterlinearMetadata _metadata(Map<String, Object?> m) {
    _fields(m, {
      'datasetId',
      'datasetRevision',
      'schemaVersion',
      'source',
      'sourceRevision',
      'profile',
      'readingPolicy',
      'referenceSystem',
      'originalLanguages',
      'glossLanguages',
      'coverage',
      'provenance',
      'attribution'
    });
    _version(m);
    final coverage = _object(m['coverage'], 'coverage');
    return InterlinearMetadata(
        datasetId: _string(m, 'datasetId'),
        datasetRevision: _string(m, 'datasetRevision'),
        schemaVersion: _integer(m, 'schemaVersion'),
        source: _string(m, 'source'),
        sourceRevision: _string(m, 'sourceRevision'),
        profile: _string(m, 'profile'),
        readingPolicy: _optionalString(m, 'readingPolicy'),
        referenceSystem: _string(m, 'referenceSystem'),
        originalLanguages: _stringList(m, 'originalLanguages'),
        glossLanguages: _stringList(m, 'glossLanguages'),
        coverage: {
          for (final e in coverage.entries)
            _book(e.key): _intList(e.value, 'coverage.${e.key}')
        },
        provenance: _strings(m, 'provenance'),
        attribution: _strings(m, 'attribution'));
  }

  Map<String, Object?> _resourceJson(InterlinearResource r) =>
      {'path': r.path, 'sha256': r.sha256};
  InterlinearResource _resource(Map<String, Object?> r) {
    _fields(r, {'path', 'sha256'});
    return InterlinearResource(
        path: _string(r, 'path'), sha256: _string(r, 'sha256'));
  }

  Map<String, Object?> _tokenJson(InterlinearToken t) => {
        'occurrenceId': t.occurrenceId,
        'sourceRecordId': t.sourceRecordId,
        'surface': t.surface,
        'language': t.language,
        'transliteration': t.transliteration,
        'glosses': t.glosses,
        'separatorAfter': t.separatorAfter,
        'sourceText': t.sourceText,
        'segments': t.segments
            .map((s) => {
                  'text': s.text,
                  'kind': s.kind,
                  'lemma': s.lemma,
                  'glosses': s.glosses,
                  'lexicalReferences': s.lexicalReferences
                      .map((l) => {
                            'system': l.system,
                            'value': l.value,
                            'traditionalStrongs': l.traditionalStrongs
                          })
                      .toList(),
                  'morphology': s.morphology
                      .map((m) => {'scheme': m.scheme, 'code': m.code})
                      .toList()
                })
            .toList(),
      };
  InterlinearToken _token(Object? value) {
    final t = _object(value, 'token');
    _fields(t, const {
      'occurrenceId',
      'sourceRecordId',
      'surface',
      'language',
      'transliteration',
      'glosses',
      'separatorAfter',
      'sourceText',
      'segments'
    });
    return InterlinearToken(
        occurrenceId: _string(t, 'occurrenceId'),
        sourceRecordId: _optionalString(t, 'sourceRecordId'),
        surface: _string(t, 'surface', allowEmpty: true),
        language: _string(t, 'language'),
        transliteration: _optionalString(t, 'transliteration'),
        glosses: _strings(t, 'glosses'),
        separatorAfter: _string(t, 'separatorAfter', allowEmpty: true),
        sourceText: _optionalString(t, 'sourceText'),
        segments: _list(t, 'segments').map((value) {
          final s = _object(value, 'segment');
          _fields(s, const {
            'text',
            'kind',
            'lemma',
            'glosses',
            'lexicalReferences',
            'morphology'
          });
          return InterlinearSegment(
              text: _optionalString(s, 'text'),
              kind: _optionalString(s, 'kind'),
              lemma: _optionalString(s, 'lemma'),
              glosses: _strings(s, 'glosses'),
              lexicalReferences: _list(s, 'lexicalReferences').map((value) {
                final l = _object(value, 'lexical reference');
                _fields(l, const {'system', 'value', 'traditionalStrongs'});
                return LexicalReference(
                    system: _string(l, 'system'),
                    value: _string(l, 'value'),
                    traditionalStrongs:
                        _optionalString(l, 'traditionalStrongs'));
              }).toList(),
              morphology: _list(s, 'morphology').map((value) {
                final m = _object(value, 'morphology');
                _fields(m, const {'scheme', 'code'});
                return MorphologyTag(
                    scheme: _string(m, 'scheme'), code: _string(m, 'code'));
              }).toList());
        }).toList());
  }

  T _decode<T>(T Function() read) {
    try {
      return read();
    } catch (error, stack) {
      _decodeFailure(error, stack);
    }
  }

  Never _decodeFailure(Object error, StackTrace stack) {
    if (error is InterlinearException) Error.throwWithStackTrace(error, stack);
    if (error is ParseVerseRefError) {
      Error.throwWithStackTrace(
          InterlinearDataException('invalid_verse_label', error.toString(),
              path: 'label', cause: error),
          stack);
    }
    if (error is FormatException) {
      Error.throwWithStackTrace(
          InterlinearDataException('malformed_json', error.message,
              cause: error),
          stack);
    }
    if (error is ArgumentError) {
      Error.throwWithStackTrace(
          InterlinearDataException('invalid_model', error.toString(),
              cause: error),
          stack);
    }
    Error.throwWithStackTrace(error, stack);
  }

  Never _bad(String message) =>
      throw InterlinearDataException('malformed_json', message);
  void _version(Map<String, Object?> value) {
    final version = _integer(value, 'schemaVersion');
    if (version != schemaVersion) {
      throw InterlinearDataException(
          'unsupported_schema', 'Unsupported schema version: $version');
    }
  }

  Map<String, Object?> _object(Object? value, String field) {
    if (value is! Map<String, dynamic>) _bad('$field must be an object');
    return value;
  }

  void _fields(Map<String, Object?> value, Set<String> allowed) {
    final unknown = value.keys.where((k) => !allowed.contains(k));
    if (unknown.isNotEmpty) _bad('Unknown fields: ${unknown.join(', ')}');
    final missing = allowed.where((k) => !value.containsKey(k));
    if (missing.isNotEmpty) _bad('Missing fields: ${missing.join(', ')}');
  }

  String _string(Map<String, Object?> m, String key,
      {bool allowEmpty = false}) {
    final value = m[key];
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      _bad('$key must be ${allowEmpty ? 'a' : 'a nonempty'} string');
    }
    return value;
  }

  String? _optionalString(Map<String, Object?> m, String key) =>
      m[key] == null ? null : _string(m, key, allowEmpty: true);
  int _integer(Map<String, Object?> m, String key) {
    final value = m[key];
    if (value is! int) _bad('$key must be an integer');
    return value;
  }

  bool _boolean(Map<String, Object?> m, String key) {
    final value = m[key];
    if (value is! bool) _bad('$key must be a boolean');
    return value;
  }

  List<Object?> _list(Map<String, Object?> m, String key) {
    final value = m[key];
    if (value is! List) _bad('$key must be an array');
    return value;
  }

  List<String> _stringList(Map<String, Object?> m, String key) =>
      _list(m, key).map((v) {
        if (v is! String || v.isEmpty) {
          _bad('$key must contain nonempty strings');
        }
        return v;
      }).toList();
  List<int> _intList(Object? value, String key) {
    if (value is! List) _bad('$key must be an array');
    return value.map((v) {
      if (v is! int) _bad('$key must contain integers');
      return v;
    }).toList();
  }

  Map<String, String> _strings(Map<String, Object?> m, String key) {
    final values = _object(m[key], key);
    return values.map((k, v) {
      if (v is! String) _bad('$key.$k must be a string');
      return MapEntry(k, v);
    });
  }

  BibleBookEnum _book(String value) {
    final book = bibleBookFromUsfmIdentifier(value);
    if (book.usfmIdentifier != value) {
      _bad('Unknown or noncanonical USFM book: $value');
    }
    return book;
  }
}

/// Fully validated resources ready for an application-specific writer.
class PreparedInterlinearDataset {
  final InterlinearManifest manifest;
  final Map<String, List<int>> resources;
  PreparedInterlinearDataset._(this.manifest, Map<String, List<int>> resources)
      : resources = Map.unmodifiable(
            resources.map((k, v) => MapEntry(k, List<int>.unmodifiable(v))));

  factory PreparedInterlinearDataset.build(
      {required InterlinearMetadata metadata,
      required Iterable<InterlinearChapter> chapters}) {
    const codec = InterlinearJsonCodec();
    if (metadata.schemaVersion != InterlinearJsonCodec.schemaVersion) {
      throw InterlinearDataException('unsupported_schema',
          'Cannot encode metadata schema ${metadata.schemaVersion}');
    }
    final resources = <String, List<int>>{};
    final entries = <InterlinearChapterResource>[];
    final occurrenceIds = <String>{};
    for (final chapter in chapters) {
      for (final token in [
        ...chapter.verses.expand((v) => v.tokens),
        ...chapter.specialEntries.expand((e) => e.tokens)
      ]) {
        if (!occurrenceIds.add(token.occurrenceId)) {
          throw InterlinearDataException('duplicate_occurrence',
              'Duplicate occurrence ${token.occurrenceId}');
        }
      }
      final path = 'chapters/${chapterKey(chapter.book, chapter.chapter)}.json';
      final bytes = utf8.encode(codec.encodeChapter(chapter));
      resources[path] = bytes;
      entries.add(InterlinearChapterResource(
          book: chapter.book,
          chapter: chapter.chapter,
          path: path,
          sha256: resourceSha256(bytes)));
    }
    final attributionBytes = utf8.encode(codec.encodeJson({
      'schemaVersion': 1,
      'datasetId': metadata.datasetId,
      'datasetRevision': metadata.datasetRevision,
      'source': metadata.source,
      'sourceRevision': metadata.sourceRevision,
      'attribution': metadata.attribution,
      'provenance': metadata.provenance
    }));
    resources['attribution.json'] = attributionBytes;
    final manifest = InterlinearManifest(
        metadata: metadata,
        chapters: entries,
        attribution: InterlinearResource(
            path: 'attribution.json',
            sha256: resourceSha256(attributionBytes)));
    resources['manifest.json'] = utf8.encode(codec.encodeManifest(manifest));
    return PreparedInterlinearDataset._(manifest, resources);
  }
}
