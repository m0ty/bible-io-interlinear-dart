import 'dart:convert';

import 'package:bible_io/bible_io.dart';
import 'package:crypto/crypto.dart';

import '../import_report.dart';
import '../models.dart';
import 'edition_selector.dart';
import 'step_records.dart';
import 'tagnt_parser.dart';
import 'tahot_parser.dart';

enum StepSourceType { tagnt, tahot }

/// Explicit source contents and a provenance name, never an implicit file read.
class StepSource {
  const StepSource({required this.text, required this.sourceFile});

  factory StepSource.fromBytes(
          {required List<int> bytes, required String sourceFile}) =>
      StepSource(text: utf8.decode(bytes), sourceFile: sourceFile);

  final String text;
  final String sourceFile;
}

/// Supported source-native profiles, distinct from exact published editions.
class StepImportConfig {
  StepImportConfig({
    required this.sourceType,
    required this.datasetId,
    required this.datasetRevision,
    required this.sourceRevision,
    required this.profile,
    this.readingPolicy,
  }) {
    for (final entry in {
      'datasetId': datasetId,
      'datasetRevision': datasetRevision,
      'sourceRevision': sourceRevision,
      'profile': profile,
    }.entries) {
      if (entry.value.trim().isEmpty || entry.value.trim() != entry.value) {
        throw ArgumentError.value(entry.value, entry.key,
            'must be nonblank without surrounding whitespace');
      }
    }
    if (sourceType == StepSourceType.tagnt &&
        (profile != 'N' || readingPolicy != null)) {
      throw ArgumentError(
          'TAGNT supports profile N (Ancient source-row reading) '
          'without a Hebrew reading policy. Exact NA27/NA28 reconstruction is not supported.');
    }
    if (sourceType == StepSourceType.tahot &&
        (profile != 'L+Q+R' || readingPolicy != 'qere')) {
      throw ArgumentError(
          'TAHOT supports profile L+Q+R with readingPolicy qere. '
          'Inline ketiv variants and X additions are not selected.');
    }
  }

  final StepSourceType sourceType;
  final String datasetId;
  final String datasetRevision;
  final String sourceRevision;
  final String profile;
  final String? readingPolicy;
}

/// Validated prepared models. Never returned for a failed or partial import.
class StepImportResult {
  StepImportResult(
      {required this.metadata,
      required List<InterlinearChapter> chapters,
      required this.report})
      : chapters = List.unmodifiable(chapters);

  final InterlinearMetadata metadata;
  final List<InterlinearChapter> chapters;
  final ImportReport report;
}

