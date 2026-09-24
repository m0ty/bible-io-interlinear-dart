import 'package:bible_io/bible_io.dart';

import 'data.dart';
import 'errors.dart';
import 'json_codec.dart';
import 'models.dart';

/// A lazy dataset with a bounded least-recently-used chapter cache.
class InterlinearBible {
  final InterlinearMetadata metadata;
  final InterlinearDataSource _source;
  final int cacheCapacity;
  final _cache = <String, InterlinearChapter>{};
  final _pending = <String, Future<InterlinearChapter>>{};
  InterlinearBible._(this._source, this.metadata, this.cacheCapacity);

  static Future<InterlinearBible> open(InterlinearDataSource source,
      {int cacheCapacity = 8}) async {
    if (cacheCapacity < 0) {
      throw ArgumentError.value(
          cacheCapacity, 'cacheCapacity', 'must be nonnegative');
    }
    return InterlinearBible._(
        source, await source.loadMetadata(), cacheCapacity);
  }

  int get cachedChapterCount => _cache.length;

  /// Pending requests may populate the cache after this method returns.
  void clearCache() => _cache.clear();

  Future<InterlinearChapter> loadChapter(BibleBookEnum book, int chapter) {
    if (!(metadata.coverage[book]?.contains(chapter) ?? false)) {
      return Future.error(UnsupportedCoverageException('unsupported_coverage',
          'No coverage for ${chapterKey(book, chapter)}'));
    }
    final key = chapterKey(book, chapter);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    if (_pending[key] case final request?) return request;
    final request = _load(book, chapter, key);
    _pending[key] = request;
    request.then<void>((_) {
      _pending.remove(key);
    }, onError: (Object error, StackTrace stack) {
      _pending.remove(key);
    });
    return request;
  }

  Future<InterlinearChapter> _load(
      BibleBookEnum book, int chapter, String key) async {
    final value = await _source.loadChapter(book, chapter);
    if (value.book != book || value.chapter != chapter) {
      throw InterlinearDataException(
          'chapter_mismatch', 'Source returned the wrong chapter for $key');
    }
    if (cacheCapacity > 0) {
      _cache[key] = value;
      while (_cache.length > cacheCapacity) {
        _cache.remove(_cache.keys.first);
      }
    }
    return value;
  }

  Future<InterlinearVerse> loadVerse(BibleLocation location) async =>
      (await loadChapter(location.book, location.chapter)).getVerseAt(location);
}
