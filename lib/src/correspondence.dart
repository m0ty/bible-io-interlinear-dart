import 'dart:convert';

import 'package:bible_io/bible_io.dart';

import 'data.dart';
import 'errors.dart';
import 'interlinear_bible.dart';
import 'json_codec.dart';
import 'mapping.dart';
import 'models.dart';

/// Exact prepared dataset release against which a correspondence was generated.
final class CorrespondenceDatasetBinding {
  const CorrespondenceDatasetBinding._(this.datasetId, this.datasetRevision,
      this.sourceRevision, this.profile, this.manifestSha256);
  final String datasetId;
  final String datasetRevision;
  final String sourceRevision;
  final String profile;
  final String manifestSha256;

  void _validate(InterlinearMetadata metadata, String referenceSystem) {
    if (metadata.datasetId != datasetId ||
        metadata.datasetRevision != datasetRevision ||
        metadata.sourceRevision != sourceRevision ||
        metadata.profile != profile ||
        metadata.referenceSystem != referenceSystem) {
      throw const InterlinearDataException('correspondence_dataset_mismatch',
          'Dataset identity, profile or reference system differs from its mapping.');
    }
  }
}

/// One explicit edition entry. No identity fallback is inferred.
final class CorrespondenceEntry {
  CorrespondenceEntry._(this.datasetId, this.status,
      List<InterlinearSourceSelection> sources, this.note)
      : sources = List.unmodifiable(sources);
  final String datasetId;
  final VerseMappingStatus status;
  final List<InterlinearSourceSelection> sources;
  final String? note;
}

/// Immutable, schema-validated correspondence and its release bindings.
///
/// Hashes detect inconsistent releases, not untrusted publishers. Applications
/// remain responsible for the trust and authenticity of their mapping document.
final class CorrespondenceIndex {
  CorrespondenceIndex._({
    required this.sourceEdition,
    required this.sourceAssetSha256,
    required this.sourceReferenceSystem,
    required this.sourceRevision,
    required this.targetReferenceSystem,
    required Map<String, CorrespondenceDatasetBinding> datasets,
    required Map<String, CorrespondenceEntry> entries,
    required Map<String, String> provenance,
    required Map<String, int> coverage,
    required List<String> unavailable,
  })  : datasets = Map.unmodifiable(datasets),
        entries = Map.unmodifiable(entries),
        provenance = Map.unmodifiable(provenance),
        coverage = Map.unmodifiable(coverage),
        unavailable = List.unmodifiable(unavailable);

  final String sourceEdition;
  final String sourceAssetSha256;
  final String sourceReferenceSystem;
  final String sourceRevision;
  final String targetReferenceSystem;
  final Map<String, CorrespondenceDatasetBinding> datasets;
  final Map<String, CorrespondenceEntry> entries;
  final Map<String, String> provenance;
  final Map<String, int> coverage;
  final List<String> unavailable;

  /// Validate once against the actual edition content identity supplied by I/O.
  void validateSourceEdition({
    required String editionId,
    required String referenceSystem,
    required String assetSha256,
  }) {
    if (editionId != sourceEdition ||
        referenceSystem != sourceReferenceSystem ||
        assetSha256 != sourceAssetSha256) {
      throw const InterlinearDataException('correspondence_edition_mismatch',
          'The correspondence does not describe this edition and asset content.');
    }
  }

  CorrespondenceEntry? entryFor(BibleLocation location) =>
      location.hasVerse ? entries[correspondenceKey(location)] : null;
}

/// A canonical key for lookup; original source label spelling is retained.
String correspondenceKey(BibleLocation location) {
  if (!location.hasVerse) throw ArgumentError('A verse location is required.');
  final label = VerseLabel.parse(location.verseLabel!);
  BibleLocation.checked(
      book: location.book,
      chapter: location.chapter,
      verse: location.verse,
      verseLabel: location.verseLabel);
  return '${location.book.usfmIdentifier}.${location.chapter}.${label.displayString}';
}

