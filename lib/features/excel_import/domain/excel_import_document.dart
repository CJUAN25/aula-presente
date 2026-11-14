/// Data read locally from one workbook. Only the three fields needed to match
/// a student leave the reader; other spreadsheet columns are never retained.
class ExcelImportDocument {
  const ExcelImportDocument({
    required this.fileName,
    required this.sheets,
    this.warnings = const [],
  });

  final String fileName;
  final List<ExcelImportSheet> sheets;

  /// Reasons why nonempty incompatible sheets were excluded from selection.
  final List<String> warnings;
}

class ExcelImportSheet {
  const ExcelImportSheet({
    required this.name,
    required this.columnMapping,
    required this.rows,
  });

  final String name;

  /// Keys: studentCode, email and name. Values are source headers.
  final Map<String, String> columnMapping;
  final List<ExcelImportRow> rows;
}

class ExcelImportRow {
  const ExcelImportRow({
    required this.rowNumber,
    required this.studentCode,
    required this.email,
    required this.name,
    this.validationError,
  });

  /// One-based position in the source worksheet, including its header row.
  final int rowNumber;
  final String studentCode;
  final String email;
  final String name;
  final String? validationError;

  bool get isValid => validationError == null;
}

abstract interface class ExcelImportReader {
  /// Returns null only when the system picker is canceled.
  Future<ExcelImportDocument?> pickAndRead();
}

class ExcelImportException implements Exception {
  const ExcelImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
