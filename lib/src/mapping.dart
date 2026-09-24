import 'package:bible_io/bible_io.dart';

/// The outcome of an explicitly configured edition correspondence.
enum VerseMappingStatus { matched, partial, unmapped, ambiguous }

/// An edition-aware request; matching numbers alone never establish a mapping.
final class VerseMappingRequest {
  VerseMappingRequest({
    required String sourceEdition,
    required String sourceReferenceSystem,
    required BibleLocation sourceLocation,
    required String targetDatasetId,
    required String targetReferenceSystem,
  })  : sourceEdition = _identifier(sourceEdition, 'sourceEdition'),
        sourceReferenceSystem =
            _identifier(sourceReferenceSystem, 'sourceReferenceSystem'),
        sourceLocation = _verseLocation(sourceLocation),
        targetDatasetId = _identifier(targetDatasetId, 'targetDatasetId'),
        targetReferenceSystem =
            _identifier(targetReferenceSystem, 'targetReferenceSystem');

  final String sourceEdition;
  final String sourceReferenceSystem;
  final BibleLocation sourceLocation;
  final String targetDatasetId;
  final String targetReferenceSystem;

  @override
  bool operator ==(Object other) =>
      other is VerseMappingRequest &&
      other.sourceEdition == sourceEdition &&
      other.sourceReferenceSystem == sourceReferenceSystem &&
      other.sourceLocation == sourceLocation &&
      other.targetDatasetId == targetDatasetId &&
      other.targetReferenceSystem == targetReferenceSystem;
  @override
  int get hashCode => Object.hash(sourceEdition, sourceReferenceSystem,
      sourceLocation, targetDatasetId, targetReferenceSystem);
}

/// A correspondence may contain several targets without splitting their text.
///
/// [provenance] records caller-supplied evidence. This package does not certify
/// the contents of mapping tables or assertions of compatible reference systems.
final class VerseMappingResult {
  VerseMappingResult({
    required this.status,
    List<BibleLocation> targets = const [],
    this.note,
    Map<String, String> provenance = const {},
  })  : targets = List.unmodifiable(targets.map(_verseLocation)),
        provenance = Map.unmodifiable(provenance) {
    if (status == VerseMappingStatus.unmapped && this.targets.isNotEmpty) {
      throw ArgumentError('Unmapped results cannot contain targets.');
    }
    if (status != VerseMappingStatus.unmapped && this.targets.isEmpty) {
      throw ArgumentError(
          'Mapped, partial and ambiguous results require targets.');
    }
    if (this.targets.toSet().length != this.targets.length) {
      throw ArgumentError('Mapping targets must be unique.');
    }
  }

  final VerseMappingStatus status;
  final List<BibleLocation> targets;
  final String? note;
  final Map<String, String> provenance;
}

/// Boundary for edition/reference-system mapping, independent of parsing.
abstract interface class VerseMapper {
  VerseMappingResult map(VerseMappingRequest request);
}

/// One caller-supplied table entry, with its outcome and provenance.
final class VerseMappingEntry {
  const VerseMappingEntry({required this.request, required this.result});
  final VerseMappingRequest request;
  final VerseMappingResult result;
}

/// An explicit caller assertion allowing identity mapping for one edition pair.
///
/// Every identifier must match exactly. Equal reference-system strings alone
/// do not enable identity mapping. This assertion neither checks target chapter
/// coverage nor independently verifies the editions' correspondence.
final class CompatibleReferencePair {
  CompatibleReferencePair({
    required String sourceEdition,
    required String sourceReferenceSystem,
    required String targetDatasetId,
    required String targetReferenceSystem,
  })  : sourceEdition = _identifier(sourceEdition, 'sourceEdition'),
        sourceReferenceSystem =
            _identifier(sourceReferenceSystem, 'sourceReferenceSystem'),
        targetDatasetId = _identifier(targetDatasetId, 'targetDatasetId'),
        targetReferenceSystem =
            _identifier(targetReferenceSystem, 'targetReferenceSystem');

  final String sourceEdition;
  final String sourceReferenceSystem;
  final String targetDatasetId;
  final String targetReferenceSystem;

  bool _matches(VerseMappingRequest request) =>
      sourceEdition == request.sourceEdition &&
      sourceReferenceSystem == request.sourceReferenceSystem &&
      targetDatasetId == request.targetDatasetId &&
      targetReferenceSystem == request.targetReferenceSystem;
}

/// A deterministic explicit table with optional caller-asserted identity pairs.
///
/// Explicit entries, including unmapped or ambiguous entries, take precedence
/// over identity assertions. An unknown source or target remains unmapped.
final class TableVerseMapper implements VerseMapper {
  TableVerseMapper({
    List<VerseMappingEntry> entries = const [],
    List<CompatibleReferencePair> identityPairs = const [],
  })  : _entries = _table(entries),
        _identityPairs = List.unmodifiable(identityPairs);

  final Map<VerseMappingRequest, VerseMappingResult> _entries;
  final List<CompatibleReferencePair> _identityPairs;

  @override
  VerseMappingResult map(VerseMappingRequest request) {
    final explicit = _entries[request];
    if (explicit != null) return explicit;
    if (_identityPairs.any((pair) => pair._matches(request))) {
      return VerseMappingResult(
        status: VerseMappingStatus.matched,
        targets: [request.sourceLocation],
        note:
            'Identity correspondence asserted by the caller for this edition pair.',
        provenance: const {
          'authority': 'caller-supplied',
          'method': 'explicit-identity-pair'
        },
      );
    }
    return VerseMappingResult(
      status: VerseMappingStatus.unmapped,
      note: 'No explicit mapping or compatible edition pair is configured.',
    );
  }
}

Map<VerseMappingRequest, VerseMappingResult> _table(
    List<VerseMappingEntry> entries) {
  final table = <VerseMappingRequest, VerseMappingResult>{};
  for (final entry in entries) {
    if (table.containsKey(entry.request)) {
      throw ArgumentError(
          'Duplicate mapping request; represent alternatives in one ambiguous result.');
    }
    table[entry.request] = entry.result;
  }
  return Map.unmodifiable(table);
}

String _identifier(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(
        value, field, 'must be non-blank with no surrounding whitespace');
  }
  return value;
}

BibleLocation _verseLocation(BibleLocation location) {
  if (!location.hasVerse) {
    throw ArgumentError.value(location, 'location', 'must identify a verse');
  }
  return BibleLocation.checked(
      book: location.book,
      chapter: location.chapter,
      verse: location.verse,
      verseLabel: location.verseLabel);
}
