import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_result.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:aula_presente/features/excel_import/domain/excel_import_document.dart';
import 'package:aula_presente/features/excel_import/presentation/excel_roster_update_screen.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AcademicDate _todayBogota() => AcademicDate.fromDateTime(
  DateTime.now().toUtc().subtract(const Duration(hours: 5)),
);

AcademicDate _futureStartDate() => _todayBogota().addDays(21);

Course _course() => Course(
  id: 'course-c7-test',
  ownerUid: 'teacher-test',
  subject: 'Materia ficticia',
  group: '07',
  period: '2026-2',
  program: 'Programa ficticio',
  schedule: CourseSchedule(
    startDate: _futureStartDate(),
    endDate: _futureStartDate().addDays(30),
    weeklyBlocks: const [],
  ),
);

const _newStudent = StudentCandidate(
  uid: 'student-new-test',
  name: 'Estudiante nuevo ficticio',
  email: 'nuevo@example.invalid',
  studentCode: '00070001',
);

ExcelImportDocument _document() => const ExcelImportDocument(
  fileName: 'lista_ficticia_c7.xlsx',
  sheets: [
    ExcelImportSheet(
      name: 'Materia ficticia',
      columnMapping: {
        'studentCode': 'CODIGOESTUDIANTE',
        'email': 'MAIL_INST',
        'name': 'NOMBRECOMPLETO',
      },
      rows: [
        ExcelImportRow(
          rowNumber: 2,
          studentCode: '00070001',
          email: 'nuevo@example.invalid',
          name: 'Estudiante nuevo ficticio',
        ),
      ],
    ),
  ],
);

PendingEnrollment _pending(String email, String name, String code) {
  final now = DateTime.utc(2026, 11, 1);
  return PendingEnrollment(
    courseId: 'course-c7-test',
    ownerUid: 'teacher-test',
    subject: 'Materia ficticia',
    group: '07',
    period: '2026-2',
    email: email,
    studentCode: code,
    name: name,
    status: 'pending',
    effectiveStartDate: _futureStartDate(),
    rosterEntryId: email,
    studentUid: null,
    authorizedAt: now,
    linkedAt: null,
    createdAt: now,
    updatedAt: now,
    lastEventId: null,
    lastStatusChangedAt: null,
  );
}

class _Reader implements ExcelImportReader {
  @override
  Future<ExcelImportDocument?> pickAndRead() async => _document();
}

class _Repository implements EnrollmentRepository {
  _Repository() {
    pending = [
      _pending(
        'pendiente-a@example.invalid',
        'Pendiente A ficticio',
        '00070002',
      ),
      _pending(
        'pendiente-b@example.invalid',
        'Pendiente B ficticio',
        '00070003',
      ),
    ];
  }

  String? uid = 'teacher-test';
  late final List<PendingEnrollment> pending;
  final startDates = <AcademicDate>[];
  final withdrawalDates = <AcademicDate>[];
  int snapshotReads = 0;
  int directWrites = 0;
  int pendingStatusWrites = 0;
  int eventIds = 0;

  int get writes => directWrites + pendingStatusWrites;

  @override
  String? get currentUid => uid;

  @override
  Future<int> countCourseStudents(String courseId) async => 0;

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async =>
      email == _newStudent.email ? _newStudent : null;

  @override
  Future<CourseRosterSnapshot> loadCourseRosterSnapshot({
    required String courseId,
  }) async {
    snapshotReads++;
    return CourseRosterSnapshot(
      activeEnrollments: const [],
      withdrawnEnrollments: const [],
      pendingEnrollments: pending,
      withdrawnPendingEnrollments: const [],
      complete: true,
    );
  }

