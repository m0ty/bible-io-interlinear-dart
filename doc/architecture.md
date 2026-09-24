# Architecture

`bible_io_interlinear` is an optional companion to `bible_io`. Translation text
continues to belong to the existing Bible-IO models. Original-language tokens
belong to separately prepared datasets, so several translations can refer to the
same original-language resource without copying it into each translation.

```text
Application
  ├─ bible_io: translations, books, references and verse labels
  └─ bible_io_interlinear
       └─ bible_io public reference types
```

The library is pure Dart. Runtime code neither reads files nor initiates network
requests. A caller supplies a resource reader for prepared JSON; command-line
tools and examples may use `dart:io`. A Flutter application can supply an asset
reader without making Flutter a dependency of this package.

## Preparation and reading

Preparation is an explicit operation: acquire pinned source bytes, parse each
source's tab-separated records, apply its supported reading profile, validate
and normalize the records, then emit a manifest, attribution, and chapter
resources. The source acquisition tool is separate from the importer. Importing
the public Dart library never downloads data.

The normal application path opens the prepared manifest and loads only requested
chapters. `InterlinearBible` owns the bounded chapter cache and deduplicates
concurrent loads for a chapter. A loaded `InterlinearChapter` provides synchronous
verse lookup. Failed loads do not become permanent cache entries.

The stable runtime entry point is `package:bible_io_interlinear/bible_io_interlinear.dart`.
The separate `package:bible_io_interlinear/stepbible.dart` entry point exposes
supported import configuration and diagnostics. Import-specific records are
implementation details. Neither entry point re-exports the entire Bible-IO API.

## Identity and references

The package depends on published `bible_io` 1.2.0-compatible APIs and imports
`package:bible_io/bible_io.dart`, whose public exports include `BibleBookEnum`,
`BibleChapterLocation`, `BibleLocation`, and `VerseLabel`. It does not import
private `lib/src` files or parse human reference strings. Exact
subdivided and combined labels remain labels rather than being reduced to an
integer. Headings and source verse-zero entries are explicit special entries,
not fabricated positive verse numbers.

An original-text edition/profile describes reading selection. A dataset revision
identifies one normalization result. A reference-system identifier describes
numbering. These are distinct metadata fields. A token key consists of dataset
ID, dataset revision, and occurrence ID; lexical identifiers describe words, not
their occurrences. Position-based identities are not promised stable across
dataset revisions.

Translation language, original language, and gloss language are independent.
For example, a Hebrew token can have an English contextual gloss while the
application displays a French translation. Hebrew tokens remain in logical
source reading order; UI directionality is the application's concern.

## Mapping boundary

Parsing a reference establishes its syntax, not its equivalence between two
editions. `VerseMappingRequest` identifies the source edition/reference scheme
and target dataset/reference scheme. `TableVerseMapper` can return several targets
with matched, partial, ambiguous, or unmapped status. Unknown pairs remain
unmapped. Identity mapping requires a caller-configured compatible pair and is
not inferred from matching numeric addresses. A declared identity pair does not
check whether the target dataset actually contains the mapped chapter or verse;
resource loading and verse lookup perform those checks.

Caller-supplied mapping assertions are not independently verified by this
package. Universal versification conversion, a TVTMS importer, and alignment of
arbitrary translation words to original-language tokens are outside version
0.1.0. This boundary permits later mapping implementations without entangling
edition selection with resource loading.

## Integrity and publication

The manifest lists explicit coverage and relative chapter resources with
SHA-256 integrity values. Decoding rejects unsupported schema versions and
invalid resource paths. Missing coverage, an unavailable resource, malformed
content, and a missing verse are different failures.

The converter validates all supplied input before finalizing its output. Failed
or partial imports must not be exposed as complete datasets. Full sources,
generated data, and caches stay outside the package; representative attributed
fixtures keep tests deterministic and offline. See [content_schema.md](content_schema.md)
and [stepbible_import.md](stepbible_import.md) for serialization and source policy.
