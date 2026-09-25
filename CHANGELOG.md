## 0.3.0

- Public correspondence builders and provider-neutral schema 2 allow independent
  editions, source providers, revisions and reference systems. Schema 1 remains
  readable for existing integrations; chapter assets remain schema 1.
- Custom word-analysis adapters support additional provider contracts and gloss
  languages without changing the core package or its audited STEPBible defaults.
- Added a standalone, in-memory Dart consumer and framework-independent guide.
- Migration: correspondence-wide `sourceRevision` and `targetReferenceSystem`
  are nullable common-value getters; use each dataset binding for mixed sources.
  Exhaustive switches over `InterlinearAnalysisSource` must handle `custom`.

## 0.2.0

- Typed, source-aware word analysis separates contextual glosses, dictionary
  entries, grammatical functions, and original source annotations.
- Strict correspondence documents and a reusable passage resolver support
  ordered word selections and superscriptions with dataset identity checks.
- Equivalent verse labels share mapping keys while retaining original labels.
- Cooperative decoding and hashing let web applications yield between batches
  without weakening validation or exposing partially checked results.
- Existing schema-v1 chapter assets and runtime APIs remain supported.

## 0.1.0

- Immutable interlinear tokens, segments, verse labels, and dataset identities.
- Deterministic prepared JSON with integrity checks and bounded chapter loading.
- Explicit reference mapping and pinned STEPBible import workflows.
