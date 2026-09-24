import '../import_report.dart';
import 'step_records.dart';
import 'tahot_parser.dart';

/// Source-native N reading; edition displacement annotations do not define it.
List<StepRecord> selectTagntN(
    List<StepRecord> records, List<ImportDiagnostic> diagnostics) {
  final selected = <StepRecord>[];
  for (final row in records) {
    if (!row.wordType.toUpperCase().startsWith('N')) continue;
    if (RegExp(r'NA27[«»]').hasMatch(row.fields[5])) {
      diagnostics.add(row.diagnostic(
          'edition_order_annotation',
          'N retains TAGNT row order. NA27 edition displacement metadata '
              '(${row.fields[5]}) is not applied; this is not an exact NA27 reproduction.',
          field: 'editions',
          severity: ImportSeverity.warning));
    }
    selected.add(row);
  }
  return selected;
}

/// Main Leningrad/Qere rows plus explicit restorations; no retroverted LXX.
List<StepRecord> selectTahotLqr(
    List<StepRecord> records, List<ImportDiagnostic> diagnostics) {
  final selected = <StepRecord>[];
  for (final row in records) {
    if (!RegExp(r'^[LQR]').hasMatch(row.wordType)) continue;
    if (isQereOmission(row)) {
      diagnostics.add(row.diagnostic('qere_omission',
          'The source explicitly omits this ketiv word in its qere reading.',
          severity: ImportSeverity.info));
      continue;
    }
    selected.add(row);
  }
  return selected;
}
