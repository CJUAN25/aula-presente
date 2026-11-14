import 'dart:async';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:aula_presente/features/excel_import/domain/excel_import_document.dart';
import 'package:aula_presente/features/excel_import/presentation/excel_import_screen.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Course _course() => Course(
  id: 'course-1',
  ownerUid: 'teacher-1',
  subject: 'Materia de prueba',
  group: '01',
  period: '2026-2',
  program: 'Programa',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 2),
    endDate: AcademicDate(year: 2026, month: 11, day: 9),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'block-1',
        weekday: 1,
        startTime: '08:00',
        endTime: '09:00',
      ),
    ],
  ),
);

const _candidate = StudentCandidate(
  uid: 'student-1',
  name: 'Cuenta ficticia',
  email: 'student@example.invalid',
  studentCode: '1234567890',
);

const _secondCandidate = StudentCandidate(
  uid: 'student-2',
  name: 'Segunda cuenta ficticia',
  email: 'missing@example.invalid',
  studentCode: '0000000002',
);

ExcelImportDocument _document() => const ExcelImportDocument(
  fileName: 'lista-ficticia.xls',
  sheets: [
    ExcelImportSheet(
      name: 'Curso de prueba',
      columnMapping: {
        'studentCode': 'CODIGOESTUDIANTE',
        'email': 'MAIL_INST',
        'name': 'NOMBRECOMPLETO',
      },
      rows: [
        ExcelImportRow(
          rowNumber: 2,
          studentCode: '1234567890',
          email: 'student@example.invalid',
          name: 'Nombre del archivo',
        ),
        ExcelImportRow(
          rowNumber: 3,
          studentCode: '0000000002',
          email: 'missing@example.invalid',
          name: 'Cuenta sin directorio',
        ),
      ],
    ),
  ],
);

class _Reader implements ExcelImportReader {
  _Reader(this.document, [this.error]);
  final ExcelImportDocument? document;
  final Object? error;
  @override
  Future<ExcelImportDocument?> pickAndRead() async {
    if (error != null) throw error!;
    return document;
  }
}

class _Repository implements EnrollmentRepository {
  String? uid = 'teacher-1';
  int writes = 0;
  bool firstCandidateAvailable = true;
  bool secondCandidateAvailable = false;
  bool failSecondWrite = false;
  Completer<EnrollmentResult>? pendingWrite;

  @override
  String? get currentUid => uid;

