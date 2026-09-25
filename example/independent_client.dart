import 'dart:convert';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';

/// A complete consumer with no Flutter, filesystem, network, KJV or STEP data.
/// These synthetic records demonstrate the API; they are not a Bible edition.
Future<void> main() async {
  final result = await runIndependentExample();
  print('${result.$1} → ${result.$2}');
}

Future<(String, String)> runIndependentExample() async {
  const book = BibleBookEnum.tobit;
  final nativeLocation =
      BibleLocation.checked(book: book, chapter: 1, verse: 1);
  final translationLocation =
      BibleLocation.checked(book: book, chapter: 1, verse: 7);
  final token = InterlinearToken(
    occurrenceId: 'word-1',
    surface: 'verbum',
    language: 'lat',
    glosses: {'es': 'una palabra', 'fr': 'une parole'},
    segments: [
      InterlinearSegment(
        text: 'verbum',
        lemma: 'verbum',
        glosses: {'es': 'palabra', 'fr': 'parole'},
        lexicalReferences: [
          LexicalReference(system: 'example-lexicon', value: 'entry-1'),
        ],
      ),
    ],
  );
  final prepared = PreparedInterlinearDataset.build(
    metadata: InterlinearMetadata(
      datasetId: 'independent-latin',
      datasetRevision: '1',
      source: 'Independent example provider',
      sourceRevision: 'text-release-a',
      profile: 'example-reading',
      referenceSystem: 'example-native-numbering',
      originalLanguages: ['lat'],
      glossLanguages: ['es', 'fr'],
      coverage: {
        book: [1]
      },
      attribution: {'notice': 'Synthetic example data; not a Bible edition.'},
    ),
    chapters: [
      InterlinearChapter(book: book, chapter: 1, verses: [
        InterlinearVerse(location: nativeLocation, tokens: [token]),
      ]),
    ],
  );
  final editionHash = resourceSha256(utf8.encode('Una palabra de ejemplo.'));
  final binding = CorrespondenceDatasetBinding(
    datasetId: 'independent-latin',
    datasetRevision: '1',
    sourceRevision: 'text-release-a',
    profile: 'example-reading',
    referenceSystem: 'example-native-numbering',
    manifestSha256: resourceSha256(prepared.resources['manifest.json']!),
  );
  final index = CorrespondenceIndex(
    sourceEdition: 'independent-spanish-edition',
    sourceAssetSha256: editionHash,
    sourceReferenceSystem: 'example-translation-numbering',
    datasets: {binding.datasetId: binding},
    entries: {
      correspondenceKey(translationLocation): CorrespondenceEntry(
        datasetId: binding.datasetId,
        status: VerseMappingStatus.matched,
        sources: [
          InterlinearSourceSelection(
            datasetId: binding.datasetId,
            book: book,
            chapter: 1,
            verseLabel: '1',
            occurrenceIds: ['word-1'],
          ),
        ],
      ),
    },
    provenance: {
      'editor': 'Example author',
      'method': 'Explicit example table'
    },
  );

  // Persist/load the generic correspondence format, then bind the actual text.
  const codec = CorrespondenceJsonCodec();
  final loadedIndex = codec.decode(codec.encode(index));
  loadedIndex.validateSourceEdition(
    editionId: 'independent-spanish-edition',
    referenceSystem: 'example-translation-numbering',
    assetSha256: editionHash,
  );
  final resolver = CorrespondenceResolver(
    index: loadedIndex,
    openDataset: (_) => CorrespondenceDataset.open(
      manifestBytes: prepared.resources['manifest.json']!,
      reader: (path) async => prepared.resources[path]!,
      cacheCapacity: 1,
    ),
  );
  final passage = await resolver.resolve(translationLocation);
  final analysis = InterlinearWordAnalyzer(
    metadata: passage.metadata,
    adapter: const ExampleProviderAnalysis(),
  ).analyze(passage.tokens.single);
  final dictionaryMeaning = analysis.parts.single.dictionaryEntries.single;
  return (passage.reconstructedText, dictionaryMeaning.glosses['es']!);
}

/// Only this example provider promises that segment glosses are dictionary
/// meanings. Other providers must declare their own field contract.
class ExampleProviderAnalysis implements InterlinearWordAnalysisAdapter {
  const ExampleProviderAnalysis();

  @override
  bool supports(InterlinearMetadata? metadata, InterlinearToken token) =>
      metadata?.source == 'Independent example provider' &&
      metadata?.sourceRevision == 'text-release-a' &&
      token.language == 'lat';

  @override
  InterlinearWordAnalysis analyze(
          InterlinearMetadata? metadata, InterlinearToken token) =>
      InterlinearWordAnalysis(
        raw: token,
        source: InterlinearAnalysisSource.custom,
        contextualGlosses: token.glosses.map(
          (language, text) => MapEntry(language, InterlinearGloss.raw(text)),
        ),
        segments: [
          for (final segment in token.segments)
            InterlinearSegmentAnalysis(
              raw: segment,
              isWordPart: true,
              dictionaryEntries: [
                if (segment.lemma case final form?)
                  InterlinearDictionaryEntry(
                    rawForm: form,
                    form: form,
                    rawGlosses: segment.glosses,
                    glosses: segment.glosses,
                    lexicalReferences: segment.lexicalReferences,
                  ),
              ],
            ),
        ],
      );
}