/// Strict offline parsing, reading selection, and normalization.
class StepImporter {
  StepImportResult importSources(
      {required Iterable<StepSource> sources,
      required StepImportConfig config}) {
    final inputs = sources.toList()
      ..sort((a, b) => a.sourceFile.compareTo(b.sourceFile));
    final diagnostics = <ImportDiagnostic>[];
    final records = <StepRecord>[];
    final ids = <String>{};
    final sourceNames = <String>{};
    final lastWords = <String, String>{};
    for (final input in inputs) {
      if (input.sourceFile.trim().isEmpty) {
        throw ArgumentError('sourceFile must be nonblank.');
      }
      if (!sourceNames.add(input.sourceFile)) {
        diagnostics.add(ImportDiagnostic(
            severity: ImportSeverity.error,
            code: 'duplicate_source_name',
            sourceFile: input.sourceFile,
            lineNumber: 0,
            message:
                'Source names must uniquely identify inputs and their provenance hashes.'));
      }
      final parsed = config.sourceType == StepSourceType.tagnt
          ? TagntParser().parseText(input.text, input.sourceFile, diagnostics)
          : TahotParser().parseText(input.text, input.sourceFile, diagnostics);
      for (final row in parsed) {
        if (!ids.add(row.id)) {
          diagnostics.add(row.diagnostic('duplicate_record',
              'This record ID appeared more than once in the provided inputs.'));
        }
        final lastWord = lastWords[row.reference];
        if (lastWord != null && row.wordNumber.compareTo(lastWord) <= 0) {
          diagnostics.add(row.diagnostic(
              'invalid_source_order',
              'Word numbers must increase in source row order within each verse. '
                  'Input files are processed by sourceFile name; discontinuous splits are unsupported.',
              field: 'reference'));
        }
        lastWords[row.reference] = row.wordNumber;
        try {
          bibleBookFromUsfmIdentifier(row.bookCode.toUpperCase());
        } on ArgumentError {
          diagnostics.add(row.diagnostic('unsupported_book',
              'Unknown STEPBible/USFM book code ${row.bookCode}.',
              field: 'reference'));
        }
        if (row.verseLabel != '0' &&
            VerseLabel.tryParse(row.verseLabel) == null) {
          diagnostics.add(row.diagnostic('invalid_verse_label',
              'Verse label is invalid under Bible-IO reference conventions.',
              field: 'reference'));
        }
      }
      records.addAll(parsed);
    }
    if (inputs.isEmpty) {
      diagnostics.add(const ImportDiagnostic(
          severity: ImportSeverity.error,
          code: 'no_sources',
          sourceFile: '<input>',
          lineNumber: 0,
          message: 'At least one source input is required.'));
    }
    final selected = config.sourceType == StepSourceType.tagnt
        ? selectTagntN(records, diagnostics)
        : selectTahotLqr(records, diagnostics);
    if (selected.isEmpty) {
      diagnostics.add(const ImportDiagnostic(
          severity: ImportSeverity.error,
          code: 'empty_selection',
          sourceFile: '<input>',
          lineNumber: 0,
          message: 'The requested profile selected no displayed words.'));
    }
    ImportReport report({int tokenCount = 0, int chapterCount = 0}) =>
        ImportReport(
          diagnostics: diagnostics,
          parsedRecords: records.length,
          selectedRecords: selected.length,
          excludedRecords: records.length - selected.length,
          tokenCount: tokenCount,
          chapterCount: chapterCount,
        );
    if (diagnostics.any((d) => d.severity == ImportSeverity.error)) {
      throw StepImportException(report());
    }
    final grouped = <String, List<StepRecord>>{};
    for (final row in selected) {
      grouped.putIfAbsent(row.locationKey, () => []).add(row);
    }
    final verses = <String, List<InterlinearVerse>>{};
    final special = <String, List<InterlinearSpecialEntry>>{};
    final chapterInfo = <String, (BibleBookEnum, int)>{};
    var tokenCount = 0;
    for (final rows in grouped.values) {
      final first = rows.first;
      final book = bibleBookFromUsfmIdentifier(first.bookCode.toUpperCase());
      final chapterKey = '${first.bookCode}.${first.chapter}';
      chapterInfo[chapterKey] = (book, first.chapter);
      try {
        final tokens = [
          for (final row in rows)
            config.sourceType == StepSourceType.tagnt
                ? _greek(row)
                : _hebrew(row)
        ];
        tokenCount += tokens.length;
        final provenance = <String, String>{
          'sourceFile': first.sourceFile,
          'sourceReferences': rows.map((r) => r.reference).toSet().join('; '),
          'firstSourceLine': '${first.lineNumber}',
          'lastSourceLine': '${rows.last.lineNumber}',
          'formatting':
              'Reconstructed from selected word rows; source punctuation retained.',
          if (config.sourceType == StepSourceType.tagnt)
            'editionAnnotations':
                rows.map((r) => '${r.wordNumber}=${r.fields[5]}').join('; '),
        };
        if (first.verseLabel == '0') {
          special.putIfAbsent(chapterKey, () => []).add(InterlinearSpecialEntry(
                sourceLabel: first.reference,
                kind: book == BibleBookEnum.psalms
                    ? 'superscription'
                    : 'source-entry',
                tokens: tokens,
                provenance: provenance,
              ));
        } else {
          final label = VerseLabel.parse(first.verseLabel);
          verses.putIfAbsent(chapterKey, () => []).add(InterlinearVerse(
                location: BibleLocation.checked(
                    book: book,
                    chapter: first.chapter,
                    verse: label.startVerse,
                    verseLabel: first.verseLabel),
                tokens: tokens,
                textIsReconstructed: true,
                provenance: provenance,
              ));
        }
      } on FormatException catch (error) {
        diagnostics.add(first.diagnostic('normalization_failed', '$error'));
      } on ParseVerseRefError catch (error) {
        diagnostics.add(first.diagnostic('normalization_failed', '$error'));
      } on ArgumentError catch (error) {
        diagnostics.add(first.diagnostic('normalization_failed', '$error'));
      }
    }
    final chapters = <InterlinearChapter>[];
    for (final entry in chapterInfo.entries) {
      try {
        chapters.add(InterlinearChapter(
            book: entry.value.$1,
            chapter: entry.value.$2,
            verses: verses[entry.key] ?? [],
            specialEntries: special[entry.key] ?? []));
      } on ArgumentError catch (error) {
        diagnostics.add(ImportDiagnostic(
            severity: ImportSeverity.error,
            code: 'invalid_chapter',
            sourceFile: '<selected>',
            lineNumber: 0,
            recordId: entry.key,
            message: '$error'));
      }
    }
    if (diagnostics.any((d) => d.severity == ImportSeverity.error)) {
      throw StepImportException(report());
    }
    chapters.sort((a, b) => a.book.index != b.book.index
        ? a.book.index.compareTo(b.book.index)
        : a.chapter.compareTo(b.chapter));
    final coverage = <BibleBookEnum, List<int>>{};
    for (final chapter in chapters) {
      coverage.putIfAbsent(chapter.book, () => []).add(chapter.chapter);
    }
    final languages = <String>{};
    final glossLanguages = <String>{};
    for (final chapter in chapters) {
      for (final tokens in [
        ...chapter.verses.map((v) => v.tokens),
        ...chapter.specialEntries.map((e) => e.tokens),
      ]) {
        for (final token in tokens) {
          languages.add(token.language);
          glossLanguages.addAll(token.glosses.keys);
        }
      }
    }
    return StepImportResult(
      metadata: InterlinearMetadata(
        datasetId: config.datasetId,
        datasetRevision: config.datasetRevision,
        source: 'STEPBible ${config.sourceType.name.toUpperCase()}',
        sourceRevision: config.sourceRevision,
        profile: config.profile,
        readingPolicy: config.readingPolicy,
        referenceSystem: 'STEPBible-NRSV',
        originalLanguages: languages.toList()..sort(),
        glossLanguages: glossLanguages.toList()..sort(),
        coverage: coverage,
        provenance: {
          'upstream': 'https://github.com/STEPBible/STEPBible-Data',
          'sourceFiles': inputs.map((s) => s.sourceFile).join('; '),
          for (final input in inputs)
            'sourceTextSha256:${input.sourceFile}':
                sha256.convert(utf8.encode(input.text)).toString(),
          'selection': config.sourceType == StepSourceType.tagnt
              ? 'Unbracketed N/n main readings in TAGNT source row order; no exact edition reconstruction.'
              : 'L/Q/R main readings in TAHOT source row order; qere omissions honored; X and inline variants excluded.',
          'occurrenceIdentity':
              'Source reference and word number, scoped to dataset ID and revision; not stable across revisions.',
        },
        attribution: {
          'creator': 'STEPBible.org, based on work at Tyndale House Cambridge',
          'license': 'CC BY 4.0',
          'licenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
          'source': 'https://github.com/STEPBible/STEPBible-Data',
          'components': config.sourceType == StepSourceType.tagnt
              ? 'English: Berean Study Bible (with permission, adapted, 2019-07-01); '
                  'Spanish: Marvel Bible Project/OpenGNT (2019-01-09); '
                  'grammar: James Tauber with Tyndale additions; dictionary forms: TBESG.'
              : 'Hebrew: Westminster Leningrad Codex 4.20 via OpenScriptures, '
                  'checked/corrected by Tyndale scholars; morphology: ETCBC with '
                  'Tyndale adaptations following OpenScriptures codes; ketiv analysis by Tyndale scholars.',
          'modifications':
              'Selected source-native reading; reformatted into chapter JSON; display spacing reconstructed. '
                  'No source Unicode normalization, new glosses, or morphology expansion.',
        },
      ),
      chapters: chapters,
      report: report(tokenCount: tokenCount, chapterCount: chapters.length),
    );
  }

