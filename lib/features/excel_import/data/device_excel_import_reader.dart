import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/excel_import_document.dart';
import 'excel_import_parser.dart';

/// Uses Android's document picker; reads only the selected file into memory.
class DeviceExcelImportReader implements ExcelImportReader {
  const DeviceExcelImportReader({this._parser = const ExcelImportParser()});

  final ExcelImportParser _parser;

  @override
  Future<ExcelImportDocument?> pickAndRead() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['xls', 'xlsx'],
      );
      if (file == null) return null;
      final reportedLength = file.lengthSync() ?? await file.length();
      if (reportedLength != null &&
          reportedLength > ExcelImportParser.maxFileBytes) {
        throw const ExcelImportException(
          'El archivo supera el límite de 5 MB. Usa una lista más pequeña.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in file.readAsByteStream()) {
        size += chunk.length;
        if (size > ExcelImportParser.maxFileBytes) {
          throw const ExcelImportException(
            'El archivo supera el límite de 5 MB. Usa una lista más pequeña.',
          );
        }
        bytes.add(chunk);
      }
      return await _parser.parseBytes(
        fileName: file.name,
        bytes: bytes.toBytes(),
      );
    } on ExcelImportException {
      rethrow;
    } catch (_) {
      throw const ExcelImportException(
        'No se pudo abrir el archivo seleccionado. Inténtalo de nuevo.',
      );
    }
  }
}
