import 'package:bible_io/bible_io.dart';

import 'errors.dart';

/// Identity, coverage, provenance and licensing of one prepared dataset.
///
/// [profile] identifies selected original text; [datasetRevision] identifies
/// this conversion; [referenceSystem] identifies verse numbering. None implies
/// that references in another edition correspond to this dataset.
final class InterlinearMetadata {
  InterlinearMetadata({
    required String datasetId,
    required String datasetRevision,
    required String source,
    required String sourceRevision,
    required String profile,
    required String referenceSystem,
    required List<String> originalLanguages,
    required List<String> glossLanguages,
    required Map<BibleBookEnum, List<int>> coverage,
    this.schemaVersion = 1,
    this.readingPolicy,
    Map<String, String> provenance = const {},
    Map<String, String> attribution = const {},
  })  : datasetId = _required(datasetId, 'datasetId'),
        datasetRevision = _required(datasetRevision, 'datasetRevision'),
        source = _required(source, 'source'),
        sourceRevision = _required(sourceRevision, 'sourceRevision'),
        profile = _required(profile, 'profile'),
        referenceSystem = _required(referenceSystem, 'referenceSystem'),
        originalLanguages = _strings(originalLanguages, 'originalLanguages'),
        glossLanguages = _strings(glossLanguages, 'glossLanguages'),
        coverage = _coverage(coverage),
        provenance = _stringMap(provenance, 'provenance'),
        attribution = _stringMap(attribution, 'attribution') {
    if (schemaVersion != 1) {
      throw const InterlinearDataException(
        'unsupported_schema',
        'Only interlinear schema version 1 is supported.',
      );
    }
    if (readingPolicy != null) _required(readingPolicy!, 'readingPolicy');
    if (this.originalLanguages.isEmpty) {
      throw ArgumentError.value(
          originalLanguages, 'originalLanguages', 'must not be empty');
    }
  }

  final String datasetId;
  final String datasetRevision;
  final int schemaVersion;
  final String source;
  final String sourceRevision;
  final String profile;
  final String? readingPolicy;
  final String referenceSystem;
  final List<String> originalLanguages;
  final List<String> glossLanguages;
  final Map<BibleBookEnum, List<int>> coverage;
  final Map<String, String> provenance;
  final Map<String, String> attribution;
}

/// An immutable chapter, with synchronous source-label and numeric lookup.
final class InterlinearChapter {
  InterlinearChapter({
    required this.book,
    required this.chapter,
    required List<InterlinearVerse> verses,
    List<InterlinearSpecialEntry> specialEntries = const [],
  })  : verses = _prepareVerses(book, chapter, verses),
        specialEntries = List.unmodifiable(specialEntries) {
    if (this.verses.isEmpty && this.specialEntries.isEmpty) {
      throw ArgumentError('A chapter must contain a verse or a special entry.');
    }
    final occurrences = <String>{};
    for (final token in [
      for (final verse in this.verses) ...verse.tokens,
      for (final entry in this.specialEntries) ...entry.tokens,
    ]) {
      if (!occurrences.add(token.occurrenceId)) {
        throw ArgumentError.value(
            token.occurrenceId, 'occurrenceId', 'duplicate in chapter');
      }
    }
    final labels = <String>{};
    for (final entry in this.specialEntries) {
      if (!labels.add(entry.sourceLabel)) {
        throw ArgumentError.value(
            entry.sourceLabel, 'sourceLabel', 'duplicate special entry');
      }
    }
    _byLabel = Map.unmodifiable({
      for (final verse in this.verses) verse.label.displayString: verse,
    });
  }

  final BibleBookEnum book;
  final int chapter;
  final List<InterlinearVerse> verses;
  final List<InterlinearSpecialEntry> specialEntries;
  late final Map<String, InterlinearVerse> _byLabel;

