import '../../courses/domain/course.dart';
import '../../enrollments/application/enrollment_validator.dart';
import '../../enrollments/domain/enrollment.dart';
import '../../enrollments/domain/enrollment_failure.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/domain/student_candidate.dart';
import '../domain/excel_import_document.dart';
import '../domain/excel_import_review.dart';

/// Coordinates local rows with exact directory lookups and canonical writes.
/// Reviewing never writes. Each confirmed row is its own transaction.
class ExcelImportCoordinator {
  const ExcelImportCoordinator(this.repository);

  final EnrollmentRepository repository;

  Future<ExcelReview> review({
    required Course course,
    required ExcelImportSheet sheet,
  }) async {
    final uid = await _checkOwner(course);
    final input = sheet.rows;
    final repeatedEmails = _repeated(input, (row) => row.email.trim());
    final repeatedCodes = _repeated(input, (row) => row.studentCode.trim());
    final evaluated = await _mapLimited(input, (row) async {
      if (!row.isValid ||
          row.email.trim().isEmpty ||
          row.studentCode.trim().isEmpty ||
          row.name.trim().isEmpty) {
        return ExcelReviewedRow(
          row: row,
          status: ExcelReviewStatus.invalid,
          message: row.validationError ?? 'Completa código, correo y nombre.',
        );
      }
      String email;
      try {
        email = EnrollmentValidator.exactEmail(row.email);
      } on EnrollmentFailure {
        return ExcelReviewedRow(
          row: row,
          status: ExcelReviewStatus.invalid,
          message: 'El correo de la fila no tiene un formato válido.',
        );
      }
      final emailRows = repeatedEmails[row.email.trim()];
      final codeRows = repeatedCodes[row.studentCode.trim()];
      if (emailRows != null || codeRows != null) {
        final affected = {...?emailRows, ...?codeRows}.toList()..sort();
        return ExcelReviewedRow(
          row: row,
          status: ExcelReviewStatus.duplicate,
          message:
              'Correo o código repetido en las filas ${affected.join(', ')}.',
        );
      }
      try {
        _assertSession(uid);
        final candidate = await repository.findStudentByEmail(email);
        _assertSession(uid);
        if (candidate == null) {
          return ExcelReviewedRow(
            row: row,
            status: ExcelReviewStatus.unavailable,
            message: 'Cuenta no disponible para vincular. Puede volver a importarse después.',
          );
        }
        if (candidate.email != email) {
          return ExcelReviewedRow(
            row: row,
            status: ExcelReviewStatus.error,
            message: 'La identidad publicada no coincide con el correo consultado.',
          );
        }
        if (candidate.studentCode == null ||
            candidate.studentCode != row.studentCode.trim()) {
          return ExcelReviewedRow(
            row: row,
            candidate: candidate,
            status: ExcelReviewStatus.codeMismatch,
            message: 'Revisar código estudiantil; no se vincula por nombre.',
          );
        }
        final enrollment = await _existing(course.id, candidate.uid);
        _assertSession(uid);
        if (enrollment?.status == 'active') {
          return ExcelReviewedRow(
            row: row,
            candidate: candidate,
            status: ExcelReviewStatus.alreadyEnrolled,
            message: 'Ya inscrito en este curso.',
          );
        }
        if (enrollment?.status == 'withdrawn') {
          return ExcelReviewedRow(
            row: row,
            candidate: candidate,
            status: ExcelReviewStatus.withdrawn,
            message: 'Retirado. Usa la reincorporación individual para conservar el historial.',
          );
        }
        return ExcelReviewedRow(
          row: row,
          candidate: candidate,
          status: ExcelReviewStatus.eligible,
          message: 'Lista para matricular.',
        );
      } on EnrollmentFailure catch (error) {
        if (error.kind == EnrollmentFailureKind.unauthenticated) rethrow;
        return ExcelReviewedRow(
          row: row,
          status: ExcelReviewStatus.error,
          message: _failureMessage(error),
        );
      } catch (_) {
        return ExcelReviewedRow(
          row: row,
          status: ExcelReviewStatus.error,
          message: 'No se pudo revisar la fila. Intenta otra vez.',
        );
      }
    });
    _assertSession(uid);

    // A UID may appear under different directory emails in old data. Neither
    // row is allowed to win based on its position in the spreadsheet.
    final uidRows = <String, List<int>>{};
    for (final item in evaluated) {
      final candidateUid = item.candidate?.uid;
      if (candidateUid != null) {
        uidRows.putIfAbsent(candidateUid, () => []).add(item.row.rowNumber);
      }
    }
    return ExcelReview(
      rows: evaluated
          .map((item) {
            final candidateUid = item.candidate?.uid;
            if (candidateUid != null &&
                (uidRows[candidateUid]?.length ?? 0) > 1) {
              final affected = uidRows[candidateUid]!..sort();
              return ExcelReviewedRow(
                row: item.row,
                candidate: item.candidate,
                status: ExcelReviewStatus.duplicate,
                message:
                    'La misma cuenta coincide con las filas ${affected.join(', ')}.',
              );
            }
            return item;
          })
          .toList(growable: false),
    );
  }

