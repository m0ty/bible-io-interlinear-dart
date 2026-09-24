import 'dart:convert';

import 'package:bible_io/bible_io.dart';

import 'errors.dart';
import 'json_codec.dart';
import 'models.dart';

/// Applications supply filesystem, asset, HTTP, database, or other I/O here.
typedef InterlinearResourceReader = Future<List<int>> Function(String path);

abstract interface class InterlinearDataSource {
  Future<InterlinearMetadata> loadMetadata();
  Future<InterlinearChapter> loadChapter(BibleBookEnum book, int chapter);
}

class MemoryInterlinearDataSource implements InterlinearDataSource {
  final InterlinearMetadata metadata;
  final Map<String, InterlinearChapter> _chapters;
  MemoryInterlinearDataSource(
      {required this.metadata, required Iterable<InterlinearChapter> chapters})
      : _chapters = _validatedChapters(metadata, chapters);

  static Map<String, InterlinearChapter> _validatedChapters(
      InterlinearMetadata metadata, Iterable<InterlinearChapter> chapters) {
    final values = List<InterlinearChapter>.of(chapters);
    // Validate the original sequence before indexing so duplicate chapters
    // cannot disappear through map-key replacement.
    PreparedInterlinearDataset.build(metadata: metadata, chapters: values);
    return Map.unmodifiable({
      for (final value in values) chapterKey(value.book, value.chapter): value
    });
  }

  @override
  Future<InterlinearMetadata> loadMetadata() async => metadata;
  @override
  Future<InterlinearChapter> loadChapter(
      BibleBookEnum book, int chapter) async {
    final key = chapterKey(book, chapter);
    final result = _chapters[key];
    if (result == null) {
      throw UnsupportedCoverageException(
          'unsupported_coverage', 'No chapter $key');
    }
    return result;
  }
}

/// Reads only the manifest and attribution on open, then requested chapters.
/// SHA-256 checks detect corruption; a trusted manifest must be supplied by the
/// application. They do not authenticate an untrusted publisher.
class JsonInterlinearDataSource implements InterlinearDataSource {
  final InterlinearResourceReader reader;
  final String manifestPath;
  final InterlinearJsonCodec codec;
  Future<InterlinearManifest>? _manifest;
  JsonInterlinearDataSource(
      {required this.reader,
      this.manifestPath = 'manifest.json',
      this.codec = const InterlinearJsonCodec()}) {
    validateResourcePath(manifestPath);
  }

  Future<List<int>> _read(String path) async {
    validateResourcePath(path);
    try {
      final bytes = List<int>.of(await reader(path));
      if (bytes.any((value) => value < 0 || value > 255)) {
        throw InterlinearDataException(
            'invalid_bytes', 'Resource contains values outside byte range',
            path: path);
      }
      return bytes;
    } on InterlinearException {
      rethrow;
    } catch (error) {
      throw InterlinearResourceException(
          'resource_unavailable', 'Could not read $path',
          path: path, cause: error);
    }
  }

  String _text(List<int> bytes, String path) {
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw InterlinearDataException('invalid_utf8', 'Invalid UTF-8 in $path',
          path: path, cause: error);
    }
  }

  Future<List<int>> _verified(InterlinearResource resource) async {
    final bytes = await _read(resource.path);
    if (resourceSha256(bytes) != resource.sha256) {
      throw InterlinearDataException(
          'integrity_mismatch', 'SHA-256 mismatch for ${resource.path}',
          path: resource.path);
    }
    return bytes;
  }

  Future<InterlinearManifest> loadManifest() {
    if (_manifest case final pending?) return pending;
    final pending = _loadManifest();
    _manifest = pending;
    // Attach a nonthrowing cleanup handler without creating an unhandled future.
    pending.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      if (identical(_manifest, pending)) _manifest = null;
    });
    return pending;
  }

  Future<InterlinearManifest> _loadManifest() async {
    final manifest =
        codec.decodeManifest(_text(await _read(manifestPath), manifestPath));
    final bytes = await _verified(manifest.attribution);
    try {
      final value = jsonDecode(_text(bytes, manifest.attribution.path));
      final expected = {
        'schemaVersion': 1,
        'datasetId': manifest.metadata.datasetId,
        'datasetRevision': manifest.metadata.datasetRevision,
        'source': manifest.metadata.source,
        'sourceRevision': manifest.metadata.sourceRevision,
        'attribution': manifest.metadata.attribution,
        'provenance': manifest.metadata.provenance
      };
      if (value is! Map<String, dynamic> ||
          codec.encodeJson(value) != codec.encodeJson(expected)) {
        throw const FormatException(
            'Attribution does not match manifest metadata');
      }
    } on FormatException catch (error) {
      throw InterlinearDataException('invalid_attribution', error.message,
          path: manifest.attribution.path, cause: error);
    }
    return manifest;
  }

  @override
  Future<InterlinearMetadata> loadMetadata() async =>
      (await loadManifest()).metadata;
  @override
  Future<InterlinearChapter> loadChapter(
      BibleBookEnum book, int chapter) async {
    final resource = (await loadManifest()).resourceFor(book, chapter);
    final decoded =
        codec.decodeChapter(_text(await _verified(resource), resource.path));
    if (decoded.book != book || decoded.chapter != chapter) {
      throw InterlinearDataException(
          'chapter_mismatch', 'Resource has the wrong chapter identity',
          path: resource.path);
    }
    return decoded;
  }
}