  /// Finds an exact declared label after Bible-IO syntax normalization.
  InterlinearVerse getVerseByLabel(String verseLabel) {
    final verse = _byLabel[VerseLabel.parse(verseLabel).displayString];
    if (verse == null) {
      throw InterlinearVerseNotFoundException(
        'missing_verse',
        'No source entry for ${book.fullName} $chapter:$verseLabel.',
      );
    }
    return verse;
  }

  /// Finds the unique source entry covering a number or subdivision.
  ///
  /// Either 29 or 30 finds `29-30`; `5` is ambiguous when `5a` and `5b` exist.
  InterlinearVerse getVerse(int verse, {String? subdivision}) {
    final matches = getVersesByNumber(verse, subdivision: subdivision);
    if (matches.isEmpty) {
      throw InterlinearVerseNotFoundException(
        'missing_verse',
        'No source entry covers ${book.fullName} $chapter:$verse${subdivision ?? ''}.',
      );
    }
    if (matches.length > 1) {
      throw InterlinearAmbiguousVerseException(
        'ambiguous_verse',
        'Several source entries cover $verse; specify a subdivision or exact label.',
      );
    }
    return matches.single;
  }

  /// All entries intersecting the requested whole verse or subdivision.
  List<InterlinearVerse> getVersesByNumber(int verse, {String? subdivision}) {
    final query = VerseLabel.parse('$verse${subdivision ?? ''}');
    final start = _start(query);
    final end = _end(query);
    return List.unmodifiable(verses.where(
      (entry) => _start(entry.label) <= end && _end(entry.label) >= start,
    ));
  }

  /// Resolves a label-bearing Bible-IO location within this chapter.
  InterlinearVerse getVerseAt(BibleLocation location) {
    final checked = _location(location);
    if (checked.book != book || checked.chapter != chapter) {
      throw InterlinearVerseNotFoundException(
        'wrong_chapter',
        'Location $checked does not belong to ${book.fullName} $chapter.',
      );
    }
    final label = VerseLabel.parse(checked.verseLabel!);
    if (label.isCombined) {
      return getVerseByLabel(label.source);
    }
    return getVerse(checked.verse!, subdivision: label.startSubdivision);
  }
}

/// A source verse entry. Exact subdivided and combined labels are preserved.
final class InterlinearVerse {
  InterlinearVerse({
    required BibleLocation location,
    required List<InterlinearToken> tokens,
    this.surfaceText,
    this.textIsReconstructed = false,
    Map<String, String> provenance = const {},
  })  : location = _location(location),
        tokens = _tokens(tokens),
        provenance = _stringMap(provenance, 'provenance');

  final BibleLocation location;
  final List<InterlinearToken> tokens;
  final String? surfaceText;
  final bool textIsReconstructed;
  final Map<String, String> provenance;

  VerseLabel get label => VerseLabel.parse(location.verseLabel!);

  /// Display text reconstructed from token surfaces and declared separators.
  /// This is not a verified published-edition transcription.
  String get reconstructedText => _reconstruct(tokens);
}

/// A heading, superscription or other source entry without a positive verse.
///
/// This intentionally has no invented verse [BibleLocation]. Its containing
/// chapter identifies the book/chapter and [sourceLabel] retains the source key.
final class InterlinearSpecialEntry {
  InterlinearSpecialEntry({
    required String sourceLabel,
    required String kind,
    required List<InterlinearToken> tokens,
    this.surfaceText,
    Map<String, String> provenance = const {},
  })  : sourceLabel = _required(sourceLabel, 'sourceLabel'),
        kind = _required(kind, 'kind'),
        tokens = _tokens(tokens),
        provenance = _stringMap(provenance, 'provenance');

  final String sourceLabel;
  final String kind;
  final List<InterlinearToken> tokens;
  final String? surfaceText;
  final Map<String, String> provenance;

  String get reconstructedText => _reconstruct(tokens);
}

