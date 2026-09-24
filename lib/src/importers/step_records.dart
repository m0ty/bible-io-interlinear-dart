import '../import_report.dart';

/// Internal parsed source row; no source-specific record API is exported.
class StepRecord {
  StepRecord({
    required this.sourceFile,
    required this.lineNumber,
    required this.fields,
    required this.bookCode,
    required this.chapter,
    required this.verseLabel,
    required this.reference,
    required this.wordNumber,
    required this.wordType,
  });

  final String sourceFile;
  final int lineNumber;
  final List<String> fields;
  final String bookCode;
  final int chapter;
  final String verseLabel;
  final String reference;
  final String wordNumber;
  final String wordType;
  String get id => fields.first;
  String get locationKey => '$bookCode.$chapter.$verseLabel';

  ImportDiagnostic diagnostic(String code, String message,
          {String? field, ImportSeverity severity = ImportSeverity.error}) =>
      ImportDiagnostic(
        severity: severity,
        code: code,
        sourceFile: sourceFile,
        lineNumber: lineNumber,
        recordId: id,
        field: field,
        message: message,
      );
}

/// Shared TSV framing only. TAGNT and TAHOT interpret their columns separately.
List<StepRecord> readRows({
  required String text,
  required String sourceFile,
  required String header,
  required int minimumColumns,
  required List<ImportDiagnostic> diagnostics,
}) {
  final rows = <StepRecord>[];
  final lines =
      text.replaceFirst(RegExp(r'^\uFEFF'), '').split(RegExp(r'\r\n|\n|\r'));
  final firstContent = lines.firstWhere(
      (line) => line.trim().isNotEmpty && !line.startsWith('#'),
      orElse: () => '');
  // Only the recognized upstream introduction can contain free-form prose.
  // Headerless extracts are accepted, but damaged leading rows are errors.
  var inData =
      !firstContent.startsWith(header == 'Word & Type' ? 'TAGNT ' : 'TAHOT ');
  final referencePattern = RegExp(
      r'^([1-3]?[A-Za-z]{2,3})\.([1-9][0-9]*)\.([0-9]+[a-z]?(?:-[0-9]+[a-z]?)?)((?:\([^)]*\)|\[[^\]]*\]|\{[^}]*\})*)#([0-9]{2}(?:[0-9]{2})?)=([A-Za-z()+]+)$');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('$header\t')) {
      inData = true;
      continue;
    }
    final looksLikeRecord = RegExp(r'^[1-3]?[A-Za-z]{2,3}\.').hasMatch(line);
    // Free-form upstream introduction ends at the first column heading/record.
    if (!inData && !looksLikeRecord) continue;
    inData = true;
    final fields = line.split('\t');
    final match = referencePattern.firstMatch(fields.first);
    if (match == null) {
      diagnostics.add(ImportDiagnostic(
        severity: ImportSeverity.error,
        code: 'invalid_record_reference',
        sourceFile: sourceFile,
        lineNumber: i + 1,
        field: header,
        message: 'Expected a STEPBible book.chapter.verse#word=type record.',
      ));
      continue;
    }
    if (fields.length < minimumColumns || fields.length > 17) {
      diagnostics.add(ImportDiagnostic(
        severity: ImportSeverity.error,
        code: 'invalid_column_count',
        sourceFile: sourceFile,
        lineNumber: i + 1,
        recordId: fields.first,
        message:
            'Expected $minimumColumns through 17 TSV columns; found ${fields.length}.',
      ));
      continue;
    }
    final chapter = int.tryParse(match[2]!);
    if (chapter == null) {
      diagnostics.add(ImportDiagnostic(
        severity: ImportSeverity.error,
        code: 'invalid_chapter_number',
        sourceFile: sourceFile,
        lineNumber: i + 1,
        recordId: fields.first,
        field: 'reference',
        message: 'Chapter number exceeds supported integer bounds.',
      ));
      continue;
    }
    rows.add(StepRecord(
      sourceFile: sourceFile,
      lineNumber: i + 1,
      fields: fields,
      bookCode: match[1]!,
      chapter: chapter,
      verseLabel: match[3]!,
      reference: fields.first.split('#').first,
      wordNumber: match[5]!,
      wordType: match[6]!,
    ));
  }
  if (rows.isEmpty) {
    diagnostics.add(ImportDiagnostic(
      severity: ImportSeverity.error,
      code: 'no_source_records',
      sourceFile: sourceFile,
      lineNumber: 0,
      message: 'No valid STEPBible data records were found.',
    ));
  }
  return rows;
}