  /// Collects validation diagnostics, withholding all data on any error.
  ImportReport validateSources(
      {required Iterable<StepSource> sources,
      required StepImportConfig config}) {
    try {
      return importSources(sources: sources, config: config).report;
    } on StepImportException catch (error) {
      return error.report;
    }
  }
}

InterlinearToken _greek(StepRecord row) {
  final fields = row.fields;
  final match = RegExp(r'^(.+) \(([^()]+)\)$').firstMatch(fields[1])!;
  final analyses =
      fields[3].split(' + ').map((value) => value.split('=')).toList();
  final dictionaries = fields[4].split(' + ').map((value) {
    final split = value.indexOf('=');
    return split < 0
        ? [value, '']
        : [value.substring(0, split), value.substring(split + 1)];
  }).toList();
  return InterlinearToken(
    occurrenceId: 'TAGNT:${row.id.split('=').first}',
    sourceRecordId: row.id,
    sourceText: fields[1],
    surface: match[1]!,
    language: 'grc',
    transliteration: match[2],
    glosses: {
      if (fields[2].isNotEmpty) 'en': fields[2],
      if (fields[8].isNotEmpty) 'es': fields[8]
    },
    segments: [
      InterlinearSegment(
        text: match[1],
        kind: 'whole-word',
        lemma: dictionaries.map((d) => d[0]).join(' + '),
        lexicalReferences: [
          for (final item in analyses)
            LexicalReference(system: 'STEPBible-dStrongs', value: item[0])
        ],
        morphology: [
          for (final item in analyses)
            MorphologyTag(scheme: 'STEPBible-TAGNT', code: item[1])
        ],
        glosses: {'en': dictionaries.map((d) => d[1]).join(' + ')},
      )
    ],
  );
}