/// One displayed token occurrence in logical source reading order.
///
/// Hebrew tokens are never reversed for visual RTL layout. [separatorAfter]
/// records spacing or punctuation after this occurrence when supplied; source
/// importers must disclose when it is reconstructed. [sourceText] may retain
/// source formatting distinct from the displayed [surface].
final class InterlinearToken {
  InterlinearToken({
    required String occurrenceId,
    required this.surface,
    required String language,
    this.sourceRecordId,
    this.transliteration,
    this.sourceText,
    Map<String, String> glosses = const {},
    List<InterlinearSegment> segments = const [],
    this.separatorAfter = ' ',
  })  : occurrenceId = _required(occurrenceId, 'occurrenceId'),
        language = _required(language, 'language'),
        glosses = _stringMap(glosses, 'glosses'),
        segments = List.unmodifiable(segments) {
    if (surface.isEmpty) {
      throw ArgumentError.value(surface, 'surface', 'must not be empty');
    }
    if (sourceRecordId != null) _required(sourceRecordId!, 'sourceRecordId');
  }

  final String occurrenceId;
  final String? sourceRecordId;
  final String surface;
  final String language;
  final String? transliteration;
  final String? sourceText;
  final Map<String, String> glosses;
  final List<InterlinearSegment> segments;
  final String separatorAfter;

  InterlinearTokenKey keyFor(InterlinearMetadata metadata) =>
      InterlinearTokenKey(
        datasetId: metadata.datasetId,
        datasetRevision: metadata.datasetRevision,
        occurrenceId: occurrenceId,
      );
}

/// A whole word or source-supported constituent, without inferred analysis.
final class InterlinearSegment {
  InterlinearSegment({
    this.text,
    this.kind,
    this.lemma,
    List<LexicalReference> lexicalReferences = const [],
    List<MorphologyTag> morphology = const [],
    Map<String, String> glosses = const {},
  })  : lexicalReferences = List.unmodifiable(lexicalReferences),
        morphology = List.unmodifiable(morphology),
        glosses = _stringMap(glosses, 'glosses');

  final String? text;
  final String? kind;
  final String? lemma;
  final List<LexicalReference> lexicalReferences;
  final List<MorphologyTag> morphology;
  final Map<String, String> glosses;
}

/// A lexicon identifier retaining its complete original namespace and value.
final class LexicalReference {
  LexicalReference(
      {required String system, required String value, this.traditionalStrongs})
      : system = _required(system, 'system'),
        value = _required(value, 'value') {
    if (traditionalStrongs != null) {
      _required(traditionalStrongs!, 'traditionalStrongs');
    }
  }

  final String system;
  final String value;

  /// A traditional Strong's equivalent, only when independently established.
  final String? traditionalStrongs;

  @override
  bool operator ==(Object other) =>
      other is LexicalReference &&
      other.system == system &&
      other.value == value &&
      other.traditionalStrongs == traditionalStrongs;
  @override
  int get hashCode => Object.hash(system, value, traditionalStrongs);
}

/// Original morphology code in a declared scheme, without universal conversion.
final class MorphologyTag {
  MorphologyTag({required String scheme, required String code})
      : scheme = _required(scheme, 'scheme'),
        code = _required(code, 'code');

  final String scheme;
  final String code;

  @override
  bool operator ==(Object other) =>
      other is MorphologyTag && other.scheme == scheme && other.code == code;
  @override
  int get hashCode => Object.hash(scheme, code);
}

/// Persistent occurrence identity scoped to a dataset revision.
///
/// Lexical IDs identify dictionary entries, not occurrences. Positional IDs
/// must not be assumed stable when [datasetRevision] changes.
final class InterlinearTokenKey {
  InterlinearTokenKey(
      {required String datasetId,
      required String datasetRevision,
      required String occurrenceId})
      : datasetId = _required(datasetId, 'datasetId'),
        datasetRevision = _required(datasetRevision, 'datasetRevision'),
        occurrenceId = _required(occurrenceId, 'occurrenceId');

  final String datasetId;
  final String datasetRevision;
  final String occurrenceId;

