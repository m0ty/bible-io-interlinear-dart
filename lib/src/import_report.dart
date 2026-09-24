/// Diagnostic severity; only errors prevent publication of a dataset.
enum ImportSeverity { info, warning, error }

/// A source-specific, actionable import diagnostic.
class ImportDiagnostic {
  const ImportDiagnostic({
    required this.severity,
    required this.code,
    required this.sourceFile,
    required this.lineNumber,
    required this.message,
    this.recordId,
    this.field,
  });

  final ImportSeverity severity;
  final String code;
  final String sourceFile;
  final int lineNumber;
  final String message;
  final String? recordId;
  final String? field;

  Map<String, Object?> toJson() => {
        'severity': severity.name,
        'code': code,
        'sourceFile': sourceFile,
        'lineNumber': lineNumber,
        if (recordId != null) 'recordId': recordId,
        if (field != null) 'field': field,
        'message': message,
      };

  @override
  String toString() =>
      '$sourceFile:$lineNumber: ${severity.name} $code: $message';
}

/// Validation results. A report with errors never accompanies usable data.
class ImportReport {
  ImportReport({
    required Iterable<ImportDiagnostic> diagnostics,
    required this.parsedRecords,
    required this.selectedRecords,
    required this.excludedRecords,
    required this.tokenCount,
    required this.chapterCount,
  }) : diagnostics = List.unmodifiable(diagnostics);

  final List<ImportDiagnostic> diagnostics;
  final int parsedRecords;
  final int selectedRecords;
  final int excludedRecords;
  final int tokenCount;
  final int chapterCount;
  bool get hasErrors =>
      diagnostics.any((d) => d.severity == ImportSeverity.error);

  Map<String, Object?> toJson() => {
        'valid': !hasErrors,
        'parsedRecords': parsedRecords,
        'selectedRecords': selectedRecords,
        'excludedRecords': excludedRecords,
        'tokenCount': tokenCount,
        'chapterCount': chapterCount,
        'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
      };
}

/// A failed strict import, containing all collected validation problems.
class StepImportException implements Exception {
  const StepImportException(this.report);
  final ImportReport report;

  @override
  String toString() => 'StepImportException: '
      '${report.diagnostics.where((d) => d.severity == ImportSeverity.error).length} '
      'error(s); ${report.diagnostics.where((d) => d.severity == ImportSeverity.error).first}';
}
