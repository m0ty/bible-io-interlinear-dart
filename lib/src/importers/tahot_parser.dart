import '../import_report.dart';
import 'step_records.dart';

/// Parser for the separate TAHOT column schema.
class TahotParser {
  List<StepRecord> parseText(
      String text, String sourceFile, List<ImportDiagnostic> diagnostics) {
    final rows = readRows(
      text: text,
      sourceFile: sourceFile,
      header: 'Eng (Heb) Ref & Type',
      minimumColumns: 12,
      diagnostics: diagnostics,
    );
    for (final row in rows) {
      final fields = row.fields;
      if (!RegExp(r'^[LQRX][LABCDEFHKPQRSVXabcdefghkpqsvx+()]*$')
              .hasMatch(row.wordType) ||
          !RegExp(r'^[LQRX][A-Za-z]*(?:\([A-Za-z]+(?:\+[A-Za-z]+)*\))*$')
              .hasMatch(row.wordType)) {
        diagnostics.add(row.diagnostic('unsupported_word_type',
            'Unknown TAHOT main-reading marker ${row.wordType}.',
            field: 'Eng (Heb) Ref & Type'));
      }
      if (isQereOmission(row)) continue;
      if (fields[1].isEmpty ||
          fields[4].isEmpty ||
          !RegExp(r'^[HA][A-Za-z0-9/]+$').hasMatch(fields[5])) {
        diagnostics.add(row.diagnostic('invalid_hebrew_analysis',
            'A non-omitted word requires Hebrew, dStrongs, and H/A-prefixed grammar.',
            field: 'Grammar'));
        continue;
      }
      final segments = fields[1].split('/').length;
      for (final column in [3, 4, 5, 11]) {
        if (fields[column].split('/').length != segments) {
          diagnostics.add(row.diagnostic('segment_count_mismatch',
              'Slash-delimited segment counts disagree with the Hebrew field.',
              field: [
                'Hebrew',
                'Transliteration',
                'Translation',
                'dStrongs',
                'Grammar',
                'Meaning Variants',
                'Spelling Variants',
                'Root dStrong+Instance',
                'Alternative Strongs+Instance',
                'Conjoin word',
                'Expanded Strong tags'
              ][column - 1]));
        }
      }
      if (!RegExp(r'^[H0-9A-Za-z{}+/\\ ]+$').hasMatch(fields[4])) {
        diagnostics.add(row.diagnostic('invalid_lexical_reference',
            'Unexpected characters in TAHOT dStrongs.',
            field: 'dStrongs'));
      }
      for (final lex in fields[4].split(RegExp(r'[/\\]+'))) {
        if (lex.trim().isNotEmpty &&
            !RegExp(r'^(?:H[0-9]{4,}[A-Za-z]*|\{H[0-9]{4,}[A-Za-z]*\})\+?$')
                .hasMatch(lex.trim())) {
          diagnostics.add(row.diagnostic('invalid_lexical_reference',
              'Expected a complete extended Hebrew lexical tag, with optional root braces and continuation +.',
              field: 'dStrongs'));
        }
      }
      final texts = fields[1].split('/');
      final tags = fields[4].split('/');
      final expanded = fields[11].split('/');
      final grammar = fields[5].split('/');
      final glosses = fields[3].split('/');
      if (texts.length == tags.length && texts.length == expanded.length) {
        for (var i = 0; i < texts.length; i++) {
          if (texts[i].isEmpty &&
              (tags[i].trim().isNotEmpty ||
                  expanded[i].trim().isNotEmpty ||
                  (i < grammar.length && grammar[i].trim().isNotEmpty) ||
                  (i < glosses.length && glosses[i].trim().isNotEmpty))) {
            diagnostics.add(row.diagnostic('analysis_without_segment',
                'An empty double-slash word boundary cannot contain lexical or grammatical analysis.',
                field: 'Hebrew'));
          }
          final count = texts[i].split(RegExp(r'\\+')).length;
          if (tags[i].split(RegExp(r'\\+')).length != count ||
              expanded[i].split(RegExp(r'\\+')).length != count) {
            diagnostics.add(row.diagnostic('punctuation_count_mismatch',
                'Backslash-delimited punctuation does not align with the lexical fields.',
                field: 'Hebrew'));
          }
        }
      }
    }
    return rows;
  }
}

bool isQereOmission(StepRecord row) =>
    row.wordType.startsWith('Q') &&
    row.fields[1].isEmpty &&
    row.fields[2] == '[ ]' &&
    row.fields[3] == '[ ]' &&
    row.fields[4].isEmpty &&
    row.fields[5].isEmpty &&
    row.fields[6].startsWith('K=');
