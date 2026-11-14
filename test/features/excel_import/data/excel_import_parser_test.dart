import 'dart:io';
import 'dart:typed_data';

import 'package:aula_presente/features/excel_import/data/excel_import_parser.dart';
import 'package:aula_presente/features/excel_import/domain/excel_import_document.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

final _parser = ExcelImportParser();

Future<Uint8List> _fixture(String name) =>
    File('test/fixtures/excel_import/$name').readAsBytes();

Uint8List _workbook(List<String> headers) {
  final excel = Excel.createExcel();
  excel['Sheet1'].appendRow(headers.map(TextCellValue.new).toList());
  excel['Sheet1'].appendRow([
    TextCellValue('0000000123'),
    TextCellValue('alumno@example.invalid'),
    TextCellValue('Persona Ficticia'),
  ]);
  return Uint8List.fromList(excel.save()!);
}

void main() {
  test('BIFF8 auténtico lee 35 filas y códigos numéricos sin .0', () async {
    final bytes = await _fixture('estudiantes_ficticios_35.xls');
    expect(bytes.sublist(0, 8), [
      0xD0,
      0xCF,
      0x11,
      0xE0,
      0xA1,
      0xB1,
      0x1A,
      0xE1,
    ]);
    final document = await _parser.parseBytes(
      fileName: 'estudiantes_ficticios_35.xls',
      bytes: bytes,
    );
    expect(document.sheets, hasLength(1));
    final sheet = document.sheets.single;
    expect(sheet.rows, hasLength(35));
    expect(sheet.rows.first.rowNumber, 2);
    expect(sheet.rows.last.rowNumber, 36);
    expect(sheet.rows.first.studentCode, '2000000001');
    expect(sheet.rows.first.email, 'alumno01@example.invalid');
    expect(sheet.rows.every((row) => row.isValid), isTrue);
    expect(sheet.columnMapping, {
      'studentCode': 'CODIGOESTUDIANTE',
      'email': 'MAIL_INST',
      'name': 'NOMBRECOMPLETO',
    });
    expect(sheet.columnMapping.keys, ['studentCode', 'email', 'name']);
    expect(sheet.rows.first.name, 'Estudiante Ficticio 01');
  });

  test('OOXML auténtico conserva ceros y separa hojas compatibles', () async {
    final bytes = await _fixture('estudiantes_ficticios_mixtos.xlsx');
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    final document = await _parser.parseBytes(
      fileName: 'estudiantes_ficticios_mixtos.xlsx',
      bytes: bytes,
    );
    expect(document.sheets, hasLength(2));
    final first = document.sheets.first;
    expect(first.columnMapping['studentCode'], 'CODIGOESTUDIANTE');
    expect(first.rows.map((row) => row.rowNumber), [2, 3, 4, 6]);
    expect(first.rows[0].studentCode, '0000000123');
    expect(first.rows[1].studentCode, '0000001234');
    expect(first.rows[2].studentCode, '2000000003');
    expect(first.rows[3].isValid, isFalse);
    expect(first.rows[3].validationError, contains('correo'));
    expect(document.sheets.last.rows, hasLength(1));
  });

  test('rechaza extensión falsa, vacío y bytes corruptos', () async {
    final xlsx = await _fixture('estudiantes_ficticios_mixtos.xlsx');
    await expectLater(
      _parser.parseBytes(fileName: 'renombrado.xls', bytes: xlsx),
      throwsA(isA<ExcelImportException>()),
    );
    await expectLater(
      _parser.parseBytes(fileName: 'vacio.xlsx', bytes: Uint8List(0)),
      throwsA(isA<ExcelImportException>()),
    );
    await expectLater(
      _parser.parseBytes(
        fileName: 'corrupto.xlsx',
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0]),
      ),
      throwsA(isA<ExcelImportException>()),
    );
  });

  test('identifica columnas obligatorias ausentes y repetidas', () async {
    final missing = _workbook(['CODIGOESTUDIANTE', 'MAIL_INST', 'OTRA']);
    await expectLater(
      _parser.parseBytes(fileName: 'faltante.xlsx', bytes: missing),
      throwsA(
        isA<ExcelImportException>().having(
          (error) => error.message,
          'message',
          contains('NOMBRECOMPLETO'),
        ),
      ),
    );
    final duplicate = _workbook([
      'CODIGOESTUDIANTE',
      'CODIGO ESTUDIANTE',
      'MAIL_INST',
      'NOMBRECOMPLETO',
    ]);
    await expectLater(
      _parser.parseBytes(fileName: 'duplicado.xlsx', bytes: duplicate),
      throwsA(
        isA<ExcelImportException>().having(
          (error) => error.message,
          'message',
          contains('repetida'),
        ),
      ),
    );
  });

  test('informa hojas incompatibles aunque exista una hoja válida', () async {
    final excel = Excel.createExcel();
    excel['Sheet1'].appendRow([
      TextCellValue('CODIGOESTUDIANTE'),
      TextCellValue('MAIL_INST'),
      TextCellValue('NOMBRECOMPLETO'),
    ]);
    excel['Sheet1'].appendRow([
      TextCellValue('0000000123'),
      TextCellValue('alumno@example.invalid'),
      TextCellValue('Persona Ficticia'),
    ]);
    excel['Sin nombre'].appendRow([
      TextCellValue('CODIGOESTUDIANTE'),
      TextCellValue('MAIL_INST'),
    ]);
    excel['Duplicada'].appendRow([
      TextCellValue('CODIGOESTUDIANTE'),
      TextCellValue('CODIGO ESTUDIANTE'),
      TextCellValue('MAIL_INST'),
      TextCellValue('NOMBRECOMPLETO'),
    ]);
    final bytes = Uint8List.fromList(excel.save()!);
    final document = await _parser.parseBytes(
      fileName: 'hojas-mixtas.xlsx',
      bytes: bytes,
    );
    expect(document.sheets.map((sheet) => sheet.name), ['Sheet1']);
    expect(document.warnings, hasLength(2));
    expect(document.warnings[0], contains('Sin nombre: faltan NOMBRECOMPLETO'));
    expect(
      document.warnings[1],
      contains('Duplicada: la columna CODIGOESTUDIANTE aparece repetida'),
    );
  });

  test('acepta alias y acentos sin mezclar columnas', () async {
    final bytes = _workbook([
      ' CÓDIGO ESTUDIANTE ',
      ' Correo Institucional ',
      ' Nombre Estudiante ',
    ]);
    final document = await _parser.parseBytes(
      fileName: 'alias.xlsx',
      bytes: bytes,
    );
    expect(document.sheets.single.rows.single.studentCode, '0000000123');
    expect(
      document.sheets.single.columnMapping['studentCode'],
      'CÓDIGO ESTUDIANTE',
    );
  });

  test('hoja sin encabezado compatible no crea filas', () async {
    final excel = Excel.createExcel();
    final bytes = Uint8List.fromList(excel.save()!);
    await expectLater(
      _parser.parseBytes(fileName: 'sin-datos.xlsx', bytes: bytes),
      throwsA(isA<ExcelImportException>()),
    );
  });
}
