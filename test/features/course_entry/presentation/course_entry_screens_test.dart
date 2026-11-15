import 'dart:async';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/course_entry/domain/course_entry_failure.dart';
import 'package:aula_presente/features/course_entry/domain/course_entry_repository.dart';
import 'package:aula_presente/features/course_entry/domain/course_invitation.dart';
import 'package:aula_presente/features/course_entry/domain/course_preview.dart';
import 'package:aula_presente/features/course_entry/domain/join_request.dart';
import 'package:aula_presente/features/course_entry/domain/join_request_page.dart';
import 'package:aula_presente/features/course_entry/presentation/course_invitation_screens.dart';
import 'package:aula_presente/features/course_entry/presentation/student_course_entry_screens.dart';
import 'package:aula_presente/features/course_entry/presentation/teacher_join_request_screens.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_status_change.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _createdAt = DateTime.utc(2026, 11, 7, 12);

Course _course() => Course(
  id: 'course-1',
  ownerUid: 'teacher-1',
  subject: 'Bases de Datos',
  group: 'G2',
  period: '2026-2',
  program: 'Ingeniería',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 2),
    endDate: AcademicDate(year: 2026, month: 11, day: 16),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'block-1',
        weekday: 1,
        startTime: '08:00',
        endTime: '10:00',
      ),
    ],
  ),
);

CourseInvitation _invitation({
  String status = 'active',
  String code = '2345ABCDE2345FGH',
  bool unconfirmedExpiry = false,
  Duration validity = CourseInvitation.defaultValidity,
}) => CourseInvitation(
  courseId: 'course-1',
  code: code,
  status: status,
  createdAt: unconfirmedExpiry ? null : _createdAt,
  updatedAt: unconfirmedExpiry ? null : _createdAt,
  validity: validity,
);

CoursePreview _preview() => CoursePreview(
  courseId: 'course-1',
  subject: 'Bases de Datos',
  group: 'G2',
  period: '2026-2',
  code: '2345ABCDE2345FGH',
  expiresAt: _createdAt.add(const Duration(days: 14)),
);

JoinRequest _request({
  JoinRequestStatus status = JoinRequestStatus.pending,
  String? rejectionReason,
}) => JoinRequest(
  courseId: 'course-1',
  studentUid: 'student-1',
  name: 'Estudiante de prueba',
  email: 'student@example.invalid',
  studentCode: '0007',
  subject: 'Bases de Datos',
  group: 'G2',
  period: '2026-2',
  status: status,
  createdAt: _createdAt,
  decidedBy: status == JoinRequestStatus.pending ? null : 'teacher-1',
  decidedAt: status == JoinRequestStatus.pending ? null : _createdAt,
  rejectionReason: rejectionReason,
);

Enrollment _enrollment({String status = 'active'}) => Enrollment(
  courseId: 'course-1',
  studentUid: 'student-1',
  ownerUid: 'teacher-1',
  name: 'Estudiante de prueba',
  email: 'student@example.invalid',
  studentCode: '0007',
  subject: 'Bases de Datos',
  group: 'G2',
  period: '2026-2',
  status: status,
  createdAt: _createdAt,
);

class _EntryRepository implements CourseEntryRepository {
  String? uid = 'teacher-1';
  CourseInvitation? invitation;
  CoursePreview preview = _preview();
  JoinRequest request = _request();
  JoinRequestResultKind submitKind = JoinRequestResultKind.created;
  JoinDecisionResultStatus decisionStatus = JoinDecisionResultStatus.approved;
  Completer<JoinRequestResult>? pendingSubmit;
  bool failNextCourseList = false;
  bool rejectApprovalForWithdrawnEnrollment = false;
  Object? lookupError;
  Object? renewError;
  int createCalls = 0;
  int renewCalls = 0;
  int deactivateCalls = 0;
  int lookupCalls = 0;
  int submitCalls = 0;
  int decisionCalls = 0;
  int courseListCalls = 0;
  Completer<CourseInvitation>? pendingRenew;

  @override
  String? get currentUid => uid;

  @override
  Future<CourseInvitation?> getCurrentInvitation(String courseId) async =>
      invitation;

