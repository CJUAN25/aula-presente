import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../domain/excel_import_document.dart';

/// Reads only identity columns from a genuine BIFF8 or OOXML workbook.
class ExcelImportParser {
  const ExcelImportParser();

  static const maxFileBytes = 5 * 1024 * 1024;
  static const maxRowsPerSheet = 1000;
  static const maxSheets = 10;
  static const maxColumns = 60;

  Future<ExcelImportDocument> parseBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final extension = fileName.toLowerCase();
    final isXls = extension.endsWith('.xls');
    final isXlsx = extension.endsWith('.xlsx');
    if (!isXls && !isXlsx) {
      throw const ExcelImportException('Elige un archivo Excel .xls o .xlsx.');
    }
    if (bytes.isEmpty) {
      throw const ExcelImportException('El archivo está vacío.');
    }
    if (bytes.length > maxFileBytes) {
      throw const ExcelImportException(
        'El archivo supera el límite de 5 MB. Usa una lista más pequeña.',
      );
    }
    const xlsMagic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    final looksXls =
        bytes.length >= xlsMagic.length &&
        List.generate(
          xlsMagic.length,
          (i) => bytes[i] == xlsMagic[i],
        ).every((matches) => matches);
    final looksXlsx =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if ((isXls && !looksXls) || (isXlsx && !looksXlsx)) {
      throw const ExcelImportException(
        'La extensión no coincide con el formato real del archivo Excel.',
      );
    }

