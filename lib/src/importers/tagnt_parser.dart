import '../import_report.dart';
import 'step_records.dart';

/// Parser for the pinned TAGNT column schema, independent of reading selection.
class TagntParser {
  List<StepRecord> parseText(
      String text, String sourceFile, List<ImportDiagnostic> diagnostics) {
    final rows = readRows(
      text: text,
      sourceFile: sourceFile,
      header: 'Word & Type',
      minimumColumns: 13,
      diagnostics: diagnostics,
    );
    for (final row in rows) {
      final fields = row.fields;
      if (!RegExp(r'^(?:[NnKkOo]+|\([NnKkOo]+\))+$').hasMatch(row.wordType)) {
        diagnostics.add(row.diagnostic('unsupported_word_type',
            'Unknown TAGNT word-type marker ${row.wordType}.',
            field: 'Word & Type'));
      }
      if (!RegExp(r'^.+ \([^()]+\)$').hasMatch(fields[1])) {
        diagnostics.add(row.diagnostic('invalid_greek',
            'Expected Greek surface followed by supplied transliteration in parentheses.',
            field: 'Greek'));
      }
      for (final analysis in fields[3].split(' + ')) {
        if (!RegExp(r'^G[0-9]{4,}[A-Za-z]*=[A-Za-z0-9-]+$')
            .hasMatch(analysis)) {
          diagnostics.add(row.diagnostic('invalid_lexical_morphology',
              'Expected dStrong=grammar, optionally joined by " + ".',
              field: 'dStrongs = Grammar'));
        }
      }
      if (fields[4].isEmpty || !fields[4].contains('=')) {
        diagnostics.add(row.diagnostic(
            'invalid_dictionary_form', 'Expected dictionary form = gloss.',
            field: 'Dictionary form = Gloss'));
      }
      if (fields[5].isEmpty) {
        diagnostics.add(row.diagnostic(
            'missing_editions', 'Edition membership is required.',
            field: 'editions'));
      }
    }
    return rows;
  }
}