  @override
  Future<CourseInvitation> createOrGetInvitation(
    String courseId, {
    Duration validity = CourseInvitation.defaultValidity,
  }) async {
    createCalls++;
    invitation = _invitation(validity: validity);
    return invitation!;
  }

  @override
  Future<CourseInvitation> renewInvitation(
    String courseId, {
    Duration validity = CourseInvitation.defaultValidity,
  }) async {
    renewCalls++;
    if (renewError != null) throw renewError!;
    if (pendingRenew != null) return pendingRenew!.future;
    invitation = _invitation(code: 'ABCDE2345FGHJKLM', validity: validity);
    return invitation!;
  }

  @override
  Future<CourseInvitation> updateInvitationValidity(
    String courseId,
    Duration validity,
  ) async {
    invitation = _invitation(
      code: invitation!.code,
      status: invitation!.status,
      validity: validity,
    );
    return invitation!;
  }

  @override
  Future<CourseInvitation> pauseInvitation(String courseId) async {
    invitation = _invitation(
      status: 'paused',
      code: invitation?.code ?? '2345ABCDE2345FGH',
      validity: invitation?.validity ?? CourseInvitation.defaultValidity,
    );
    return invitation!;
  }

  @override
  Future<CourseInvitation> reactivateInvitation(String courseId) async {
    invitation = _invitation(
      code: invitation?.code ?? '2345ABCDE2345FGH',
      validity: invitation?.validity ?? CourseInvitation.defaultValidity,
    );
    return invitation!;
  }

  @override
  Future<void> deactivateInvitation(String courseId) async {
    deactivateCalls++;
  }

  @override
  Future<CoursePreview> findCourseByCode(String input) async {
    lookupCalls++;
    if (lookupError != null) throw lookupError!;
    return preview;
  }

  @override
  Future<JoinRequestResult> requestJoin(String input) async {
    submitCalls++;
    final pending = pendingSubmit;
    if (pending != null) return pending.future;
    return JoinRequestResult(
      kind: submitKind,
      courseId: 'course-1',
      request:
          submitKind == JoinRequestResultKind.alreadyEnrolled ||
              submitKind == JoinRequestResultKind.alreadyWithdrawn
          ? null
          : request,
    );
  }

  @override
  Future<JoinRequest?> getMyRequest(String courseId) async => request;

  @override
  Future<JoinRequestPage> listMyRequests({
    JoinRequestCursor? cursor,
    int pageSize = 25,
  }) async => JoinRequestPage(items: [request], nextCursor: null);

  @override
  Future<JoinRequestPage> listCourseRequests(
    String courseId, {
    JoinRequestCursor? cursor,
    int pageSize = 25,
  }) async {
    courseListCalls++;
    if (failNextCourseList) {
      failNextCourseList = false;
      throw const CourseEntryFailure(CourseEntryFailureKind.network);
    }
    return JoinRequestPage(items: [request], nextCursor: null);
  }

  @override
  Future<JoinDecisionResult> decideJoinRequest({
    required String courseId,
    required String studentUid,
    required JoinRequestDecision decision,
    String? rejectionReason,
  }) async {
    decisionCalls++;
    if (decision == JoinRequestDecision.approve &&
        rejectApprovalForWithdrawnEnrollment) {
      throw const CourseEntryFailure(
        CourseEntryFailureKind.enrollmentWithdrawn,
      );
    }
    final status = decision == JoinRequestDecision.approve
        ? decisionStatus
        : rejectionReason == null
        ? JoinDecisionResultStatus.rejected
        : JoinDecisionResultStatus.rejected;
    final updated = _request(
      status:
          status == JoinDecisionResultStatus.rejected ||
              status == JoinDecisionResultStatus.alreadyRejected
          ? JoinRequestStatus.rejected
          : JoinRequestStatus.approved,
      rejectionReason: rejectionReason,
    );
    return JoinDecisionResult(
      status: status,
      courseId: courseId,
      request: updated,
      enrollment: status == JoinDecisionResultStatus.rejected
          ? null
          : _enrollment(),
    );
  }
}

class _EnrollmentRepository implements EnrollmentRepository {
  String? uid = 'student-1';
  final List<Enrollment> items = [];