/// Strict decoder for the existing prepared correspondence JSON schema 1.
///
/// Optional fields are accepted only by name. A misspelled occurrence selector
/// is an error, never a request to substitute every word in its source entry.
final class CorrespondenceJsonCodec {
  const CorrespondenceJsonCodec();

  CorrespondenceIndex decode(String text) {
    try {
      return _readSteps(_object(jsonDecode(text), 'index'), 256).last!;
    } catch (error, stack) {
      _decodeFailure(error, stack);
    }
  }

  /// Uses the synchronous validator, yielding between bounded batches. Callers
  /// provide platform scheduling. No partial index is exposed on late errors.
  Future<CorrespondenceIndex> decodeAsync(String text,
      {required Future<void> Function() yieldControl,
      int batchSize = 256}) async {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    try {
      final root = _object(jsonDecode(text), 'index');
      await yieldControl();
      for (final result in _readSteps(root, batchSize)) {
        if (result != null) return result;
        await yieldControl();
      }
      throw StateError('The correspondence validator produced no result.');
    } catch (error, stack) {
      _decodeFailure(error, stack);
    }
  }

  Iterable<CorrespondenceIndex?> _readSteps(
      Map<String, dynamic> root, int batchSize) sync* {
    _fields(root, const {
      'schemaVersion',
      'sourceEdition',
      'sourceEditionSha256',
      'sourceAssetSha256',
      'sourceReferenceSystem',
      'sourceRevision',
      'targetReferenceSystem',
      'datasets',
      'provenance',
      'coverage',
      'entries'
    });
    if (root['schemaVersion'] is! int || root['schemaVersion'] != 1) {
      _bad('Unsupported correspondence schema.');
    }
    final edition = _string(root['sourceEdition']);
    final editionHash = _hash(root['sourceAssetSha256']);
    if (_hash(root['sourceEditionSha256']) != editionHash) {
      _bad('Edition hash aliases disagree.');
    }
    final revision = _string(root['sourceRevision']);
    final datasets = <String, CorrespondenceDatasetBinding>{};
    for (final e in _object(root['datasets'], 'datasets').entries) {
      final id = _string(e.key);
      final value = _object(e.value, 'dataset binding');
      _fields(value, const {
        'datasetRevision',
        'sourceRevision',
        'profile',
        'manifestSha256'
      });
      final sourceRevision = _string(value['sourceRevision']);
      if (sourceRevision != revision) {
        _bad('Dataset source revisions disagree.');
      }
      datasets[id] = CorrespondenceDatasetBinding._(
          id,
          _string(value['datasetRevision']),
          sourceRevision,
          _string(value['profile']),
          _hash(value['manifestSha256']));
    }
    if (datasets.isEmpty) _bad('At least one dataset binding is required.');
    final provenance = _object(root['provenance'], 'provenance');
    _fields(provenance, const {
      'authority',
      'source',
      'license',
      'licenseUrl',
      'evidence',
      'tvtmsSha256',
      'scope',
      'method',
      'modifications'
    });
    _hash(provenance['tvtmsSha256']);
    final entries = <String, CorrespondenceEntry>{};
    final books = <BibleBookEnum>{};
    final chapters = <String>{};
    final unavailableEntries = <String>{};
    var matched = 0;
    var batchEntries = 0;
    for (final e in _object(root['entries'], 'entries').entries) {
      final location = _keyLocation(e.key);
      books.add(location.$1);
      chapters.add('${location.$1.usfmIdentifier}.${location.$2}');
      final value = _object(e.value, 'entry');
      _fields(value, const {'datasetId', 'status', 'sources'},
          optional: const {'note'});
      final id = _string(value['datasetId']);
      if (!datasets.containsKey(id)) _bad('Entry uses an undeclared dataset.');
      final status = switch (value['status']) {
        'matched' => VerseMappingStatus.matched,
        'partial' => VerseMappingStatus.partial,
        'unmapped' => VerseMappingStatus.unmapped,
        'ambiguous' => VerseMappingStatus.ambiguous,
        _ => _bad('Unknown correspondence status.'),
      };
      final sources = <InterlinearSourceSelection>[];
      for (final raw in _list(value['sources'])) {
        final source = _object(raw, 'source selection');
        _fields(source, const {
          'book',
          'chapter'
        }, optional: const {
          'verseLabel',
          'specialEntryLabel',
          'occurrenceIds'
        });
        final book = _book(source['book']);
        final chapter = _positive(source['chapter']);
        // Presence with null is malformed, not a request for the default.
        final verse = source.containsKey('verseLabel')
            ? _string(source['verseLabel'])
            : null;
        final special = source.containsKey('specialEntryLabel')
            ? _string(source['specialEntryLabel'])
            : null;
        final ids = source.containsKey('occurrenceIds')
            ? _list(source['occurrenceIds']).map(_string).toList()
            : null;
        sources.add(InterlinearSourceSelection(
            datasetId: id,
            book: book,
            chapter: chapter,
            verseLabel: verse,
            specialEntryLabel: special,
            occurrenceIds: ids));
      }
      if ((status == VerseMappingStatus.unmapped) != sources.isEmpty) {
        _bad(
            'Unavailable entries require no sources; other entries require sources.');
      }
      if (status == VerseMappingStatus.unmapped) unavailableEntries.add(e.key);
      if (status == VerseMappingStatus.matched) matched++;
      entries[e.key] = CorrespondenceEntry._(id, status, sources,
          value.containsKey('note') ? _string(value['note']) : null);
      if (++batchEntries == batchSize) {
        batchEntries = 0;
        yield null;
      }
    }
    final rawCoverage = _object(root['coverage'], 'coverage');
    const counters = {
      'books',
      'chapters',
      'verses',
      'matched',
      'resegmented',
      'superscriptions',
      'tokens',
      'movedGreekTokens',
      'filteredSources'
    };
    _fields(rawCoverage, {...counters, 'unavailable'});
    final coverage = {
      for (final key in counters) key: _nonnegative(rawCoverage[key])
    };
    final unavailable = _list(rawCoverage['unavailable']).map(_string).toList();
    if (unavailable.toSet().length != unavailable.length ||
        unavailable.length != unavailableEntries.length ||
        !unavailableEntries.containsAll(unavailable) ||
        coverage['books'] != books.length ||
        coverage['chapters'] != chapters.length ||
        coverage['verses'] != entries.length ||
        coverage['matched'] != matched) {
      _bad('Correspondence coverage does not match its explicit entries.');
    }
    yield CorrespondenceIndex._(
        sourceEdition: edition,
        sourceAssetSha256: editionHash,
        sourceReferenceSystem: _string(root['sourceReferenceSystem']),
        sourceRevision: revision,
        targetReferenceSystem: _string(root['targetReferenceSystem']),
        datasets: datasets,
        entries: entries,
        provenance:
            provenance.map((key, value) => MapEntry(key, _string(value))),
        coverage: coverage,
        unavailable: unavailable);
  }
}

