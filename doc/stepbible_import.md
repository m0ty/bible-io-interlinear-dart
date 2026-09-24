# STEPBible import and reproducibility

Version 0.1.0 imports two inspected source formats from
[STEPBible-Data](https://github.com/STEPBible/STEPBible-Data/tree/b99716b0cddb648ddb95cc786a197180f2f97d48):
TAGNT (Greek New Testament) and TAHOT (Hebrew/Aramaic Old Testament). Acquisition,
parsing, reading selection, normalization, and prepared-data loading are separate
operations. The application loading path consumes chapter JSON, not a complete
raw source corpus.

## Exact inputs

[sources.lock.json](../tool/sources.lock.json) pins revision
`b99716b0cddb648ddb95cc786a197180f2f97d48`, original repository-relative paths,
byte lengths, SHA-256 hashes, and Git blob identifiers for these six files:

| Source | Upstream file groups |
| --- | --- |
| TAGNT | Mat-Jhn; Act-Rev |
| TAHOT | Gen-Deu; Jos-Est; Job-Sng; Isa-Mal |

The complete names in the lock are authoritative. The README hash separately
records the inspected repository documentation. Tests use committed small
extracts from these pins and do not fetch a moving branch.

From the repository root, explicitly acquire the complete source files:

```sh
dart pub get
dart run tool/acquire_sources.dart
dart run tool/acquire_sources.dart --verify-only
```

Acquisition writes under `.work/sources` by default. Existing matching files are
verified and reused; mismatching files require `--overwrite`. Downloads are
checked against both size and SHA-256 before replacing a file. `--verify-only`
does not access the network. `--output` selects another local source directory.
Nothing in runtime loading, importing the Dart library, or unit tests performs
this operation automatically.

## Supported reading profiles

### TAGNT: `N`

`N` is the source's "Ancient" reading category: its main vocabulary associated
with NA27, expressed with NA28 spelling where available and THGNT-based
punctuation. Selection includes rows with an unbracketed `N`/`n` source category,
in the source's logical row order. Bracketed variant categories are not alternate
tokens to append. Other source editions such as TR, NA28, SBL, and Tyndale are
not separately selectable profiles in this release.

This is a **STEPBible source reading profile**, not a verified reproduction of
the published NA27 edition. In particular, the pinned files contain 17 NA27
displacement annotations. Some are not safely interpretable as row offsets:
`Mrk.7.30#08` has `NA27«9`, despite being the eighth source word, and
`Mrk.2.19#25` marks a preposition without applying the same mark to the following
pronoun. The importer retains source order rather than inventing edition
reordering rules. The original edition annotations remain source provenance.
This limitation is a reason to select the documented `N` category rather than
label the result an exact NA27 text.

TAGNT's actual columns differ from TAHOT. They include reference/type, Greek
surface plus supplied transliteration, English contextual translation,
disambiguated Strong identifier plus morphology, dictionary form/gloss, edition
membership, variant fields, Spanish translation, and other annotations. The
importer preserves extended identifiers and the source morphology scheme;
spelling variants are not silently substituted into the selected surface.
Editorial apparatus columns (including the optional fourteenth-column variant
notes), alternate tagging, and contextual submeaning annotations are not a
lossless apparatus export. The pinned source and original record IDs remain the
authority for those fields; only edition membership/order annotations are copied
into verse provenance. This release does not interpret those notes as extra
display tokens.

### TAHOT: `L+Q+R`, reading policy `qere`

The supported policy selects the source's main Leningrad (`L`), qere (`Q`), and
restored (`R`) rows. Where the source presents qere as the main reading, that
surface is used; ketiv in the variant fields is not appended as another token.
Restored passages are included as the source marks them. Extra reconstructed
LXX readings (`X`) are excluded by this profile. Selecting a ketiv policy or
including every variant is not implemented.

The header says `R` restores Joshua 21:36-37 and Nehemiah 7:67b from parallel
passages. It also distinguishes Leningrad letters/pointing from qere and ketiv;
therefore `L+Q+R` should not be presented as a diplomatic transcription of one
manuscript. An empty qere can represent an intentional absence of a spoken word,
not a fabricated blank display token.

TAHOT has separate Hebrew, transliteration, English translation, lexical, and
morphology columns. Source `/` boundaries distinguish affixes and roots, while
`\` boundaries mark punctuation. Segmentation uses these supplied boundaries;
it does not infer a new morphological analysis. Hebrew and Aramaic source
markers remain distinct. Stored token order is logical reading order and must
not be reversed for RTL presentation.

## References, identity, and text

The source headers define their primary references using NRSV/English numbering,
with alternative Hebrew or edition references in brackets. The importer keeps
the primary labels and preserves the original source record reference in
provenance. It does not apply a universal versification conversion. Psalm
superscriptions encoded as verse zero are explicit special entries; they are
not reassigned to verse one.

Source word references identify occurrences within this pinned source, whereas
`G…`/`H…` lexical identifiers identify lexical entries. A persistent token key
also includes dataset ID and dataset revision. Do not assume a positional word
reference will continue to identify the same occurrence after a source update.

Greek/Hebrew code points are preserved without destructive Unicode
normalization. Punctuation already in the source is retained. Verse display text
is reconstructed from word rows and separators and is not verified published
edition typography. Supplied transliteration is retained; this package does not
generate transliterations, glosses, or morphological expansions.

## Conversion

Inspect the CLI's exact supported choices:

```sh
dart run bin/convert_stepbible.dart --help
```

For a complete Greek import, pass both locked TAGNT files (repeat `--input`):

```sh
dart run bin/convert_stepbible.dart --source-type tagnt --profile N --input ".work/sources/TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt" --input ".work/sources/TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt" --output dataset/tagnt --dataset-id step-tagnt-n --dataset-revision 0.1.0 --report .work/tagnt-report.json
```

For Hebrew/Aramaic, pass all four locked TAHOT files:

```sh
dart run bin/convert_stepbible.dart --source-type tahot --profile L+Q+R --reading-policy qere --input ".work/sources/TAHOT Gen-Deu - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --input ".work/sources/TAHOT Jos-Est - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --input ".work/sources/TAHOT Job-Sng - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --input ".work/sources/TAHOT Isa-Mal - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt" --output dataset/tahot --dataset-id step-tahot-lqr --dataset-revision 0.1.0 --report .work/tahot-report.json
```

A subset of input files
produces only that supplied coverage; it does not imply complete canon coverage.
The manifest is authoritative for what a dataset actually contains.

Conversion is strict. Diagnostics identify severity, code, source file,
line/record, and field when applicable. A malformed data record is an error,
not a silently omitted verse. The report describes the selected policy and
validation outcome. Failed imports exit nonzero, and an existing dataset is
not replaced unless `--overwrite` is provided. Output is finalized only after
validation succeeds.
The optional `--report` path must be outside the output dataset, which already
includes `import-report.json`. `--diagnostic` collects the validation report
without publishing a dataset. Explicit overwrite retains the previous dataset
as a sibling backup instead of deleting it.

The programmatic API is exported by `stepbible.dart`; it accepts source contents
explicitly rather than interpreting a string as either a file path or text.
See [example/import_stepbible.dart](../example/import_stepbible.dart) for a small
offline import and [example/read_interlinear.dart](../example/read_interlinear.dart)
for normal prepared-data loading.

## Attribution and limits

The source README and individual file headers identify CC BY 4.0 and credit
STEP Bible, based on work at Tyndale House Cambridge. The individual headers
also identify component sources for Greek text, contextual translations,
lexical data, Hebrew text, and morphology. These notices are recorded in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Fixtures identify their
extracted records and modifications; generated datasets carry attribution and
conversion provenance separately from the package's AGPL-3.0 code license.

This importer does not include a lexicon service, alternate-edition apparatus
renderer, universal verse mapping, or translation-to-original word alignment.
It does not assert an independently verified licensing review of upstream
components. Other source profiles require separate evidence and implementation.

Both full locked input sets were converted and all prepared resources were
validated on 24 September 2026. The recorded results and exact commands are in
[validation.md](validation.md); fixture-only tests are not the basis for that
full-input claim.