  @override
  String? get currentUid => uid;

  @override
  Future<void> ensureStudentDirectoryEntry() async {}

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async => null;

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    AcademicDate? effectiveStartDate,
    bool resolvePendingWhenAlreadyEnrolled = true,
  }) async =>
      EnrollmentResult(enrollment: _enrollment(), alreadyEnrolled: false);

  @override
  Future<EnrollmentPage> listCourseStudents({
    required String courseId,
    String status = 'active',
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async => EnrollmentPage(items: const [], nextCursor: null);

  @override
  String newStatusEventId({
    required String courseId,
    required String studentUid,
  }) => 'status-event-1';

  @override
  Future<EnrollmentStatusChangeResult> changeEnrollmentStatus({
    required Enrollment expected,
    required String nextStatus,
    required String operationId,
    AcademicDate? effectiveDate,
  }) async =>
      EnrollmentStatusChangeResult(enrollment: expected, alreadyApplied: false);

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async => _enrollment();

  @override
  Future<EnrollmentHistoryPage> listEnrollmentHistory({
    required String courseId,
    required String studentUid,
    EnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  }) async => EnrollmentHistoryPage(items: const [], nextCursor: null);

  @override
  Future<EnrollmentPage> listMyCourses({
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async => EnrollmentPage(
    items: items.where((item) => item.status == 'active').toList(),
    nextCursor: null,
  );

  @override
  Future<int> countCourseStudents(String courseId) async => 0;

  @override
  Future<Course> getMyEnrolledCourse(String courseId) async => _course();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget screen, {double scale = 1}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: screen,
);

Future<void> _tapCourseAction(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'generation lets teacher choose a lifetime before its first write',
    (tester) async {
      final repository = _EntryRepository();
      await tester.pumpWidget(
        _app(CourseInvitationScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(repository.createCalls, 0);
      await tester.tap(find.text('Vigencia: 14 días'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 días después de generarlo'),
        findsOneWidget,
      );
      await tester.tap(find.text('Guardar vencimiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar código'));
      await tester.pumpAndSettle();
      expect(repository.createCalls, 1);
      expect(repository.invitation!.validity, const Duration(days: 3));
    },
  );

  testWidgets(
    'editing paused invitation previews the exact date and preserves its code',
    (tester) async {
      final repository = _EntryRepository()
        ..invitation = _invitation(status: 'paused');
      await tester.pumpWidget(
        _app(
          ManageCourseInvitationScreen(
            course: _course(),
            invitation: repository.invitation!,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapCourseAction(tester, 'Editar vencimiento');
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Guardar vencimiento'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Elige de 1 a 2160'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '30');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nuevo vencimiento: 07/12/2026'),
        findsOneWidget,
      );
      await tester.tap(find.text('Guardar vencimiento'));
      await tester.pumpAndSettle();
      expect(repository.invitation!.code, '2345ABCDE2345FGH');
      expect(repository.invitation!.status, 'paused');
      expect(repository.invitation!.validity, const Duration(days: 30));
      expect(find.text('Vencimiento actualizado.'), findsOneWidget);
    },
  );

  testWidgets(
    'active invitation shows code, copy, expiry and three actions without pause',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repository = _EntryRepository()..invitation = _invitation();
      await tester.pumpWidget(
        _app(
          ManageCourseInvitationScreen(
            course: _course(),
            invitation: repository.invitation!,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2345-ABCD-E234-5FGH'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.textContaining('Vence el 21/11/2026'), findsOneWidget);
      expect(find.text('Pausar código'), findsNothing);
      expect(find.text('Renovar código'), findsOneWidget);
      expect(find.text('Editar vencimiento'), findsOneWidget);
      expect(find.text('Desactivar código'), findsOneWidget);
      await _tapCourseAction(tester, 'Copiar código');
      expect(copied, '2345-ABCD-E234-5FGH');
    },
  );

  testWidgets('previously paused invitation can reactivate or renew', (
    tester,
  ) async {
    final repository = _EntryRepository()
      ..invitation = _invitation(status: 'paused');
    await tester.pumpWidget(
      _app(
        ManageCourseInvitationScreen(
          course: _course(),
          invitation: repository.invitation!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pausar código'), findsNothing);
    expect(find.text('Renovar código'), findsOneWidget);
    expect(find.text('Copiar código'), findsNothing);
    await _tapCourseAction(tester, 'Reactivar código');
    expect(repository.invitation!.status, 'paused');
    await tester.tap(find.text('Confirmar reactivación'));
    await tester.pumpAndSettle();
    expect(repository.invitation!.code, '2345ABCDE2345FGH');
    expect(find.text('Invitación reactivada.'), findsOneWidget);
  });

  testWidgets('permanently inactive code only offers replacement', (
    tester,
  ) async {
    final repository = _EntryRepository()
      ..invitation = _invitation(status: 'inactive');
    await tester.pumpWidget(
      _app(
        ManageCourseInvitationScreen(
          course: _course(),
          invitation: repository.invitation!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Editar vencimiento'), findsNothing);
    expect(find.text('Reactivar código'), findsNothing);
    expect(find.text('Pausar código'), findsNothing);
    await _tapCourseAction(tester, 'Renovar código');
    expect(find.text('Confirmar renovación'), findsOneWidget);
  });

  testWidgets('pending renewal disables repeated writes', (tester) async {
    final repository = _EntryRepository()
      ..invitation = _invitation()
      ..pendingRenew = Completer<CourseInvitation>();
    await tester.pumpWidget(
      _app(
        ManageCourseInvitationScreen(
          course: _course(),
          invitation: repository.invitation!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapCourseAction(tester, 'Renovar código');
    await tester.tap(find.text('Confirmar renovación'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.renewCalls, 1);
    final renewButton = tester.widget<FilledButton>(
      find.byType(FilledButton).first,
    );
    expect(renewButton.onPressed, isNull);
    repository.pendingRenew!.complete(_invitation(code: 'ABCDE2345FGHJKLM'));
    await tester.pumpAndSettle();
    expect(find.text('Invitación renovada.'), findsOneWidget);
    expect(find.text('ABCD-E234-5FGH-JKLM'), findsOneWidget);
  });

  testWidgets('denied renewal names the failed action and gives a next step', (
    tester,
  ) async {
    final repository = _EntryRepository()
      ..invitation = _invitation()
      ..renewError = const CourseEntryFailure(
        CourseEntryFailureKind.permissionDenied,
      );
    await tester.pumpWidget(
      _app(
        ManageCourseInvitationScreen(
          course: _course(),
          invitation: repository.invitation!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapCourseAction(tester, 'Renovar código');
    await tester.tap(find.text('Confirmar renovación'));
    await tester.pumpAndSettle();
    expect(repository.renewCalls, 1);
    expect(find.text('No se pudo renovar el código'), findsOneWidget);
    expect(find.textContaining('no tiene permiso'), findsOneWidget);
    expect(find.textContaining('Actualiza la pantalla'), findsOneWidget);
    expect(find.text('Invitación renovada.'), findsNothing);
  });

  testWidgets(
    'safe debug diagnosis displays stage and error without echoing invite or email',
    (tester) async {
      final repository = _EntryRepository()
        ..uid = 'student-1'
        ..lookupError = const CourseEntryFailure(
          CourseEntryFailureKind.inviteUnavailable,
          diagnosticStep: 'lookup-get',
          diagnosticCode: 'permission-denied',
        );
      await tester.pumpWidget(
        _app(
          StudentCourseCodeScreen(
            repository: repository,
            enrollmentRepository: _EnrollmentRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2345-ABCD-E234-5FGH');
      await tester.tap(find.text('Consultar curso'));
      await tester.pumpAndSettle();
      await _tapCourseAction(tester, 'Diagnóstico (debug)');
      final report = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(
        report,
        'course-entry-v2 | paso=lookup-get | error=permission-denied',
      );
      expect(report, isNot(contains('2345')));
      expect(report, isNot(contains('@')));
    },
  );

  testWidgets('docente prepara invitación, comparte texto y cambia el código', (
    tester,
  ) async {
    final repository = _EntryRepository();
    await tester.pumpWidget(
      _app(CourseInvitationScreen(course: _course(), repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generar código'));
    await tester.pumpAndSettle();
    expect(find.text('Tu invitación está lista.'), findsOneWidget);
    expect(find.text('2345-ABCD-E234-5FGH'), findsOneWidget);
    expect(repository.createCalls, 1);

    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver código para compartir').first);
    await tester.pumpAndSettle();
    expect(find.text('Comparte este código.'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Acceso por aprobación'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gestionar invitación').first);
    await tester.tap(find.text('Gestionar invitación').first);
    await tester.pumpAndSettle();
    await _tapCourseAction(tester, 'Renovar código');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar renovación'));
    await tester.pumpAndSettle();
    expect(repository.renewCalls, 1);
    expect(find.text('Invitación renovada.'), findsOneWidget);
    expect(find.text('ABCD-E234-5FGH-JKLM'), findsOneWidget);
  });

  testWidgets(
    'a stale date is displayed as confirmed and never blocks renewal',
    (tester) async {
      final staleCreatedAt = DateTime(2000, 1, 1);
      final repository = _EntryRepository()
        ..invitation = CourseInvitation(
          courseId: 'course-1',
          code: '2345ABCDE2345FGH',
          status: 'active',
          createdAt: staleCreatedAt,
          updatedAt: staleCreatedAt,
        );
      await tester.pumpWidget(
        _app(CourseInvitationScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(repository.createCalls, 0);
      expect(find.textContaining('Vence el'), findsOneWidget);
      expect(find.text('Código vencido'), findsNothing);

      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gestionar invitación').first);
      await tester.pumpAndSettle();
      await _tapCourseAction(tester, 'Renovar código');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar renovación'));
      await tester.pumpAndSettle();
      expect(repository.renewCalls, 1);
      expect(find.text('Invitación renovada.'), findsOneWidget);
    },
  );

  testWidgets('unconfirmed expiry shows a waiting state without an estimate', (
    tester,
  ) async {
    final repository = _EntryRepository()
      ..invitation = _invitation(unconfirmedExpiry: true);
    await tester.pumpWidget(
      _app(CourseInvitationScreen(course: _course(), repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmando la fecha de vigencia…'), findsOneWidget);
    expect(find.textContaining('Vence el'), findsNothing);
  });

  testWidgets(
    'estudiante consulta solo materia grupo y periodo, envía una solicitud y ve estado',
    (tester) async {
      final repository = _EntryRepository()..uid = 'student-1';
      final enrollmentRepository = _EnrollmentRepository();
      await tester.pumpWidget(
        _app(
          StudentCourseCodeScreen(
            repository: repository,
            enrollmentRepository: enrollmentRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2345-abcd-e234-5fgh');
      await tester.tap(find.text('Consultar curso'));
      await tester.pumpAndSettle();
      expect(find.text('Bases de Datos · G2'), findsOneWidget);
      expect(find.text('2026-2'), findsOneWidget);
      expect(find.text('Horario semanal'), findsNothing);
      expect(find.text('Solicitar unirme'), findsOneWidget);

      await tester.tap(find.text('Solicitar unirme'));
      await tester.pumpAndSettle();
      expect(repository.submitCalls, 1);
      expect(find.text('Tu solicitud fue enviada.'), findsOneWidget);
      expect(find.text('El docente decide el ingreso'), findsOneWidget);
    },
  );

  testWidgets('el botón de solicitar se desactiva durante una operación', (
    tester,
  ) async {
    final repository = _EntryRepository()
      ..uid = 'student-1'
      ..pendingSubmit = Completer<JoinRequestResult>();
    await tester.pumpWidget(
      _app(
        ConfirmCourseRequestScreen(
          preview: _preview(),
          repository: repository,
          enrollmentRepository: _EnrollmentRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar unirme'));
    await tester.pump();
    expect(repository.submitCalls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    repository.pendingSubmit!.complete(
      JoinRequestResult(
        kind: JoinRequestResultKind.created,
        courseId: 'course-1',
        request: _request(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu solicitud fue enviada.'), findsOneWidget);
    expect(repository.submitCalls, 1);
  });

  testWidgets('un código no crea solicitud si la matrícula está retirada', (
    tester,
  ) async {
    final repository = _EntryRepository()
      ..uid = 'student-1'
      ..submitKind = JoinRequestResultKind.alreadyWithdrawn;
    await tester.pumpWidget(
      _app(
        ConfirmCourseRequestScreen(
          preview: _preview(),
          repository: repository,
          enrollmentRepository: _EnrollmentRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar unirme'));
    await tester.pumpAndSettle();
    expect(find.text('Tu inscripción está retirada.'), findsOneWidget);
    expect(find.text('No se creó otra solicitud'), findsOneWidget);
    expect(repository.submitCalls, 1);
    expect(repository.decisionCalls, 0);
    expect(find.text('Horario semanal'), findsNothing);
  });

  testWidgets(
    'una aprobación histórica no afirma acceso cuando la matrícula está retirada',
    (tester) async {
      final enrollmentRepository = _EnrollmentRepository()
        ..items.add(_enrollment(status: 'withdrawn'));
      await tester.pumpWidget(
        _app(
          CourseJoinRequestStatusScreen(
            preview: _preview(),
            status: JoinRequestStatus.approved,
            request: _request(status: JoinRequestStatus.approved),
            repository: _EntryRepository()..uid = 'student-1',
            enrollmentRepository: enrollmentRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Solicitud aprobada'), findsOneWidget);
      expect(find.text('Aprobación histórica'), findsOneWidget);
      expect(find.text('Acceso confirmado'), findsNothing);
      expect(
        find.textContaining('Mis materias muestra solo matrículas activas'),
        findsOneWidget,
      );

      await tester.tap(find.text('Ver mis materias'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no tienes materias inscritas'), findsOneWidget);
      expect(find.text('Horario semanal'), findsNothing);
    },
  );

  testWidgets(
    'un fallo al refrescar la lista no revierte una aprobación confirmada',
    (tester) async {
      final repository = _EntryRepository()..uid = 'teacher-1';
      await tester.pumpWidget(
        _app(
          TeacherJoinRequestsScreen(course: _course(), repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estudiante de prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Fecha de solicitud'), findsOneWidget);
      expect(find.text('Ingreso efectivo'), findsNothing);
      await tester.tap(find.text('Aprobar ingreso'));
      await tester.pumpAndSettle();
      expect(find.text('Ingreso aprobado.'), findsOneWidget);
      expect(repository.decisionCalls, 1);

      repository.failNextCourseList = true;
      await tester.tap(find.text('Volver a solicitudes'));
      await tester.pumpAndSettle();
      expect(find.text('No pudimos completar la operación'), findsOneWidget);
      expect(find.text('No se confirmó la decisión'), findsNothing);
      expect(repository.decisionCalls, 1);
      expect(repository.courseListCalls, 2);
    },
  );

  testWidgets(
    'la aprobación no reactiva una matrícula retirada ni queda disponible para repetir',
    (tester) async {
      final repository = _EntryRepository()
        ..uid = 'teacher-1'
        ..rejectApprovalForWithdrawnEnrollment = true;
      await tester.pumpWidget(
        _app(
          TeacherJoinRequestsScreen(course: _course(), repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estudiante de prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aprobar ingreso'));
      await tester.pumpAndSettle();
      expect(find.text('La matrícula está retirada'), findsOneWidget);
      expect(
        find.textContaining(
          'La aprobación no cambió la solicitud ni el estado del estudiante.',
        ),
        findsOneWidget,
      );
      expect(repository.request.status, JoinRequestStatus.pending);
      expect(repository.decisionCalls, 1);
      await tester.scrollUntilVisible(
        find.text('Aprobar ingreso'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Aprobar ingreso'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('desactivar código confirma y conserva el acceso ya concedido', (
    tester,
  ) async {
    final repository = _EntryRepository()..uid = 'teacher-1';
    await tester.pumpWidget(
      _app(
        ManageCourseInvitationScreen(
          course: _course(),
          invitation: _invitation(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapCourseAction(tester, 'Desactivar código');
    await tester.pumpAndSettle();
    expect(find.text('¿Desactivar el código?'), findsOneWidget);
    expect(
      find.textContaining('matrículas existentes se conservan'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirmar desactivación'));
    await tester.pumpAndSettle();
    expect(repository.deactivateCalls, 1);
    expect(find.text('Invitación desactivada.'), findsOneWidget);
  });

  testWidgets(
    'rechazo pide un motivo y lo presenta como decisión persistente',
    (tester) async {
      final repository = _EntryRepository();
      await tester.pumpWidget(
        _app(
          ReviewJoinRequestScreen(
            course: _course(),
            request: _request(),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechazar solicitud'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Falta confirmar el grupo.',
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(repository.decisionCalls, 1);
      expect(find.text('Solicitud rechazada.'), findsOneWidget);
      expect(find.text('Falta confirmar el grupo.'), findsOneWidget);
    },
  );

  testWidgets(
    'pantalla de código se adapta a 320, 390 y 430 px con texto ampliado y teclado',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _EntryRepository()..uid = 'student-1';
      for (final width in [320.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        await tester.pumpWidget(
          _app(
            KeyedSubtree(
              key: ValueKey(width),
              child: StudentCourseCodeScreen(
                repository: repository,
                enrollmentRepository: _EnrollmentRepository(),
              ),
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '2345abcd e2345fgh');
        tester.view.viewInsets = const FakeViewPadding(bottom: 500);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho ${width.toInt()}',
        );
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text('Consultar curso'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho ${width.toInt()}',
        );
      }
    },
  );

  testWidgets(
    'solicitud rechazada conserva motivo en la consulta del estudiante',
    (tester) async {
      final repository = _EntryRepository()
        ..uid = 'student-1'
        ..request = _request(
          status: JoinRequestStatus.rejected,
          rejectionReason: 'El grupo no coincide.',
        );
      await tester.pumpWidget(
        _app(
          StudentCourseCodeScreen(
            repository: repository,
            enrollmentRepository: _EnrollmentRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consultar mis solicitudes'));
      await tester.pumpAndSettle();
      expect(find.text('Bases de Datos · G2'), findsOneWidget);
      expect(find.text('El grupo no coincide.'), findsOneWidget);
      expect(find.textContaining('Rechazada'), findsOneWidget);
    },
  );

  testWidgets(
    'listas docente y estudiante caben a 320, 390 y 430 con texto ampliado',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _EntryRepository();
      final enrollments = _EnrollmentRepository();

      for (final width in [320.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        await tester.pumpWidget(
          _app(
            TeacherJoinRequestsScreen(
              course: _course(),
              repository: repository,
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Solicitudes de ingreso'), findsOneWidget);
        expect(find.text('Estudiante de prueba'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'lista docente a ${width.toInt()} px',
        );

        repository.uid = 'student-1';
        await tester.pumpWidget(
          _app(
            MyJoinRequestsScreen(
              repository: repository,
              enrollmentRepository: enrollments,
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mis solicitudes'), findsOneWidget);
        expect(find.text('Bases de Datos · G2'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'lista estudiante a ${width.toInt()} px',
        );
      }
    },
  );

  testWidgets(
    'diálogo de rechazo y confirmación de renovación caben con teclado y escala',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _EntryRepository()..uid = 'teacher-1';

      for (final width in [320.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        tester.view.resetViewInsets();
        await tester.pumpWidget(
          _app(
            ReviewJoinRequestScreen(
              course: _course(),
              request: _request(),
              repository: repository,
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -700));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Rechazar solicitud'));
        await tester.tap(find.text('Rechazar solicitud'));
        await tester.pumpAndSettle();
        expect(find.text('Motivo del rechazo'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'El grupo necesita una revisión adicional.',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 480);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'diálogo M17 con teclado a ${width.toInt()} px',
        );
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _app(
            ManageCourseInvitationScreen(
              course: _course(),
              invitation: _invitation(),
              repository: repository,
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Activo'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'gestión M29 a ${width.toInt()} px con texto ampliado',
        );
        await tester.scrollUntilVisible(
          find.text('Desactivar código'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Desactivar código'), findsOneWidget);
        await _tapCourseAction(tester, 'Renovar código');
        await tester.pumpAndSettle();
        expect(find.text('¿Renovar el código?'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'diálogo M30 a ${width.toInt()} px',
        );
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      }
    },
  );
}