/// Trusted platform scheduling for verification and decoding of supplied bytes.
/// Implementations must invoke [decodeVerifiedInterlinearChapter] or its async
/// counterpart with both supplied arguments. This executable adapter is trusted
/// code, like the reader; it is not a data/publisher trust boundary.
typedef VerifiedInterlinearChapterDecoder = Future<InterlinearChapter> Function(
    List<int> bytes, String expectedSha256);

/// A lazy dataset built from one manifest and its resource reader.
/// Construction owns the Bible/source pair, preventing accidental binding of a
/// pre-existing Bible from another release to correct manifest bytes.
final class CorrespondenceDataset {
  CorrespondenceDataset._(
      {required this.bible, required List<int> manifestBytes})
      : manifestBytes = List.unmodifiable(manifestBytes);
  final InterlinearBible bible;
  final List<int> manifestBytes;

  /// [reader] returns uncompressed resources relative to this manifest.
  /// Optional trusted scheduling moves complete verify/decode work to an isolate
  /// or uses cooperative checkpoints; the package owns the resulting chapter cache.
  static Future<CorrespondenceDataset> open({
    required List<int> manifestBytes,
    required InterlinearResourceReader reader,
    VerifiedInterlinearChapterDecoder? verifyAndDecodeChapter,
    int cacheCapacity = 8,
  }) async {
    final pinned = List<int>.unmodifiable(manifestBytes);
    final source = _BoundCorrespondenceSource(
        pinned,
        reader,
        verifyAndDecodeChapter ??
            (bytes, hash) async =>
                decodeVerifiedInterlinearChapter(bytes, hash));
    final bible =
        await InterlinearBible.open(source, cacheCapacity: cacheCapacity);
    return CorrespondenceDataset._(bible: bible, manifestBytes: pinned);
  }
}