  @override
  bool operator ==(Object other) =>
      other is InterlinearTokenKey &&
      other.datasetId == datasetId &&
      other.datasetRevision == datasetRevision &&
      other.occurrenceId == occurrenceId;
  @override
  int get hashCode => Object.hash(datasetId, datasetRevision, occurrenceId);
}

String _required(String value, String field) {
  if (value.trim().isEmpty || value.trim() != value) {
    throw ArgumentError.value(
        value, field, 'must be non-blank with no surrounding whitespace');
  }
  return value;
}

Map<String, String> _stringMap(Map<String, String> input, String field) {
  for (final key in input.keys) {
    _required(key, '$field key');
  }
  return Map.unmodifiable(input);
}

List<String> _strings(List<String> input, String field) {
  for (final value in input) {
    _required(value, field);
  }
  if (input.toSet().length != input.length) {
    throw ArgumentError.value(input, field, 'must not contain duplicates');
  }
  return List.unmodifiable(input);
}

Map<BibleBookEnum, List<int>> _coverage(Map<BibleBookEnum, List<int>> input) {
  if (input.isEmpty) {
    throw ArgumentError.value(input, 'coverage', 'must not be empty');
  }
  final result = <BibleBookEnum, List<int>>{};
  for (final entry in input.entries) {
    if (entry.value.isEmpty ||
        entry.value.any((n) => n < 1) ||
        entry.value.toSet().length != entry.value.length) {
      throw ArgumentError.value(entry.value, 'coverage',
          'chapters must be nonempty, positive and unique');
    }
    result[entry.key] = List.unmodifiable(List<int>.of(entry.value)..sort());
  }
  return Map.unmodifiable(result);
}

BibleLocation _location(BibleLocation value) {
  if (!value.hasVerse) {
    throw ArgumentError.value(value, 'location', 'must identify a verse');
  }
  return BibleLocation.checked(
      book: value.book,
      chapter: value.chapter,
      verse: value.verse,
      verseLabel: value.verseLabel);
}

List<InterlinearToken> _tokens(List<InterlinearToken> tokens) {
  final ids = <String>{};
  for (final token in tokens) {
    if (!ids.add(token.occurrenceId)) {
      throw ArgumentError.value(
          token.occurrenceId, 'tokens', 'duplicate occurrence ID');
    }
  }
  return List.unmodifiable(tokens);
}

String _reconstruct(List<InterlinearToken> tokens) => tokens
    .map((token) => '${token.surface}${token.separatorAfter}')
    .join()
    .trimRight();

int _position(int verse, String? subdivision, {required bool end}) =>
    verse * 28 +
    (subdivision == null ? (end ? 27 : 0) : subdivision.codeUnitAt(0) - 96);
int _start(VerseLabel label) =>
    _position(label.startVerse, label.startSubdivision, end: false);
int _end(VerseLabel label) => _position(label.endVerse ?? label.startVerse,
    label.isCombined ? label.endSubdivision : label.startSubdivision,
    end: true);

List<InterlinearVerse> _prepareVerses(
    BibleBookEnum book, int chapter, List<InterlinearVerse> verses) {
  if (chapter < 1) {
    throw ArgumentError.value(chapter, 'chapter', 'must be positive');
  }
  for (final verse in verses) {
    if (verse.location.book != book || verse.location.chapter != chapter) {
      throw ArgumentError.value(
          verse.location, 'verses', 'must belong to the containing chapter');
    }
  }
  final sorted = List<InterlinearVerse>.of(verses)
    ..sort((a, b) => _start(a.label).compareTo(_start(b.label)));
  for (var i = 1; i < sorted.length; i++) {
    if (_start(sorted[i].label) <= _end(sorted[i - 1].label)) {
      throw ArgumentError.value(sorted[i].label.source, 'verses',
          'duplicate or overlapping verse labels');
    }
  }
  return List.unmodifiable(sorted);
}