  @override
  Future<List<Enrollment>> findCourseEnrollmentsByEmail({
    required String courseId,
    required String email,
  }) async => const [];

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    AcademicDate? effectiveStartDate,
    bool resolvePendingWhenAlreadyEnrolled = true,
  }) async {
    directWrites++;
    startDates.add(effectiveStartDate!);
    return EnrollmentResult(
      enrollment: Enrollment(
        courseId: courseId,
        studentUid: candidate.uid,
        ownerUid: 'teacher-test',
        name: candidate.name,
        email: candidate.email,
        studentCode: candidate.studentCode,
        subject: 'Materia ficticia',
        group: '07',
        period: '2026-2',
        status: 'active',
        createdAt: null,
        rosterEntryId: candidate.email,
        effectiveStartDate: effectiveStartDate,
      ),
      alreadyEnrolled: false,
    );
  }

  @override
  String newStatusEventId({
    required String courseId,
    required String studentUid,
  }) => 'enrollment-event-${++eventIds}';

  @override
  String newPendingStatusEventId({
    required String courseId,
    required String email,
  }) => 'pending-event-${++eventIds}';

  @override
  Future<PendingEnrollmentStatusChangeResult> changePendingEnrollmentStatus({
    required PendingEnrollment expected,
    required String nextStatus,
    required String operationId,
    required AcademicDate effectiveDate,
  }) async {
    pendingStatusWrites++;
    withdrawalDates.add(effectiveDate);
    return PendingEnrollmentStatusChangeResult(
      status: nextStatus,
      operationId: operationId,
      alreadyApplied: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required _Repository repository,
  required double width,
  double textScale = 1.6,
}) async {
  tester.view.physicalSize = Size(width * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ExcelRosterUpdateScreen(
        course: _course(),
        repository: repository,
        reader: _Reader(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCompleteListReview(WidgetTester tester) async {
  await _tapVisible(tester, find.text('Comparar lista completa'));
  await _tapVisible(
    tester,
    find.text('Seleccionar Excel'),
    scrollOffset: const Offset(0, 300),
  );
  await tester.pumpAndSettle();
  expect(find.text('Reconocimos tu archivo.'), findsOneWidget);
  await _tapVisible(tester, find.text('Revisar cambios'));
  expect(find.text('Revisa qué cambió.'), findsOneWidget);
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder finder, {
  Offset scrollOffset = const Offset(0, -300),
}) async {
  await _bringVisible(tester, finder, scrollOffset: scrollOffset);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _bringVisible(
  WidgetTester tester,
  Finder finder, {
  Offset scrollOffset = const Offset(0, -300),
}) async {
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).first, scrollOffset);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _withdrawalCheckbox(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Checkbox &&
      widget.semanticLabel == 'Seleccionar retiro de $name',
);

Future<void> _openWithdrawals(WidgetTester tester) async {
  await _tapVisible(tester, find.text('Seleccionar cambios'));
  expect(find.text('Selecciona las altas.'), findsOneWidget);
  final addCheckbox = find.byWidgetPredicate(
    (widget) =>
        widget is Checkbox && widget.semanticLabel == 'Seleccionar fila 2',
  );
  await _bringVisible(tester, addCheckbox);
  expect(tester.widget<Checkbox>(addCheckbox).value, isFalse);
  await _tapVisible(tester, addCheckbox);
  expect(tester.widget<Checkbox>(addCheckbox).value, isTrue);
  await _tapVisible(tester, find.text('Revisar posibles retiros'));
  expect(find.text('Elige quién se retira.'), findsOneWidget);
}

void main() {
  testWidgets('revisar y seleccionar no escribe; retiros salen desmarcados', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository: repository, width: 390);
    expect(find.text('Carga la lista del curso.'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    await _openCompleteListReview(tester);

    expect(repository.snapshotReads, 1);
    expect(repository.writes, 0);
    expect(find.text('2'), findsWidgets);
    await _openWithdrawals(tester);

    for (final name in ['Pendiente A ficticio', 'Pendiente B ficticio']) {
      final checkbox = _withdrawalCheckbox(name);
      await _bringVisible(tester, checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    }
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'confirma un alta y un retiro parcial con fechas distintas en ${width.toInt()} px',
      (tester) async {
        final repository = _Repository();
        await _pump(tester, repository: repository, width: width);
        await _openCompleteListReview(tester);
        expect(repository.writes, 0);
        await _openWithdrawals(tester);

        final selectedWithdrawal = _withdrawalCheckbox('Pendiente A ficticio');
        await _bringVisible(tester, selectedWithdrawal);
        expect(tester.widget<Checkbox>(selectedWithdrawal).value, isFalse);
        await _tapVisible(tester, selectedWithdrawal);
        expect(tester.widget<Checkbox>(selectedWithdrawal).value, isTrue);
        await _tapVisible(tester, find.text('Revisar selección'));
        expect(find.text('Estos cambios se aplicarán.'), findsOneWidget);

        final startDate = _futureStartDate();
        final withdrawalDate = _todayBogota();
        expect(startDate, isNot(withdrawalDate));
        await _bringVisible(tester, find.text(startDate.isoDate));
        expect(find.text(startDate.isoDate), findsOneWidget);
        await _bringVisible(tester, find.text(withdrawalDate.isoDate));
        expect(find.text(withdrawalDate.isoDate), findsOneWidget);
        expect(repository.writes, 0);
        expect(tester.takeException(), isNull);

        await _tapVisible(tester, find.text('Confirmar cambios'));

        expect(repository.directWrites, 1);
        expect(repository.pendingStatusWrites, 1);
        expect(repository.startDates, [startDate]);
        expect(repository.withdrawalDates, [withdrawalDate]);
        expect(find.text('Tu selección se aplicó.'), findsOneWidget);
        await _bringVisible(
          tester,
          find.text('Se conservó; el retiro no estaba seleccionado.'),
        );
        expect(
          find.text('Se conservó; el retiro no estaba seleccionado.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