  Future<ExcelImportResult> confirm({
    required Course course,
    required List<ExcelReviewedRow> selected,
  }) async {
    final uid = await _checkOwner(course);
    if (selected.isEmpty || selected.any((row) => !row.selectable)) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    final rowNumbers = <int>{};
    final emails = <String>{};
    final codes = <String>{};
    final candidateUids = <String>{};
    for (final item in selected) {
      final candidate = item.candidate!;
      if (!rowNumbers.add(item.row.rowNumber) ||
          !emails.add(item.row.email.trim()) ||
          !codes.add(item.row.studentCode.trim()) ||
          !candidateUids.add(candidate.uid)) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
      }
    }
    final results = await _mapLimited(selected, (item) async {
      try {
        _assertSession(uid);
        final searchedEmail = EnrollmentValidator.exactEmail(item.row.email);
        final current = await repository.findStudentByEmail(searchedEmail);
        _assertSession(uid);
        if (current == null ||
            current.email != searchedEmail ||
            !_sameCandidate(item.candidate!, current) ||
            current.studentCode != item.row.studentCode.trim()) {
          return ExcelConfirmedRow(
            reviewed: item,
            outcome: ExcelImportOutcome.needsReview,
            message: 'La cuenta o su código cambió. Revisa la fila antes de reintentar.',
          );
        }
        final existing = await _existing(course.id, current.uid);
        _assertSession(uid);
        if (existing != null) return _existingOutcome(item, existing);
        final result = await repository.enrollStudent(
          courseId: course.id,
          candidate: current,
          resolvePendingWhenAlreadyEnrolled: false,
        );
        // The transaction has returned a confirmed result. A later session
        // change must not turn that confirmed write into an apparent failure.
        if (result.alreadyEnrolled) {
          return _existingOutcome(item, result.enrollment);
        }
        return ExcelConfirmedRow(
          reviewed: item,
          outcome: ExcelImportOutcome.enrolledNow,
          message: 'Matriculada ahora con la fecha del servidor.',
        );
      } on EnrollmentFailure catch (error) {
        return ExcelConfirmedRow(
          reviewed: item,
          outcome: error.kind == EnrollmentFailureKind.candidateChanged
              ? ExcelImportOutcome.needsReview
              : ExcelImportOutcome.failed,
          message: _failureMessage(error),
        );
      } catch (_) {
        return ExcelConfirmedRow(
          reviewed: item,
          outcome: ExcelImportOutcome.failed,
          message: 'No se confirmó esta matrícula. Consulta el estado y vuelve a revisar antes de reintentar.',
        );
      }
    });
    return ExcelImportResult(rows: results);
  }

  Future<String> _checkOwner(Course course) async {
    EnrollmentValidator.documentId(course.id);
    final uid = repository.currentUid;
    if (uid == null) {
      throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
    }
    if (uid != course.ownerUid) {
      throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
    }
    // Server-backed count checks teacher role and ownership through Rules.
    await repository.countCourseStudents(course.id);
    _assertSession(uid);
    return uid;
  }

  void _assertSession(String uid) {
    if (repository.currentUid != uid) {
      throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
    }
  }

  Future<Enrollment?> _existing(String courseId, String studentUid) async {
    try {
      return await repository.getCourseEnrollment(
        courseId: courseId,
        studentUid: studentUid,
      );
    } on EnrollmentFailure catch (error) {
      if (error.kind == EnrollmentFailureKind.courseUnavailable) return null;
      rethrow;
    }
  }

  ExcelConfirmedRow _existingOutcome(
    ExcelReviewedRow item,
    Enrollment existing,
  ) {
    if (existing.status == 'withdrawn') {
      return ExcelConfirmedRow(
        reviewed: item,
        outcome: ExcelImportOutcome.withdrawn,
        message: 'Inscripción retirada; usa la reincorporación individual.',
      );
    }
    if (existing.status == 'active') {
      return ExcelConfirmedRow(
        reviewed: item,
        outcome: ExcelImportOutcome.alreadyEnrolled,
        message: 'Ya estaba inscrito; no se creó otra matrícula.',
      );
    }
    return ExcelConfirmedRow(
      reviewed: item,
      outcome: ExcelImportOutcome.failed,
      message: 'Estado de matrícula inesperado. Consulta la lista.',
    );
  }

  bool _sameCandidate(StudentCandidate left, StudentCandidate right) =>
      left.uid == right.uid &&
      left.name == right.name &&
      left.email == right.email &&
      left.studentCode == right.studentCode;

  Map<String, List<int>> _repeated(
    List<ExcelImportRow> rows,
    String Function(ExcelImportRow) key,
  ) {
    final occurrences = <String, List<int>>{};
    for (final row in rows) {
      final value = key(row);
      if (value.isNotEmpty) {
        occurrences.putIfAbsent(value, () => []).add(row.rowNumber);
      }
    }
    occurrences.removeWhere((_, rowNumbers) => rowNumbers.length < 2);
    return occurrences;
  }

  Future<List<T>> _mapLimited<S, T>(
    List<S> input,
    Future<T> Function(S) action,
  ) async {
    final results = List<T?>.filled(input.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < input.length) {
        final index = next++;
        results[index] = await action(input[index]);
      }
    }

    await Future.wait(
      List.generate(input.length < 3 ? input.length : 3, (_) => worker()),
    );
    return results.cast<T>();
  }

  String _failureMessage(EnrollmentFailure error) => switch (error.kind) {
    EnrollmentFailureKind.network => 'Sin conexión o respuesta incierta. Consulta la lista antes de reintentar.',
    EnrollmentFailureKind.permissionDenied ||
    EnrollmentFailureKind.teacherRoleRequired =>
      'No tienes permiso para revisar o matricular en este curso.',
    EnrollmentFailureKind.candidateChanged =>
      'La cuenta cambió desde la revisión. Vuelve a revisar la fila.',
    EnrollmentFailureKind.courseUnavailable =>
      'El curso ya no está disponible para esta operación.',
    EnrollmentFailureKind.emailNotVerified =>
      'Tu correo debe estar verificado para continuar.',
    EnrollmentFailureKind.profileInvalid =>
      'Tu perfil no está disponible o no coincide con la sesión.',
    EnrollmentFailureKind.unauthenticated =>
      'La sesión cambió. Vuelve a entrar antes de continuar.',
    _ => 'No se pudo confirmar la fila. Consulta su estado y reintenta.',
  };
}