    try {
      final workbook = await Excel.decodeBytesAsync(bytes);
      if (workbook.tables.isEmpty) {
        throw const ExcelImportException('El libro no contiene hojas.');
      }
      if (workbook.tables.length > maxSheets) {
        throw const ExcelImportException(
          'El libro tiene demasiadas hojas (máximo 10).',
        );
      }
      final sheets = <ExcelImportSheet>[];
      final rejected = <String>[];
      for (final entry in workbook.tables.entries) {
        final sheet = entry.value;
        if (sheet.maxRows > maxRowsPerSheet + 20 ||
            sheet.maxColumns > maxColumns) {
          throw const ExcelImportException(
            'La hoja supera el límite de 1000 filas o 60 columnas.',
          );
        }
        final parsed = _parseSheet(entry.key, sheet);
        if (parsed.sheet != null) {
          sheets.add(parsed.sheet!);
        } else if (parsed.error != 'hoja vacía.') {
          rejected.add('${entry.key}: ${parsed.error}');
        }
      }
      if (sheets.isEmpty) {
        if (rejected.isEmpty) {
          throw const ExcelImportException(
            'El libro no contiene filas ni encabezados en ninguna hoja.',
          );
        }
        throw ExcelImportException(
          'Ninguna hoja contiene las tres columnas necesarias. ${rejected.join(' ')}',
        );
      }
      return ExcelImportDocument(
        fileName: fileName,
        sheets: sheets,
        warnings: rejected,
      );
    } on ExcelImportException {
      rethrow;
    } catch (_) {
      throw const ExcelImportException(
        'No se pudo leer el Excel. Comprueba que no esté dañado o protegido.',
      );
    }
  }

  ({ExcelImportSheet? sheet, String? error}) _parseSheet(
    String name,
    Sheet sheet,
  ) {
    if (sheet.maxRows == 0) return (sheet: null, error: 'hoja vacía.');
    final values = sheet.rows;
    final headerIndex = values.indexWhere(
      (row) => row.any((cell) => _cellText(cell).trim().isNotEmpty),
    );
    if (headerIndex < 0) return (sheet: null, error: 'hoja vacía.');
    final headers = values[headerIndex];
    final positions = <String, int>{};
    final names = <String, String>{};
    for (var i = 0; i < headers.length; i++) {
      final label = _cellText(headers[i]).trim();
      final key = _headerKey(label);
      if (key == null) continue;
      if (positions.containsKey(key)) {
        return (sheet: null, error: 'la columna $key aparece repetida.');
      }
      positions[key] = i;
      names[key] = label;
    }
    const requiredKeys = ['CODIGOESTUDIANTE', 'MAIL_INST', 'NOMBRECOMPLETO'];
    final missing = requiredKeys.where((key) => !positions.containsKey(key));
    if (missing.isNotEmpty) {
      return (sheet: null, error: 'faltan ${missing.join(', ')}.');
    }
    final rows = <ExcelImportRow>[];
    for (var i = headerIndex + 1; i < values.length; i++) {
      final row = values[i];
      if (row.every((cell) => _cellText(cell).trim().isEmpty)) {
        continue;
      }
      if (rows.length >= maxRowsPerSheet) {
        throw const ExcelImportException(
          'La hoja supera el límite de 1000 filas con datos.',
        );
      }
      final code = _studentCode(row[positions['CODIGOESTUDIANTE']!]);
      final email = _text(row[positions['MAIL_INST']!]);
      final studentName = _text(row[positions['NOMBRECOMPLETO']!]);
      final errors = <String>[];
      if (code.error != null) errors.add(code.error!);
      if (code.value.isEmpty && code.error == null) {
        errors.add('Falta el código estudiantil.');
      }
      if (email.isEmpty) errors.add('Falta el correo.');
      if (studentName.isEmpty) errors.add('Falta el nombre.');
      if (code.value.length > 40 ||
          email.length > 254 ||
          studentName.length > 100) {
        errors.add('Una celda obligatoria supera el límite permitido.');
      }
      rows.add(
        ExcelImportRow(
          rowNumber: i + 1,
          studentCode: code.value,
          email: email,
          name: studentName,
          validationError: errors.isEmpty ? null : errors.join(' '),
        ),
      );
    }
    return (
      sheet: ExcelImportSheet(
        name: name,
        columnMapping: {
          'studentCode': names['CODIGOESTUDIANTE']!,
          'email': names['MAIL_INST']!,
          'name': names['NOMBRECOMPLETO']!,
        },
        rows: rows,
      ),
      error: null,
    );
  }

  String? _headerKey(String header) {
    final normalized = header
        .toUpperCase()
        .trim()
        .replaceAll(RegExp('[ÁÀÂÄ]'), 'A')
        .replaceAll(RegExp('[ÉÈÊË]'), 'E')
        .replaceAll(RegExp('[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp('[ÓÒÔÖ]'), 'O')
        .replaceAll(RegExp('[ÚÙÛÜ]'), 'U')
        .replaceAll(RegExp(r'[\s_\-]+'), '');
    return switch (normalized) {
      'CODIGOESTUDIANTE' || 'CODIGOALUMNO' => 'CODIGOESTUDIANTE',
      'MAILINST' ||
      'CORREOINSTITUCIONAL' ||
      'EMAILINSTITUCIONAL' => 'MAIL_INST',
      'NOMBRECOMPLETO' || 'NOMBREESTUDIANTE' => 'NOMBRECOMPLETO',
      _ => null,
    };
  }

  String _text(Data? cell) => switch (cell?.value) {
    TextCellValue(:final value) => value.toString().trim(),
    _ => '',
  };

  String _cellText(Data? cell) => switch (cell?.value) {
    TextCellValue(:final value) => value.toString(),
    _ => cell?.displayText ?? '',
  };

  ({String value, String? error}) _studentCode(Data? cell) {
    final value = cell?.value;
    if (value == null) return (value: '', error: null);
    if (value is TextCellValue) {
      return (value: value.value.toString().trim(), error: null);
    }
    final number = switch (value) {
      IntCellValue(:final value) => value.toDouble(),
      DoubleCellValue(:final value) => value,
      _ => null,
    };
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        number > 9007199254740991 ||
        number != number.truncateToDouble()) {
      return (value: '', error: 'El código numérico no es un entero exacto.');
    }
    var digits = number.toInt().toString();
    final format = cell?.cellStyle?.numberFormat.formatCode ?? '';
    if (RegExp(r'^0{2,40}$').hasMatch(format)) {
      digits = digits.padLeft(format.length, '0');
    }
    return (value: digits, error: null);
  }
}
