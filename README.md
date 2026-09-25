# bible_io_interlinear

An optional, pure Dart companion to `bible_io` for original-language Bible
interlinear data. Version **0.2.0** keeps each original-language dataset
separate from translations. It reuses public Bible-IO books, locations and verse
labels without subclassing Bible/Verse or re-exporting the whole Bible-IO API.

Applications load a small manifest and requested chapter JSON. Data preparation
is a separate operation: pinned STEPBible text → source parser → explicit
reading selection → validated models → deterministic JSON. Library imports and
runtime readers never acquire source files, access the filesystem, or require
network requests. Resource loading is injected by the application.

## Supported data

| Import | Supported profile | Selection |
| --- | --- | --- |
| TAGNT Greek NT | `N` | Main Ancient `N`/`n` source rows in logical source order |
| TAHOT Hebrew/Aramaic OT | `L+Q+R`, `qere` | Main Leningrad/Qere rows and restorations; excludes `X` additions |

These are STEPBible source reading profiles. The Greek output is not claimed
to reproduce a named published edition exactly: upstream combines spelling,
punctuation, and edition information. Exact edition displacement reconstruction
and alternate ketiv selection are unsupported. Inputs and available chapter
resources determine coverage; fixture imports contain only selected passages.
See [import details](doc/stepbible_import.md) for actual source rules and limits.

Tokens retain Greek/Hebrew Unicode, source IDs, supplied transliteration,
language-keyed glosses, extended lexical IDs, and original morphology codes.
Source-supported segments distinguish word constituents and punctuation.
Hebrew tokens remain in logical reading order. Reconstructed display text is
explicitly marked and is not a verified reproduction of published typography.

Translation language, original language, and gloss language are independent.
For example, a Spanish translation can display Greek tokens with English glosses.

## Run locally

Requires Dart SDK 3.4 or later; development checks use Dart 3.11.4. Resolved
Bible-IO dependencies are `bible_io 1.2.0` and `bible_io_references 1.2.0`.

```sh
dart pub get
dart run example/import_stepbible.dart
dart run example/read_interlinear.dart
dart run tool/verify_dataset.dart .work/example-dataset
dart run bin/convert_stepbible.dart --help
```

The import example writes `.work/example-dataset` and refuses existing output.
Pass an input file and a new output directory to repeat it. The reading example
accepts `DATASET_DIRECTORY USFM_BOOK CHAPTER VERSE_LABEL` as optional arguments.

Convert the committed fixture without network access:

```sh
dart run bin/convert_stepbible.dart --source-type tagnt --profile N --input test/fixtures/stepbible/tagnt.txt --dataset-id step-tagnt-n-fixture --dataset-revision 1 --output .work/converted-fixture --report .work/fixture-report.json
```

For the pinned full inputs, explicitly run `dart run tool/acquire_sources.dart`;
then use the complete commands in [STEPBible import](doc/stepbible_import.md).
`--diagnostic` collects a report without publishing a dataset. Strict conversion
exits nonzero on malformed records and validates staged output before finalizing.
`--overwrite` replaces an existing valid dataset while retaining a sibling
backup. Full source files, generated datasets, and caches are excluded from Git
and the package archive.

## Runtime API

```dart
import 'dart:io'; // Only this command-line application's reader uses I/O.
import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';

final bible = await InterlinearBible.open(
  JsonInterlinearDataSource(
    reader: (path) => File('dataset/$path').readAsBytes(),
  ),
  cacheCapacity: 8,
);
final chapter = await bible.loadChapter(bibleBookFromUsfmIdentifier('JHN'), 1);
final verse = chapter.getVerseByLabel('1'); // Synchronous after chapter load.
for (final token in verse.tokens) {
  print('${token.surface}: ${token.glosses['en']}');
  for (final segment in token.segments) {
    print(segment.lemma);
    for (final lexical in segment.lexicalReferences) {
      print('${lexical.system}: ${lexical.value}');
    }
    for (final tag in segment.morphology) {
      print('${tag.scheme}: ${tag.code}');
    }
  }
  final persistentKey = token.keyFor(bible.metadata);
  print(persistentKey.occurrenceId);
}
```

The bounded chapter cache deduplicates concurrent loads, supports capacity zero,
and permits retry after errors. Data, unavailable-resource, unsupported-coverage,
and missing-verse failures are distinct. `MemoryInterlinearDataSource` supports
already constructed immutable models. Exact combined/subdivided labels such as
`29-30` and `5a` survive serialization. Numeric lookup of an ambiguous subdivision
throws rather than choosing silently. Superscriptions have explicit special
entries with their source label, without an invented positive verse number.

Flutter applications inject an asset reader; Flutter is not a package dependency:

```dart
import 'package:flutter/services.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';

final interlinear = await InterlinearBible.open(
  JsonInterlinearDataSource(reader: (path) async {
    final data = await rootBundle.load('assets/interlinear/$path');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }),
);
```

Declare the generated manifest, attribution, and chapter assets in the Flutter
application's own pubspec. A filesystem reader must control its dataset directory
and avoid external symlinks; the loader validates relative resource paths.

## Reference correspondence

Parsing a reference does not establish correspondence between editions.
`VerseMapper` takes a `VerseMappingRequest` identifying the source edition and
reference system, source `BibleLocation`, target dataset, and target reference
system. `TableVerseMapper` uses explicit `VerseMappingEntry` records whose
results can be `matched`, `partial`, `unmapped`, or `ambiguous` and may contain
multiple target locations. Caller-supplied evidence stays caller-supplied.

For prepared edition mappings, `CorrespondenceJsonCodec` strictly validates the
schema-1 index, including dataset release bindings and exact source selectors.
Validate the loaded translation's SHA-256 with
`CorrespondenceIndex.validateSourceEdition`, then use `CorrespondenceResolver`
with an injected dataset opener. It verifies manifest identity and resolves
ordered word selections, combined verses, and special entries without replacing
the original source locations with a translation's address. See
[the integration contract](doc/flutter_integration.md) for the API and ownership
boundaries.

`InterlinearWordAnalyzer(metadata: bible.metadata).analyze(token)` provides typed
contextual glosses, dictionary entries, grammatical functions, and source
annotations. It interprets only the audited STEPBible source revision/profile;
unknown providers retain their raw fields. Applications choose localized labels
and presentation. Original token data and schema-1 chapter bytes remain intact.

Unknown pairs remain unmapped. Identity correspondence requires an explicit
`CompatibleReferencePair` assertion; equal verse numbers or equal system strings
alone do not enable it. A full TVTMS importer and universal verse conversion are
future work. Arbitrary translation-to-original word alignment is outside scope:
verse correspondence and lexical similarity do not establish word alignment.

## Provenance, licenses, and validation

Code uses **AGPL-3.0**, matching Bible-IO; the existing [LICENSE](LICENSE) is
preserved. STEPBible data is separately attributed under **CC BY 4.0**, with
source-specific component notices retained in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
The pin is `b99716b0cddb648ddb95cc786a197180f2f97d48`; paths and SHA-256 hashes are
in [sources.lock.json](tool/sources.lock.json). Fixtures are small attributed
extracts. Generated metadata records the selected profile, input provenance and
conversion modifications. This is not a legal review of upstream components.

```sh
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart pub publish --dry-run
```

Unit tests run offline. See [architecture](doc/architecture.md),
[content schema](doc/content_schema.md), and [validation results](doc/validation.md).
The package does not implement lexicon services, morphology expansion,
corpus search, additional source importers, AI glossing, or Flutter widgets.