InterlinearToken _hebrew(StepRecord row) {
  final fields = row.fields;
  final texts = fields[1].split('/');
  final lexical = fields[4].split('/');
  final grammar = fields[5].split('/');
  final glosses = fields[3].split('/');
  final expanded = fields[11].split('/');
  final segments = <InterlinearSegment>[];
  for (var i = 0; i < texts.length; i++) {
    if (texts[i].isEmpty) {
      continue; // Source // denotes a word break within qere.
    }
    final textParts = texts[i].split(RegExp(r'\\+'));
    final lexParts = lexical[i].split(RegExp(r'\\+'));
    final expandedParts = expanded[i].split(RegExp(r'\\+'));
    // Gen 14:17 Kedorlaomer contains an internal maqaf inside a single root.
    // The source explicitly calls this out. Do not label the remaining name
    // as punctuation or invent a division of its root analysis.
    if (textParts
        .skip(1)
        .any((p) => RegExp(r'^[־׀׃].*[\u05D0-\u05EA]').hasMatch(p))) {
      final definition =
          expandedParts.first.replaceAll(RegExp(r'[{}]'), '').split('=');
      segments.add(InterlinearSegment(
        text: texts[i].replaceAll('\\', ''),
        kind: lexical[i].startsWith('{') ? 'root' : 'constituent',
        lemma: definition.length >= 3 ? definition[1] : null,
        lexicalReferences: [
          for (final lex in lexParts)
            if (lex.trim().isNotEmpty)
              LexicalReference(
                  system: 'STEPBible-dStrongs',
                  value: lex.replaceAll(RegExp(r'[{}]'), '').trim())
        ],
        morphology: [
          if (grammar[i].isNotEmpty)
            MorphologyTag(scheme: 'STEPBible-TAHOT', code: grammar[i])
        ],
        glosses: {if (glosses[i].trim().isNotEmpty) 'en': glosses[i].trim()},
      ));
      continue;
    }
    for (var p = 0; p < textParts.length; p++) {
      if (textParts[p].isEmpty) continue;
      final lex = p < lexParts.length
          ? lexParts[p].replaceAll(RegExp(r'[{}]'), '').trim()
          : '';
      String? lemma;
      if (p < expandedParts.length) {
        final definition =
            expandedParts[p].replaceAll(RegExp(r'[{}]'), '').split('=');
        if (definition.length >= 3 && definition[1].isNotEmpty) {
          lemma = definition[1];
        }
      }
      final punctuation =
          p > 0 || (lex == 'H9014' || lex == 'H9015' || lex == 'H9016');
      segments.add(InterlinearSegment(
        text: textParts[p],
        kind: punctuation
            ? 'punctuation'
            : lexical[i].startsWith('{')
                ? 'root'
                : 'constituent',
        lemma: lemma,
        lexicalReferences: [
          if (lex.isNotEmpty)
            LexicalReference(system: 'STEPBible-dStrongs', value: lex)
        ],
        morphology: [
          if (p == 0 && grammar[i].isNotEmpty)
            MorphologyTag(scheme: 'STEPBible-TAHOT', code: grammar[i])
        ],
        glosses: {
          if (p == 0 && glosses[i].trim().isNotEmpty) 'en': glosses[i].trim()
        },
      ));
    }
  }
  final surface =
      fields[1].replaceAll('//', ' ').replaceAll('/', '').replaceAll('\\', '');
  return InterlinearToken(
    occurrenceId: 'TAHOT:${row.id.split('=').first}',
    sourceRecordId: row.id,
    sourceText: fields[1],
    surface: surface,
    language: fields[5].startsWith('A') ? 'arc' : 'hbo',
    transliteration: fields[2].isEmpty ? null : fields[2],
    glosses: {if (fields[3].isNotEmpty) 'en': fields[3]},
    segments: segments,
    separatorAfter: surface.endsWith('־') ? '' : ' ',
  );
}
