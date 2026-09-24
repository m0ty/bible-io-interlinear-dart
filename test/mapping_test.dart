import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

BibleLocation location(int verse, {String? label}) => BibleLocation.checked(
      book: BibleBookEnum.psalms,
      chapter: 3,
      verse: verse,
      verseLabel: label,
    );

VerseMappingRequest request(
        {String source = 'translation',
        String target = 'hebrew',
        String? label}) =>
    VerseMappingRequest(
        sourceEdition: source,
        sourceReferenceSystem: 'translation-numbering',
        sourceLocation: location(1, label: label),
        targetDatasetId: target,
        targetReferenceSystem: 'hebrew-numbering');

void main() {
  test('explicit table preserves one-to-many and caller provenance', () {
    final targets = [location(2), location(3)];
    final provenance = {'authority': 'caller-supplied', 'table': 'local-v1'};
    final result = VerseMappingResult(
        status: VerseMappingStatus.matched,
        targets: targets,
        provenance: provenance);
    final entries = [VerseMappingEntry(request: request(), result: result)];
    final mapper = TableVerseMapper(entries: entries);
    targets.clear();
    provenance.clear();
    entries.clear();
    final mapped = mapper.map(request());
    expect(mapped.status, VerseMappingStatus.matched);
    expect(mapped.targets, [location(2), location(3)]);
    expect(mapped.provenance['authority'], 'caller-supplied');
    expect(() => mapped.targets.clear(), throwsUnsupportedError);
    expect(() => mapped.provenance.clear(), throwsUnsupportedError);
  });

  test('unknown pairs and even matching reference strings remain unmapped', () {
    final mapper = TableVerseMapper();
    final equalSchemes = VerseMappingRequest(
        sourceEdition: 'a',
        sourceReferenceSystem: 'same',
        sourceLocation: location(1),
        targetDatasetId: 'b',
        targetReferenceSystem: 'same');
    expect(mapper.map(equalSchemes).status, VerseMappingStatus.unmapped);
    expect(mapper.map(request()).targets, isEmpty);
  });

  test('identity requires the whole configured pair and retains exact labels',
      () {
    final pairs = [
      CompatibleReferencePair(
          sourceEdition: 'translation',
          sourceReferenceSystem: 'translation-numbering',
          targetDatasetId: 'hebrew',
          targetReferenceSystem: 'hebrew-numbering')
    ];
    final mapper = TableVerseMapper(identityPairs: pairs);
    pairs.clear();
    final mapped = mapper.map(request(label: '1A–2b'));
    expect(mapped.targets.single.verseLabel, '1A–2b');
    expect(mapped.provenance['authority'], 'caller-supplied');
    expect(mapper.map(request(source: 'unknown')).status,
        VerseMappingStatus.unmapped);
    expect(mapper.map(request(target: 'unknown')).status,
        VerseMappingStatus.unmapped);
  });

  test('explicit partial/ambiguous/unmapped entries override identity', () {
    for (final status in [
      VerseMappingStatus.partial,
      VerseMappingStatus.ambiguous,
      VerseMappingStatus.unmapped
    ]) {
      final expected = VerseMappingResult(
          status: status,
          targets: status == VerseMappingStatus.unmapped
              ? []
              : [location(2), location(3)],
          note: 'Caller table status');
      final mapper = TableVerseMapper(entries: [
        VerseMappingEntry(request: request(), result: expected)
      ], identityPairs: [
        CompatibleReferencePair(
            sourceEdition: 'translation',
            sourceReferenceSystem: 'translation-numbering',
            targetDatasetId: 'hebrew',
            targetReferenceSystem: 'hebrew-numbering')
      ]);
      expect(mapper.map(request()), same(expected));
    }
  });

  test('validates mappings and rejects duplicate requests', () {
    expect(() => VerseMappingResult(status: VerseMappingStatus.matched),
        throwsArgumentError);
    expect(
        () => VerseMappingResult(
            status: VerseMappingStatus.unmapped, targets: [location(1)]),
        throwsArgumentError);
    expect(
        () => VerseMappingResult(
            status: VerseMappingStatus.matched,
            targets: [location(1), location(1)]),
        throwsArgumentError);
    final entry = VerseMappingEntry(
        request: request(),
        result: VerseMappingResult(status: VerseMappingStatus.unmapped));
    expect(
        () => TableVerseMapper(entries: [entry, entry]), throwsArgumentError);
    expect(
        () => VerseMappingRequest(
            sourceEdition: '',
            sourceReferenceSystem: 'a',
            sourceLocation: location(1),
            targetDatasetId: 'b',
            targetReferenceSystem: 'b'),
        throwsArgumentError);
    expect(
        () => VerseMappingRequest(
            sourceEdition: 'a',
            sourceReferenceSystem: 'a',
            sourceLocation:
                const BibleLocation(book: BibleBookEnum.psalms, chapter: 3),
            targetDatasetId: 'b',
            targetReferenceSystem: 'b'),
        throwsArgumentError);
  });
}
