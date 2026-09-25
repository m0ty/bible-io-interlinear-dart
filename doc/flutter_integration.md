# Flutter integration contract

Version 0.2.0 keeps source interpretation and correspondence in the pure Dart
package. Flutter owns asset access, gzip decompression, platform scheduling,
localized labels, layout, focus, and animation. Existing chapter/manifest JSON
remains schema 1; importing the package never loads the full corpus.

## Loading a mapped passage

1. Read the prepared correspondence index and decode it with
   `CorrespondenceJsonCodec`. Unknown fields, malformed selectors, inconsistent
   coverage, and missing release bindings are errors. In particular, a misspelled
   `occurrenceIds` field must never expand a word selection to a whole verse.
2. Call `index.validateSourceEdition` with the loaded edition ID, reference
   system, and SHA-256 of its actual asset bytes. An edition name alone does not
   establish compatibility.
3. Construct `CorrespondenceResolver(index: index, openDataset: ...)`. The opener
   calls `CorrespondenceDataset.open(manifestBytes: bytes, reader: reader)`.
   This factory creates the lazy Bible from that exact manifest and checks
   uncompressed chapter bytes against its resource hashes. It prevents pairing
   another Bible's content with a correct manifest. The resolver verifies
   their hash and metadata against the index, including profile and source/data
   revision. Applications can additionally restrict allowed source profiles.
4. Await `resolver.resolve(translationLocation)`. The result keeps
   `translationLocation` separate from native `sourceSelections`. A selector
   addresses an exact verse label or special entry and may supply ordered word
   occurrence IDs. Missing selections fail; ambiguous alternatives are not
   concatenated. Unmapped passages contain no original words.

Keep a resolver for the lifetime of its immutable asset release. Concurrent
dataset opens are deduplicated; failed opens can retry. `InterlinearBible` owns a
bounded chapter cache. Changing an edition or data release requires a new binding,
not reuse of an old successful validation. SHA-256 detects inconsistent bytes;
it does not authenticate an untrusted publisher.

An optional `verifyAndDecodeChapter` hook supplies trusted platform scheduling.
It must invoke `decodeVerifiedInterlinearChapter` or its asynchronous counterpart
on the supplied bytes and expected hash. The hook and reader are application
code, not a sandbox for an untrusted decoder.

The older `VerseMapper`/`TableVerseMapper` APIs remain available. Mapping results
can now carry native `sourceSelections` alongside legacy positive-verse targets.
Equivalent parsed verse labels use canonical lookup keys.

## Word presentation

```dart
final analysis = InterlinearWordAnalyzer(metadata: passage.metadata)
    .analyze(passage.tokens.first);
for (final part in analysis.parts) {
  for (final entry in part.dictionaryEntries) {
    print(entry.form);
    print(entry.glosses['en']);
  }
}
```

Contextual glosses, dictionary meanings, grammatical functions, and source
annotations are separate types. Compound dictionary entries keep the form,
meaning, and lexical reference together where the source establishes that
pairing. Uncertain pairings remain annotations rather than invented matches.
Raw tokens and raw fields remain available for inspection.

Source interpretation requires audited metadata; Greek or Hebrew language alone
does not imply STEPBible notation. A new revision/provider falls back to raw
values until its contract is reviewed. Flutter supplies readable/localized
function labels via `InterlinearGloss.render` and places source codes and
annotations in its technical disclosure.

## Web and release responsibilities

The app loads chapters on demand and retains a bounded cache. On native Flutter,
expensive decode work may run in an isolate; on web, `compute` executes on the
current event loop. Measure cold binding, large chapters, warm lookups, and main
thread pauses in a release browser build before changing storage or scheduling.
Unit-test execution times do not establish browser responsiveness.

`CorrespondenceJsonCodec.decodeAsync`, `InterlinearJsonCodec.decodeChapterAsync`
and `resourceSha256Async` accept an injected scheduling callback. The synchronous
and cooperative paths share validation; no partial result is returned. Flutter
can yield after a short elapsed work budget while native platforms keep using
isolates. UTF-8/JSON parsing and decompression still have synchronous phases;
cooperative decoding is not a claim that all browser work runs on another thread.

The companion app pins an immutable, reachable package Git revision. Developers
can opt into an ignored `pubspec_overrides.yaml` pointing at a sibling checkout;
CI and release builds must resolve without that sibling. Its complete bundle
generator stages data, mapping, file integrity, and provenance before promoting
the bundle, and verifies committed assets without requiring raw source downloads.
PR, Pages, and release workflows share the same verification gate.
