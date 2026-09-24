# Prepared content schema 1

UTF-8 JSON resources are generated deterministically: object keys sort
lexicographically, chapter resource entries sort by USFM book/chapter key,
coverage chapter numbers sort numerically, and each resource ends in LF. Token
and segment array order is logical source reading order. Unicode is preserved;
the converter does not normalize Greek or Hebrew characters.

`manifest.json` has `schemaVersion: 1`, `bookNamespace: "USFM"`, `metadata`,
`chapters`, and `attribution`. The schema is separate from the Bible-IO content
schema. Each chapter resource has `book`, positive `chapter`, relative `path`,
and lowercase hex `sha256`. Attribution has `path` and `sha256`. Coverage and
chapter resources must agree exactly, without duplicates. The manifest itself
must come from a trusted application source; hashes detect corruption, not
publisher authenticity.

Metadata contains `datasetId`, `datasetRevision`, `schemaVersion`, `source`,
`sourceRevision`, `profile`, nullable `readingPolicy`, `referenceSystem`,
`originalLanguages`, `glossLanguages`, `coverage` (USFM book keys to chapter
arrays), and string maps `provenance` and `attribution`. Dataset revision,
original-text selection, and verse numbering are independent identifiers.
Coverage means available chapter resources; fixture datasets can contain only
selected verse entries within those chapters. A missing entry is a lookup error.

Chapter files have `schemaVersion`, `book`, `chapter`, `verses`, and
`specialEntries`. Each verse has its exact `label` string, ordered `tokens`,
nullable `surfaceText`, `textIsReconstructed`, and `provenance`. Labels use the
public Bible-IO `VerseLabel` grammar, including `5a` and `29-30`. Do not coerce
labels to integers. Special entries have `sourceLabel`, `kind`, `tokens`,
nullable `surfaceText`, and `provenance`; they have no fabricated positive verse
location. Psalm verse-zero superscriptions are represented here.

Tokens contain `occurrenceId`, nullable `sourceRecordId`, `surface`, `language`,
nullable `transliteration`, `glosses` (language to string), `segments`,
`separatorAfter`, and nullable `sourceText`. Source punctuation may remain in
surface text; `sourceText` preserves source segmentation markup. Segments have
nullable `text`, `kind`, `lemma`, plus `glosses`, `lexicalReferences`, and
`morphology`. A lexical reference has `system`, `value`, and nullable
`traditionalStrongs`. A morphology tag has `scheme` and `code`. Complete
extended identifiers and source schemes must be retained.

All listed fields are required in serialized manifest/chapter objects, including
nullable fields. Unknown fields, wrong types, invalid model values, and unknown
schema versions are errors. A future format change requires a new schema.
Occurrence IDs are unique within a dataset. Persistent identity is the tuple
`(datasetId, datasetRevision, occurrenceId)`; positional IDs are not guaranteed
stable between revisions. Verse and segment objects are immutable in memory.

Paths permit ASCII letters, digits, `_`, `-`, `.`, and `/`, with no empty, `.`
or `..` components. Absolute paths, drive letters, backslashes, percent escapes,
URLs and traversal are rejected before reader access. Windows device names,
components ending in a dot, and case-insensitive resource path collisions are
also rejected for portable datasets. A filesystem reader owns
its dataset root and must not place symlinks to external resources inside it.

`attribution.json` repeats schema, dataset/source identities, provenance and
attribution; the loader verifies its digest and consistency with the manifest.
`import-report.json` is converter output for auditing and is not a runtime
resource. Validation failures cannot produce a complete dataset.