class _BoundCorrespondenceSource implements InterlinearDataSource {
  _BoundCorrespondenceSource(List<int> manifestBytes, this.reader, this.decode)
      : manifestSource = JsonInterlinearDataSource(
            reader: (path) async =>
                path == 'manifest.json' ? manifestBytes : reader(path));
  final InterlinearResourceReader reader;
  final VerifiedInterlinearChapterDecoder decode;
  final JsonInterlinearDataSource manifestSource;

  @override
  Future<InterlinearMetadata> loadMetadata() => manifestSource.loadMetadata();

  @override
  Future<InterlinearChapter> loadChapter(
      BibleBookEnum book, int chapter) async {
    final resource =
        (await manifestSource.loadManifest()).resourceFor(book, chapter);
    final List<int> bytes;
    try {
      bytes = await reader(resource.path);
    } on InterlinearException {
      rethrow;
    } catch (error) {
      throw InterlinearResourceException(
          'resource_unavailable', 'Could not read ${resource.path}',
          path: resource.path, cause: error);
    }
    return decode(bytes, resource.sha256);
  }
}

/// Verifies exact uncompressed bytes before strict model decoding.
InterlinearChapter decodeVerifiedInterlinearChapter(
    List<int> bytes, String expectedSha256) {
  _checkChapterHash(resourceSha256(bytes), expectedSha256);
  try {
    return const InterlinearJsonCodec().decodeChapter(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw InterlinearDataException(
        'invalid_utf8', 'Chapter is not valid UTF-8.',
        cause: error);
  }
}

/// Cooperatively verifies and decodes exact bytes, with no partial result.
Future<InterlinearChapter> decodeVerifiedInterlinearChapterAsync(
    List<int> bytes, String expectedSha256,
    {required Future<void> Function() yieldControl,
    Future<void> Function()? yieldBetweenPhases,
    int batchSize = 64}) async {
  _checkChapterHash(
      await resourceSha256Async(bytes, yieldControl: yieldControl),
      expectedSha256);
  await (yieldBetweenPhases ?? yieldControl)();
  try {
    return await const InterlinearJsonCodec().decodeChapterAsync(
        utf8.decode(bytes),
        yieldControl: yieldControl,
        batchSize: batchSize);
  } on FormatException catch (error) {
    throw InterlinearDataException(
        'invalid_utf8', 'Chapter is not valid UTF-8.',
        cause: error);
  }
}

void _checkChapterHash(String actual, String expected) {
  if (actual != expected) {
    throw const InterlinearDataException(
        'integrity_mismatch', 'Chapter bytes do not match the bound manifest.');
  }
}

typedef CorrespondenceDatasetOpener = Future<CorrespondenceDataset> Function(
    CorrespondenceDatasetBinding binding);

/// Original tokens mapped to a separately identified translation location.
/// Native source references remain in [sourceSelections] and token identities.
final class MappedInterlinearPassage {
  MappedInterlinearPassage._(this.translationLocation, this.mapping,
      this.metadata, List<InterlinearToken> tokens)
      : tokens = List.unmodifiable(tokens);
  final BibleLocation translationLocation;
  final VerseMappingResult mapping;
  final InterlinearMetadata? metadata;
  final List<InterlinearToken> tokens;
  List<InterlinearSourceSelection> get sourceSelections =>
      mapping.sourceSelections;
  String get reconstructedText => tokens
      .map((token) => '${token.surface}${token.separatorAfter}')
      .join()
      .trimRight();
}

/// Resolves typed correspondence using injected, lazy datasets.
///
/// Each successful dataset binding is verified once. Concurrent opens share a
/// future, and failed opens remain retryable. The datasets own chapter caching.
final class CorrespondenceResolver {
  CorrespondenceResolver({required this.index, required this.openDataset});
  final CorrespondenceIndex index;
  final CorrespondenceDatasetOpener openDataset;
  final _datasets = <String, Future<InterlinearBible>>{};

  Future<InterlinearBible> _open(String id) {
    if (_datasets[id] case final existing?) return existing;
    final pending = _openBound(index.datasets[id]!);
    _datasets[id] = pending;
    pending.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      if (identical(_datasets[id], pending)) _datasets.remove(id);
    });
    return pending;
  }

  Future<InterlinearBible> _openBound(
      CorrespondenceDatasetBinding binding) async {
    final loaded = await openDataset(binding);
    if (resourceSha256(loaded.manifestBytes) != binding.manifestSha256) {
      throw const InterlinearDataException('correspondence_manifest_mismatch',
          'Loaded manifest does not match the correspondence dataset release.');
    }
    const codec = InterlinearJsonCodec();
    final manifest = codec.decodeManifest(utf8.decode(loaded.manifestBytes));
    binding._validate(manifest.metadata, index.targetReferenceSystem);
    binding._validate(loaded.bible.metadata, index.targetReferenceSystem);
    // Check complete metadata, including reading policy and attribution,
    // before exposing the dataset alongside its bound manifest.
    final actual = InterlinearManifest(
        metadata: loaded.bible.metadata,
        chapters: manifest.chapters,
        attribution: manifest.attribution);
    if (codec.encodeManifest(actual) != codec.encodeManifest(manifest)) {
      throw const InterlinearDataException('correspondence_dataset_mismatch',
          'Opened dataset metadata differs from its bound manifest.');
    }
    return loaded.bible;
  }

  Future<MappedInterlinearPassage> resolve(
      BibleLocation translationLocation) async {
    final key = correspondenceKey(translationLocation);
    final entry = index.entries[key];
    if (entry == null || entry.status == VerseMappingStatus.unmapped) {
      return MappedInterlinearPassage._(
          translationLocation,
          VerseMappingResult(
              status: VerseMappingStatus.unmapped,
              note: entry?.note ?? 'No correspondence for this exact verse.'),
          null,
          []);
    }
    final targets = <String, BibleLocation>{};
    for (final source in entry.sources) {
      if (source.verseLocation case final location?) {
        targets.putIfAbsent(correspondenceKey(location), () => location);
      }
    }
    final mapping = VerseMappingResult(
        status: entry.status,
        targets: targets.values.toList(),
        sourceSelections: entry.sources,
        note: entry.note,
        provenance: {...index.provenance, 'entry': key});
    // Alternatives remain alternatives; never concatenate an ambiguous result.
    if (entry.status == VerseMappingStatus.ambiguous) {
      return MappedInterlinearPassage._(translationLocation, mapping, null, []);
    }
    final bible = await _open(entry.datasetId);
    final tokens = <InterlinearToken>[];
    final occurrences = <String>{};
    for (final source in entry.sources) {
      final chapter = await bible.loadChapter(source.book, source.chapter);
      final List<InterlinearToken> original;
      if (source.specialEntryLabel case final label?) {
        final matches = chapter.specialEntries
            .where((e) => e.sourceLabel == label)
            .toList();
        if (matches.length != 1) _bad('Mapped source heading is missing.');
        original = matches.single.tokens;
      } else {
        original = chapter.getVerseByLabel(source.verseLabel!).tokens;
      }
      final selected = <InterlinearToken>[];
      if (source.occurrenceIds case final ids?) {
        final byId = {for (final token in original) token.occurrenceId: token};
        for (final id in ids) {
          final token = byId[id];
          if (token == null) {
            _bad('Mapped word is missing from its exact source entry.');
          }
          selected.add(token);
        }
      } else {
        selected.addAll(original);
      }
      for (final token in selected) {
        if (!occurrences.add(token.occurrenceId)) {
          _bad('Mapping duplicates an original occurrence.');
        }
        tokens.add(token);
      }
    }
    if (tokens.isEmpty) {
      _bad('Mapped correspondence contains no original words.');
    }
    return MappedInterlinearPassage._(
        translationLocation, mapping, bible.metadata, tokens);
  }
}

