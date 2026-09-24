# Recorded full-input validation

On **24 September 2026**, both complete pinned STEPBible input sets were
converted successfully with the package CLI. Each command exited **0**. Before
finalizing each dataset, the CLI loaded the staged manifest and attribution and
decoded every chapter through `JsonInterlinearDataSource`, checking resource
hashes and normalized models.

These results concern the supported source profiles and the exact bytes below.
They establish full-input format handling, selection, normalization,
serialization, and runtime readability. They do not establish textual
equivalence to a published Greek edition, universal verse correspondence, or an
independent licensing review.

## Environment and pins

- Dart SDK **3.11.4 stable**, `windows_x64`.
- Resolved `bible_io` **1.2.0**, with transitive `bible_io_references` **1.2.0**.
  The package imports reference types through Bible-IO's public entry point.
- Resolved direct tooling dependencies: `crypto` **3.0.7** and `args` **2.7.0**.
- STEPBible-Data revision:
  `b99716b0cddb648ddb95cc786a197180f2f97d48`.
- All six complete input files matched their byte lengths and SHA-256 hashes in
  [sources.lock.json](../tool/sources.lock.json), checked using
  `dart run tool/acquire_sources.dart --verify-only`.
- The acquisition utility also successfully downloaded the pinned TAHOT Job-Sng
  file into a separate ignored smoke-test directory and verified its bytes.

The Windows Flutter `dart.bat` launcher stalled in this environment. Actual
commands used the bundled SDK executable at
`C:/FlutterSDK/flutter/bin/cache/dart-sdk/bin/dart.exe`; the portable commands
below use `dart` and require a working Dart SDK on `PATH`. No machine-specific
dependency paths are in the package manifest.

The existing ecosystem was inspected read-only at these revisions:

| Repository | Inspected commit |
| --- | --- |
| [bible-io-package-dart](https://github.com/m0ty/bible-io-package-dart/tree/5061c978a9183b89d5145731fa40feb2775058ee) | `5061c978a9183b89d5145731fa40feb2775058ee` |
| [bible-io-references-dart](https://github.com/m0ty/bible-io-references-dart/tree/9a3ac68cdf65ffcfc3ed52a707df0dd93d16b5a4) | `9a3ac68cdf65ffcfc3ed52a707df0dd93d16b5a4` |
| [BibleIO-Flutter-App](https://github.com/m0ty/BibleIO-Flutter-App/tree/7599596db1bbbdab7af0dce3a5a35df5bbbec7e8) | `7599596db1bbbdab7af0dce3a5a35df5bbbec7e8` |

Inspection covered public models, locations and verse labels, loading APIs,
tests, package manifests, content-schema documentation, and license files. The
new companion depends on published package versions; these checkout revisions
are inspection provenance rather than path dependencies. Existing repositories
were not modified.

## Executed supporting checks

| Command | Observed result |
| --- | --- |
| `dart --version` | 3.11.4 stable on Windows x64 |
| `dart pub get` | Passed; published dependencies resolved to the versions above |
| `dart format --output=none --set-exit-if-changed .` | Passed; 25 files, zero changes |
| `dart analyze` | Passed; no issues found |
| `dart test` | Passed; all 55 tests, including 17 importer regression tests |
| `dart run bin/convert_stepbible.dart --help` | Passed; lists source formats, `N`, `L+Q+R`, and `qere` |
| `dart run tool/acquire_sources.dart --verify-only` | Passed for all six complete pinned source files |
| `dart run example/import_stepbible.dart` | Passed; small authentic fixture serialized to prepared chapters |
| `dart run example/read_interlinear.dart` | Passed; prepared chapter loaded and token data printed |
| `dart run tool/verify_dataset.dart .work/example-dataset` | Passed; fixture dataset resources and occurrence IDs verified |
| `dart pub publish --dry-run` | Passed with zero warnings; nothing was published |

After the internal-maqaf segmentation correction and stricter diagnostic
validation, both complete conversions were repeated successfully in
`.work/final-tagnt` and `.work/final-tahot`; their counts match the table below.
The final fixture examples also passed in `.work/final-example` (seven chapters,
117 tokens), including runtime lookup of Matthew 1:1 and the standalone verifier.

The separate offline acquisition tests also passed: exact bytes accepted,
changed bytes rejected, unavailable files rejected, and traversal rejected.
The CLI tests passed for fixture-to-runtime loading, malformed input without
partial publication, protected replacement with retained backup, report/input
collision protection, and report-only diagnostic mode.

## Results

| Measurement | TAGNT | TAHOT |
| --- | ---: | ---: |
| Source profile | `N` | `L+Q+R` |
| Hebrew reading policy | Not applicable | `qere` |
| Parsed source records | 142,096 | 305,652 |
| Selected displayed tokens | 137,646 | 305,486 |
| Excluded source records | 4,450 | 166 |
| Books with coverage | 27 | 39 |
| Chapters written and verified | 260 | 929 |
| Ordinary verse entries | 7,918 | 23,145 |
| Special entries | 0 | 116 |
| Error diagnostics | 0 | 0 |

The Greek run emitted **17 warnings** with code `edition_order_annotation`.
The `N` profile retains source row order, preserving the source edition
annotations in provenance instead of interpreting ambiguous NA27 displacement
markers. It is not advertised as exact NA27 reconstruction.

The Hebrew/Aramaic run emitted **14 informational diagnostics** with code
`qere_omission`: the source explicitly supplies no spoken qere token at these
positions. TAHOT special entries preserve source verse-zero headings rather
than assigning invented positive verse numbers. Manifest original languages
are `hbo` and `arc`; TAGNT uses `grc`. The gloss languages are `en` for TAHOT and
`en`, `es` for TAGNT.

## Exact complete conversion commands

Run from the repository root after source acquisition. These paths keep source
and generated corpora in the ignored `.work` directory. Existing outputs require
an explicit `--overwrite`; it retains the old dataset as a sibling backup.

```sh
dart run tool/acquire_sources.dart
dart run tool/acquire_sources.dart --verify-only
dart run bin/convert_stepbible.dart --source-type tagnt --profile N --input ".work/sources/TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt" --input ".work/sources/TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt" --dataset-id step-tagnt-n --dataset-revision 0.1.0 --output .work/full-tagnt --report .work/full-tagnt-report.json
dart run bin/convert_stepbible.dart --source-type tahot --profile L+Q+R --reading-policy qere --input ".work/sources/TAHOT Gen-Deu - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --input ".work/sources/TAHOT Jos-Est - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --input ".work/sources/TAHOT Job-Sng - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --input ".work/sources/TAHOT Isa-Mal - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --dataset-id step-tahot-lqr --dataset-revision 0.1.0 --output .work/full-tahot --report .work/full-tahot-report.json
```

The CLI's default source revision is the pinned revision above. To import other
input bytes, supply and document their real source revision; doing so does not
extend the tested source-format or profile claims. The importer records input
content hashes, and the acquisition tool verifies complete upstream files
against the lock. Small committed fixtures are extracts with separate fixture
hashes and source-line provenance.

Full source files, generated chapters, reports, and smoke-test downloads remain
local and are excluded from Git and publication. Re-running these commands
produces the report evidence; they are not part of the offline unit test suite.
