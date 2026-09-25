# Using the package in an independent application

The package owns original-language models, integrity checks, chapter caching,
explicit reference correspondence, and source-aware word analysis. The consumer
owns storage/transport, UI, localized labels, supported editions, and scheduling.
Runtime imports use only Dart libraries and published Bible-IO APIs.

`example/independent_client.dart` is a runnable consumer that imports only the
public package entry points. It prepares synthetic Latin records at a Tobit
reference, supplies Spanish and French glosses, builds an explicit correspondence
for an unrelated translation address, round-trips that table through JSON, loads
resources from memory, and supplies its own word-analysis adapter. Its data is
demonstration material, not an imported or verified Bible edition.

```sh
dart run example/independent_client.dart
dart compile js -O2 -o .dart_tool/independent_client.js example/independent_client.dart
```

## Storage and coverage

`InterlinearBible.open` accepts an `InterlinearDataSource`.
`MemoryInterlinearDataSource` accepts already prepared models.
`JsonInterlinearDataSource` accepts a reader callback returning resource bytes.
The callback can map the validated relative paths to files, HTTP responses, a
database, Flutter assets or memory. No storage backend is selected implicitly.
Transport compression is the consumer's choice; integrity hashes describe the
uncompressed prepared JSON bytes.

Core models accept arbitrary source IDs, revision IDs, profiles, language-keyed
glosses, lexicon systems and morphology schemes. Books and verse-label syntax
use Bible-IO's public reference types, including its additional book identifiers.
The package does not impose the companion app's 66-book coverage. Consumers
declare actual prepared coverage and choose their own bounded chapter-cache
capacity. Missing data does not trigger a source download or another edition.

The built-in text importers support the documented STEPBible profiles. Supporting
another source's raw files requires a converter that supplies validated models;
accepting generic models is not a claim to understand every source file format.

## Constructing correspondence

Create a `CorrespondenceDatasetBinding` for each dataset using its ID, dataset
revision, source revision, reading profile, reference system and exact manifest
SHA-256. Each dataset has its own release and numbering identity; independent
providers do not need a shared revision string.

Create `CorrespondenceEntry` values with a dataset ID, mapping status and ordered
`InterlinearSourceSelection` values. Each selection specifies an exact native
verse label or special-entry label and may select ordered occurrence IDs. A
passage belongs to one declared dataset; comparison/collation of alternative
datasets remains a consumer concern. Ambiguous alternatives are never silently
concatenated.

Construct `CorrespondenceIndex` from the edition ID, SHA-256 of its actual
content, source reference system, dataset bindings, entries keyed with
`correspondenceKey(location)`, and optional provenance string fields. Coverage
counts and the list of unmapped entries are derived. There is no requirement for
TVTMS evidence, Greek-specific counters, STEPBible IDs, a KJV edition or English
glosses. A programmatic table is still the caller's assertion of correspondence;
the library validates its structure and identities, not its textual scholarship.

`CorrespondenceJsonCodec.encode(index)` emits deterministic generic schema 2.
`decode` and `decodeAsync` read schema 2 and the original schema-1 app format.
Both reject unknown structured fields and malformed selectors. Provenance is
explicitly an extensible string map in schema 2. The strict legacy schema-1
decoder preserves the old app format's fixed provenance and coverage fields.
Chapter and manifest resources remain schema 1.

After constructing/loading an index, call `validateSourceEdition` with the actual
edition ID, reference system and content hash. Then create a
`CorrespondenceResolver` whose opener calls:

```dart
CorrespondenceDataset.open(
  manifestBytes: exactManifestBytes,
  reader: readUncompressedResource,
  cacheCapacity: 4,
);
```

The package owns the manifest/source pair and verifies resource hashes. The
resolver also enforces each binding's profile, revisions, reference system and
manifest hash. Its result separates the translation address from original source
selectors and token identities. Hashes bind bytes; callers establish trust in
the publisher and mapping assertions.

## Provider-specific word analysis

`InterlinearWordAnalyzer` supplies audited built-in STEPBible analysis. It selects
those rules from exact source metadata, not from the language alone. Unknown
sources and unsupported revisions retain raw glosses without inferred dictionary
meanings or grammar. The built-in TAGNT dictionary interpretation is audited for
the supplied English fields; additional language fields remain available raw.

For another provider, implement `InterlinearWordAnalysisAdapter` and pass it as
`InterlinearWordAnalyzer(metadata: metadata, adapter: adapter)`. The analyzer
checks `supports(metadata, token)` before delegating. Unsupported tokens fall
back to the built-in rules/raw representation. An adapter may compose other
adapters internally. Custom results use `InterlinearAnalysisSource.custom` and
must retain the exact raw token and references to its original segments.

The adapter decides which provider fields are contextual glosses, dictionary
entries, source codes or annotations. Dictionary/context gloss maps retain
language keys. Consumers choose the display language, render grammatical
functions through `InterlinearGloss.render`, and decide which details to show.
The package does not choose English UI labels or a widget layout.

Readers, decoders and custom analyzers are trusted executable application code.
The integrity API validates data; it is not a sandbox for consumer callbacks.

## Scheduling and compatibility

Cooperative hash, chapter and mapping methods accept `yieldControl` callbacks.
The consumer can schedule an event-loop yield, while native applications can
use an isolate. Verified chapter-decoding helpers preserve integrity checks when
moving work to another execution context. There is no unconditional Flutter
`compute`, browser timer or isolate dependency in the package.

In 0.3.0, correspondence-wide `sourceRevision` and `targetReferenceSystem` are
nullable convenience getters: they return a shared value only when every binding
agrees. Use each dataset binding when working with different providers/systems.
Exhaustive switches on `InterlinearAnalysisSource` must include `custom`.
Existing schema-1 mappings and chapter assets require no regeneration to load.

See [the Flutter-specific integration](flutter_integration.md) for the companion
app's choices: compressed assets, KJV-only correspondence, UI labels and focus.