Never _bad(String message) =>
    throw InterlinearDataException('invalid_mapping', message);
Map<String, dynamic> _object(Object? value, String field) =>
    value is Map<String, dynamic> ? value : _bad('$field must be an object.');
List<dynamic> _list(Object? value) =>
    value is List ? value : _bad('Expected an array.');
String _string(Object? value) =>
    value is String && value.trim().isNotEmpty && value.trim() == value
        ? value
        : _bad('Expected nonblank text without surrounding whitespace.');
String _hash(Object? value) {
  final hash = _string(value);
  if (!_sha256Pattern.hasMatch(hash)) {
    _bad('Expected a lowercase SHA-256.');
  }
  return hash;
}

int _nonnegative(Object? value) => value is int && value >= 0
    ? value
    : _bad('Expected a nonnegative integer.');
int _positive(Object? value) =>
    value is int && value > 0 ? value : _bad('Expected a positive integer.');
void _fields(Map<String, dynamic> value, Set<String> required,
    {Set<String> optional = const {}}) {
  if (value.keys
          .any((key) => !required.contains(key) && !optional.contains(key)) ||
      required.any((key) => !value.containsKey(key))) {
    _bad('Unknown or missing correspondence fields: ${value.keys.join(', ')}.');
  }
}

BibleBookEnum _book(Object? value) {
  final id = _string(value);
  final book = _booksById[id];
  if (book == null) _bad('Unknown or noncanonical source book.');
  return book;
}

(BibleBookEnum, int) _keyLocation(String key) {
  final match = _entryKeyPattern.firstMatch(key);
  if (match == null) _bad('Invalid correspondence entry key.');
  final book = _book(match[1]);
  final label = VerseLabel.parse(match[3]!);
  if (label.displayString != match[3]) {
    _bad('Noncanonical correspondence entry key.');
  }
  return (book, int.parse(match[2]!));
}

final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
final _entryKeyPattern = RegExp(r'^([A-Z0-9]{3})\.([1-9][0-9]*)\.(.+)$');
final _booksById = {
  for (final book in BibleBookEnum.values) book.usfmIdentifier: book
};

Never _decodeFailure(Object error, StackTrace stack) {
  if (error is InterlinearException) Error.throwWithStackTrace(error, stack);
  if (error is ParseVerseRefError ||
      error is ArgumentError ||
      error is FormatException) {
    Error.throwWithStackTrace(
        InterlinearDataException('invalid_mapping',
            error is FormatException ? error.message : error.toString(),
            cause: error),
        stack);
  }
  Error.throwWithStackTrace(error, stack);
}