  @override
  Future<int> countCourseStudents(String courseId) async => writes;

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async {
    if (email == _candidate.email && firstCandidateAvailable) return _candidate;
    if (email == _secondCandidate.email && secondCandidateAvailable) {
      return _secondCandidate;
    }
    return null;
  }

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async =>
      throw const EnrollmentFailure(EnrollmentFailureKind.courseUnavailable);

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    bool resolvePendingWhenAlreadyEnrolled = true,
  }) async {
    writes++;
    if (candidate.uid == _secondCandidate.uid && failSecondWrite) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    final pending = pendingWrite;
    if (pending != null) return pending.future;
    return EnrollmentResult(
      enrollment: Enrollment(
        courseId: courseId,
        studentUid: candidate.uid,
        ownerUid: 'teacher-1',
        name: candidate.name,
        email: candidate.email,
        studentCode: candidate.studentCode,
        subject: 'Materia de prueba',
        group: '01',
        period: '2026-2',
        status: 'active',
        createdAt: null,
      ),
      alreadyEnrolled: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required _Repository repository,
  ExcelImportDocument? document,
  Object? readerError,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: ExcelImportScreen(
          course: _course(),
          repository: repository,
          reader: _Reader(document, readerError),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'seleccionar y revisar no escribe; solo confirma la fila elegida',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository: repository, document: _document());
      await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
      await tester.tap(find.text('Seleccionar Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Reconocimos tu archivo.'), findsOneWidget);
      expect(find.text('CODIGOESTUDIANTE'), findsOneWidget);
      expect(repository.writes, 0);

      await tester.tap(find.text('Revisar coincidencias'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Cuenta no disponible'),
        200,
      );
      expect(find.textContaining('Cuenta no disponible'), findsOneWidget);
      expect(repository.writes, 0);

      await tester.tap(find.text('Seleccionar estudiantes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seleccionar todas las elegibles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desmarcar todas'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      await tester.tap(find.text('Seleccionar todas las elegibles'));
      await tester.pumpAndSettle();
      expect(find.text('Revisar selección'), findsOneWidget);
      await tester.tap(find.text('Revisar selección'));
      await tester.pumpAndSettle();
      expect(repository.writes, 0);
      expect(find.text('Al confirmar'), findsOneWidget);

      await tester.tap(find.text('Confirmar inscripciones'));
      await tester.pumpAndSettle();
      expect(repository.writes, 1);
      expect(find.text('Matriculadas ahora'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Filas sin escritura'), 200);
      expect(find.text('Filas sin escritura'), findsOneWidget);
    },
  );

  testWidgets('cancelar el selector y doble toque no crean altas duplicadas', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository: repository);
    await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
    await tester.tap(find.text('Seleccionar Excel'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar Excel'), findsOneWidget);
    expect(repository.writes, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, repository: repository, document: _document());
    await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
    await tester.tap(find.text('Seleccionar Excel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar coincidencias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar estudiantes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar todas las elegibles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar selección'));
    await tester.pumpAndSettle();
    repository.pendingWrite = Completer<EnrollmentResult>();
    await tester.tap(find.text('Confirmar inscripciones'));
    await tester.pump();
    expect(repository.writes, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    repository.pendingWrite!.complete(
      EnrollmentResult(
        enrollment: Enrollment(
          courseId: 'course-1',
          studentUid: _candidate.uid,
          ownerUid: 'teacher-1',
          name: _candidate.name,
          email: _candidate.email,
          studentCode: _candidate.studentCode,
          subject: 'Materia de prueba',
          group: '01',
          period: '2026-2',
          status: 'active',
          createdAt: null,
        ),
        alreadyEnrolled: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.writes, 1);
  });

  testWidgets(
    'hoja vacía y hojas omitidas explican por qué no se puede revisar',
    (tester) async {
      const document = ExcelImportDocument(
        fileName: 'vacio.xlsx',
        warnings: ['Hoja antigua: falta NOMBRECOMPLETO'],
        sheets: [
          ExcelImportSheet(
            name: 'Solo encabezados',
            columnMapping: {
              'studentCode': 'CODIGOESTUDIANTE',
              'email': 'MAIL_INST',
              'name': 'NOMBRECOMPLETO',
            },
            rows: [],
          ),
        ],
      );
      final repository = _Repository();
      await _pump(tester, repository: repository, document: document);
      await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
      await tester.tap(find.text('Seleccionar Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Hoja omitida'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Hoja sin estudiantes'), 200);
      expect(find.text('Hoja sin estudiantes'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      expect(repository.writes, 0);
    },
  );

  testWidgets('archivo ilegible y lista sin altas tienen mensajes útiles', (
    tester,
  ) async {
    final repository = _Repository()..firstCandidateAvailable = false;
    await _pump(
      tester,
      repository: repository,
      readerError: const ExcelImportException('Archivo ilegible de prueba.'),
    );
    await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
    await tester.tap(find.text('Seleccionar Excel'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Archivo ilegible de prueba.'),
      200,
    );
    expect(find.text('Archivo ilegible de prueba.'), findsOneWidget);
    expect(repository.writes, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, repository: repository, document: _document());
    await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
    await tester.tap(find.text('Seleccionar Excel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar coincidencias'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    expect(repository.writes, 0);
  });

  testWidgets('resultado parcial separa la alta confirmada de la fallida', (
    tester,
  ) async {
    final repository = _Repository()
      ..secondCandidateAvailable = true
      ..failSecondWrite = true;
    await _pump(tester, repository: repository, document: _document());
    await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
    await tester.tap(find.text('Seleccionar Excel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar coincidencias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar estudiantes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar todas las elegibles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar selección'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar inscripciones'));
    await tester.pumpAndSettle();
    expect(repository.writes, 2);
    expect(find.text('Matriculadas ahora'), findsOneWidget);
    expect(find.text('Sin confirmar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('recorrido se adapta a $width px y texto 1.6', (tester) async {
      await _pump(
        tester,
        repository: _Repository(),
        document: _document(),
        width: width,
      );
      expect(find.text('Carga la lista del curso.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Seleccionar Excel'), 200);
      await tester.tap(find.text('Seleccionar Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar coincidencias'));
      await tester.pumpAndSettle();
      expect(find.text('Comprueba tu lista.'), findsOneWidget);
      await tester.tap(find.text('Seleccionar estudiantes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seleccionar todas las elegibles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar selección'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar inscripciones'));
      await tester.pumpAndSettle();
      expect(find.text('Matriculadas ahora'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
