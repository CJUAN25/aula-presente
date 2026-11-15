import '../../courses/domain/course.dart';
import '../../enrollments/application/enrollment_validator.dart';
import '../../enrollments/domain/enrollment.dart';
import '../../enrollments/domain/enrollment_failure.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/domain/pending_enrollment.dart';
import '../../enrollments/domain/pending_enrollment_page.dart';
import '../../enrollments/domain/student_candidate.dart';
import '../../schedule/domain/academic_date.dart';
import '../domain/excel_import_document.dart';
import '../domain/excel_import_review.dart';
import 'excel_roster_comparator.dart';

/// Coordinates the local workbook, the complete course snapshot and the
/// per-person transactions. Reviewing never writes.
class ExcelImportCoordinator {
  const ExcelImportCoordinator(
    this.repository, {
    this._comparator = const ExcelRosterComparator(),
  });

  final EnrollmentRepository repository;
  final ExcelRosterComparator _comparator;

  Future<ExcelReview> review({
    required Course course,
    required ExcelImportSheet sheet,
    ExcelImportMode mode = ExcelImportMode.additionsOnly,
  }) async {
    final uid = await _checkOwner(course);
    final input = sheet.rows;
    final repeatedEmails = _repeated(input, (row) => row.email.trim());
    final repeatedCodes = _repeated(input, (row) => row.studentCode.trim());

    CourseRosterSnapshot? snapshot;
    if (mode == ExcelImportMode.completeList) {
      try {
        snapshot = await repository.loadCourseRosterSnapshot(
          courseId: course.id,
        );
        _assertSession(uid);
      } on EnrollmentFailure catch (error) {
        return _unavailableSnapshotReview(
          sheet: sheet,
          mode: mode,
          error: error,
        );
      } catch (_) {
        return _unavailableSnapshotReview(
          sheet: sheet,
          mode: mode,
          error: const EnrollmentFailure(EnrollmentFailureKind.network),
        );
      }
    }
    final partialEnrollments = <String, Enrollment>{};
    final partialPendings = <String, PendingEnrollment>{};
    void rememberEnrollment(Enrollment value) {
      partialEnrollments[value.studentUid] = value;
    }

    void rememberPending(PendingEnrollment value) {
      if (value.status != 'linked') partialPendings[value.email] = value;
    }

    final resolvedRows = await _mapLimited(input, (row) async {
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
          final base = ExcelReviewedRow(
            row: row,
            status: ExcelReviewStatus.pendingEligible,
            message:
                'Cuenta no disponible; se revisará como pendiente de vincular.',
          );
          return mode == ExcelImportMode.additionsOnly
              ? await _resolvePartialIdentity(
                  base,
                  courseId: course.id,
                  email: email,
                  uid: uid,
                  rememberEnrollment: rememberEnrollment,
                  rememberPending: rememberPending,
                )
              : base;
        }
        if (candidate.email != email) {
          return ExcelReviewedRow(
            row: row,
            status: ExcelReviewStatus.identityConflict,
            message:
                'La identidad publicada no coincide con el correo consultado.',
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
        final base = ExcelReviewedRow(
          row: row,
          candidate: candidate,
          status: ExcelReviewStatus.eligible,
          message: 'Identidad cotejada; verificando el estado del curso.',
        );
        return mode == ExcelImportMode.additionsOnly
            ? await _resolvePartialIdentity(
                base,
                courseId: course.id,
                email: email,
                uid: uid,
                rememberEnrollment: rememberEnrollment,
                rememberPending: rememberPending,
              )
            : base;
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
          message: 'No se pudo revisar la identidad. Intenta otra vez.',
        );
      }
    });
    _assertSession(uid);

    snapshot ??= CourseRosterSnapshot(
      activeEnrollments: partialEnrollments.values
          .where((item) => item.status == 'active')
          .toList(growable: false),
      withdrawnEnrollments: partialEnrollments.values
          .where((item) => item.status == 'withdrawn')
          .toList(growable: false),
      pendingEnrollments: partialPendings.values
          .where((item) => item.status == 'pending')
          .toList(growable: false),
      withdrawnPendingEnrollments: partialPendings.values
          .where((item) => item.status == 'withdrawn')
          .toList(growable: false),
      complete: false,
    );
    final comparison = _comparator.compare(
      sheet: sheet,
      resolvedRows: resolvedRows,
      snapshot: snapshot,
      mode: mode,
    );
    final rows = comparison.rows
        .map((row) {
          if (row.operationId != null) return row;
          if (row.action == ExcelReviewAction.rejoinEnrollment &&
              row.enrollment != null) {
            return _copyRow(
              row,
              operationId: repository.newStatusEventId(
                courseId: course.id,
                studentUid: row.enrollment!.studentUid,
              ),
            );
          }
          if (row.action == ExcelReviewAction.reopenPending &&
              row.pendingEnrollment != null) {
            return _copyRow(
              row,
              operationId: repository.newPendingStatusEventId(
                courseId: course.id,
                email: row.pendingEnrollment!.email,
              ),
            );
          }
          return row;
        })
        .toList(growable: false);
    final withdrawals = comparison.potentialWithdrawals
        .map((member) {
          final operationId = member.kind == ExcelRosterMemberKind.enrollment
              ? repository.newStatusEventId(
                  courseId: course.id,
                  studentUid: member.enrollment!.studentUid,
                )
              : repository.newPendingStatusEventId(
                  courseId: course.id,
                  email: member.pendingEnrollment!.email,
                );
          return member.withOperationId(operationId);
        })
        .toList(growable: false);
    return ExcelReview(
      rows: rows,
      mode: comparison.mode,
      potentialWithdrawals: withdrawals,
      isComplete: comparison.isComplete,
      retirementsAllowed: comparison.retirementsAllowed,
      retirementBlockReason: comparison.retirementBlockReason,
    );
  }

  Future<ExcelImportResult> confirm({
    required Course course,
    required List<ExcelReviewedRow> selected,
    ExcelReview? review,
    List<ExcelRosterMember> selectedWithdrawals = const [],
    AcademicDate? effectiveStartDate,
    AcademicDate? withdrawalEffectiveDate,

    /// Backward-compatible alias for callers that still provide one date.
    AcademicDate? effectiveDate,
  }) async {
    final uid = await _checkOwner(course);
    if ((selected.isEmpty && selectedWithdrawals.isEmpty) ||
        selected.any((row) => !row.selectable)) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    if (selectedWithdrawals.isNotEmpty &&
        (review == null ||
            review.mode != ExcelImportMode.completeList ||
            !review.retirementsAllowed)) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    final allowedWithdrawals =
        review?.potentialWithdrawals
            .map((member) => member.identityKey)
            .toSet() ??
        <String>{};
    if (selectedWithdrawals.any(
          (member) => !allowedWithdrawals.contains(member.identityKey),
        ) ||
        selectedWithdrawals
                .map((member) => member.identityKey)
                .toSet()
                .length !=
            selectedWithdrawals.length) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    final rowNumbers = <int>{};
    final emails = <String>{};
    final codes = <String>{};
    final candidateUids = <String>{};
    for (final item in selected) {
      final email = EnrollmentValidator.exactEmail(item.row.email);
      if (!rowNumbers.add(item.row.rowNumber) ||
          !emails.add(email) ||
          !codes.add(item.row.studentCode.trim()) ||
          (item.candidate != null && !candidateUids.add(item.candidate!.uid))) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
      }
    }
    final startDate =
        effectiveStartDate ?? effectiveDate ?? _defaultEffectiveDate(course);
    final hasStartChanges = selected.any(
      (row) =>
          row.action == ExcelReviewAction.enrollDirect ||
          row.action == ExcelReviewAction.authorizePending ||
          row.action == ExcelReviewAction.rejoinEnrollment ||
          row.action == ExcelReviewAction.reopenPending,
    );
    if (hasStartChanges) {
      _validateEffectiveDate(course, startDate, allowFutureCourseStart: true);
    }
    final withdrawalDate =
        withdrawalEffectiveDate ??
        effectiveDate ??
        _defaultWithdrawalDate(course);
    if (selectedWithdrawals.isNotEmpty) {
      _validateWithdrawalDate(course, withdrawalDate);
    }

    final rowResults = await _mapLimited(selected, (item) async {
      try {
        _assertSession(uid);
        switch (item.action) {
          case ExcelReviewAction.enrollDirect:
            final candidate = await _recheckCandidate(item, uid);
            if (candidate == null) {
              return _rowResult(
                item,
                ExcelImportOutcome.needsReview,
                'La cuenta cambió. Vuelve a comparar antes de confirmar.',
              );
            }
            final matches = await repository.findCourseEnrollmentsByEmail(
              courseId: course.id,
              email: candidate.email,
            );
            _assertSession(uid);
            if (matches.length > 1 ||
                matches.any(
                  (enrollment) =>
                      enrollment.studentUid != candidate.uid ||
                      enrollment.studentCode != candidate.studentCode,
                )) {
              return _rowResult(
                item,
                ExcelImportOutcome.needsReview,
                'El correo ya se relaciona con otra matrícula. Revisa la identidad del curso.',
              );
            }
            if (matches.length == 1) {
              return _existingOutcome(item, matches.single);
            }
            final enrolled = await repository.enrollStudent(
              courseId: course.id,
              candidate: candidate,
              effectiveStartDate: startDate,
              resolvePendingWhenAlreadyEnrolled: false,
            );
            return enrolled.alreadyEnrolled
                ? _existingOutcome(item, enrolled.enrollment)
                : _rowResult(
                    item,
                    ExcelImportOutcome.enrolledNow,
                    'Alta confirmada desde ${startDate.isoDate}.',
                  );
          case ExcelReviewAction.authorizePending:
            final candidate = await repository.findStudentByEmail(
              EnrollmentValidator.exactEmail(item.row.email),
            );
            _assertSession(uid);
            if (candidate != null) {
              if (!_sameCandidateAtRow(item, candidate)) {
                return _rowResult(
                  item,
                  ExcelImportOutcome.needsReview,
                  'La cuenta apareció o cambió después de revisar. Vuelve a comparar la identidad.',
                );
              }
              final matches = await repository.findCourseEnrollmentsByEmail(
                courseId: course.id,
                email: candidate.email,
              );
              _assertSession(uid);
              if (matches.length > 1 ||
                  matches.any((e) => e.studentUid != candidate.uid)) {
                return _rowResult(
                  item,
                  ExcelImportOutcome.needsReview,
                  'El correo ya se relaciona con otra matrícula. Revisa la identidad del curso.',
                );
              }
              if (matches.length == 1) {
                return _existingOutcome(item, matches.single);
              }
              final enrolled = await repository.enrollStudent(
                courseId: course.id,
                candidate: candidate,
                effectiveStartDate: startDate,
                resolvePendingWhenAlreadyEnrolled: false,
              );
              return enrolled.alreadyEnrolled
                  ? _existingOutcome(item, enrolled.enrollment)
                  : _rowResult(
                      item,
                      ExcelImportOutcome.enrolledNow,
                      'La cuenta ya está verificada; alta confirmada desde ${startDate.isoDate}.',
                    );
            }
            final result = await repository.authorizePendingEnrollment(
              course: course,
              email: item.row.email.trim(),
              studentCode: item.row.studentCode.trim(),
              name: item.row.name.trim(),
              effectiveStartDate: startDate,
            );
            return _rowResult(
              item,
              result.created
                  ? ExcelImportOutcome.pendingNow
                  : ExcelImportOutcome.unchanged,
              result.created
                  ? 'Autorización guardada; se vinculará al verificar la cuenta.'
                  : 'La autorización ya estaba pendiente; no se duplicó.',
            );
          case ExcelReviewAction.rejoinEnrollment:
            final expected = item.enrollment;
            if (expected == null) {
              return _rowResult(
                item,
                ExcelImportOutcome.needsReview,
                'La matrícula ya no está disponible.',
              );
            }
            final result = await repository.changeEnrollmentStatus(
              expected: expected,
              nextStatus: 'active',
              operationId:
                  item.operationId ??
                  repository.newStatusEventId(
                    courseId: course.id,
                    studentUid: expected.studentUid,
                  ),
              effectiveDate: startDate,
            );
            return _rowResult(
              item,
              ExcelImportOutcome.rejoined,
              result.alreadyApplied
                  ? 'La reincorporación ya estaba confirmada.'
                  : 'Reincorporación confirmada desde ${startDate.isoDate}.',
            );
          case ExcelReviewAction.reopenPending:
            final expected = item.pendingEnrollment;
            if (expected == null) {
              return _rowResult(
                item,
                ExcelImportOutcome.needsReview,
                'La autorización ya no está disponible.',
              );
            }
            final result = await repository.changePendingEnrollmentStatus(
              expected: expected,
              nextStatus: 'pending',
              operationId:
                  item.operationId ??
                  repository.newPendingStatusEventId(
                    courseId: course.id,
                    email: expected.email,
                  ),
              effectiveDate: startDate,
            );
            return _rowResult(
              item,
              result.alreadyApplied
                  ? ExcelImportOutcome.unchanged
                  : ExcelImportOutcome.pendingReopened,
              result.alreadyApplied
                  ? 'La autorización ya estaba activa.'
                  : 'Pendiente reactivado para vincular la cuenta.',
            );
          case ExcelReviewAction.none:
            return _rowResult(
              item,
              ExcelImportOutcome.needsReview,
              'Esta fila no tiene una acción confirmable.',
            );
        }
      } on EnrollmentFailure catch (error) {
        return _rowResult(
          item,
          error.kind == EnrollmentFailureKind.candidateChanged ||
                  error.kind == EnrollmentFailureKind.staleEnrollment ||
                  error.kind == EnrollmentFailureKind.invalidInput
              ? ExcelImportOutcome.needsReview
              : ExcelImportOutcome.failed,
          _failureMessage(error),
        );
      } catch (_) {
        return _rowResult(
          item,
          ExcelImportOutcome.failed,
          'No se confirmó esta fila. Consulta el estado y vuelve a revisar antes de reintentar.',
        );
      }
    });

    final changes = await _mapLimited(selectedWithdrawals, (member) async {
      try {
        _assertSession(uid);
        final operationId =
            member.operationId ??
            (member.kind == ExcelRosterMemberKind.enrollment
                ? repository.newStatusEventId(
                    courseId: course.id,
                    studentUid: member.enrollment!.studentUid,
                  )
                : repository.newPendingStatusEventId(
                    courseId: course.id,
                    email: member.pendingEnrollment!.email,
                  ));
        if (member.enrollment case final enrollment?) {
          final result = await repository.changeEnrollmentStatus(
            expected: enrollment,
            nextStatus: 'withdrawn',
            operationId: operationId,
            effectiveDate: withdrawalDate,
          );
          return ExcelConfirmedRosterChange(
            member: member,
            outcome: ExcelRosterChangeOutcome.withdrawnNow,
            message: result.alreadyApplied
                ? 'El retiro ya estaba confirmado.'
                : 'Retiro confirmado desde ${withdrawalDate.isoDate}.',
          );
        }
        final pending = member.pendingEnrollment!;
        final result = await repository.changePendingEnrollmentStatus(
          expected: pending,
          nextStatus: 'withdrawn',
          operationId: operationId,
          effectiveDate: withdrawalDate,
        );
        return ExcelConfirmedRosterChange(
          member: member,
          outcome: ExcelRosterChangeOutcome.pendingWithdrawnNow,
          message: result.alreadyApplied
              ? 'El retiro de la autorización ya estaba confirmado.'
              : 'Autorización retirada desde ${withdrawalDate.isoDate}.',
        );
      } on EnrollmentFailure catch (error) {
        return ExcelConfirmedRosterChange(
          member: member,
          outcome:
              error.kind == EnrollmentFailureKind.staleEnrollment ||
                  error.kind == EnrollmentFailureKind.invalidInput
              ? ExcelRosterChangeOutcome.needsReview
              : ExcelRosterChangeOutcome.failed,
          message: _failureMessage(error),
        );
      } catch (_) {
        return ExcelConfirmedRosterChange(
          member: member,
          outcome: ExcelRosterChangeOutcome.failed,
          message: 'No se confirmó el retiro. Actualiza la comparación antes de reintentar.',
        );
      }
    });
    return ExcelImportResult(rows: rowResults, rosterChanges: changes);
  }

  Future<StudentCandidate?> _recheckCandidate(
    ExcelReviewedRow item,
    String uid,
  ) async {
    final email = EnrollmentValidator.exactEmail(item.row.email);
    final current = await repository.findStudentByEmail(email);
    _assertSession(uid);
    if (current == null || !_sameCandidateAtRow(item, current)) return null;
    return current;
  }

  Future<ExcelReviewedRow> _resolvePartialIdentity(
    ExcelReviewedRow row, {
    required String courseId,
    required String email,
    required String uid,
    required void Function(Enrollment) rememberEnrollment,
    required void Function(PendingEnrollment) rememberPending,
  }) async {
    final codeLookup = await repository.findCourseRosterByStudentCode(
      courseId: courseId,
      studentCode: row.row.studentCode.trim(),
    );
    _assertSession(uid);
    if (codeLookup.hasMoreEnrollmentMatches ||
        codeLookup.hasMorePendingMatches) {
      return _identityConflict(
        row,
        'Hay varias inscripciones con este código. Revisa la identidad antes de agregar.',
      );
    }
    for (final enrollment in codeLookup.enrollmentMatches) {
      rememberEnrollment(enrollment);
      if (enrollment.email != email ||
          enrollment.studentCode != row.row.studentCode.trim()) {
        return _identityConflict(
          row,
          'El código ya pertenece a otra identidad del curso. No se creará una matrícula duplicada.',
        );
      }
    }
    for (final pending in codeLookup.pendingMatches) {
      if (pending.status == 'linked') {
        final linkedUid = pending.studentUid;
        if (linkedUid == null) {
          return _identityConflict(
            row,
            'Hay una autorización vinculada sin matrícula canónica. Revisa el curso.',
          );
        }
        final enrollment = await repository.findCourseEnrollmentByUid(
          courseId: pending.courseId,
          studentUid: linkedUid,
        );
        _assertSession(uid);
        if (enrollment == null ||
            enrollment.rosterEntryId != pending.rosterEntryId) {
          return _identityConflict(
            row,
            'La autorización vinculada no coincide con la matrícula canónica. Revisa el curso.',
          );
        }
        rememberEnrollment(enrollment);
        if (enrollment.email != email ||
            enrollment.studentCode != row.row.studentCode.trim()) {
          return _identityConflict(
            row,
            'El código ya pertenece a otra identidad del curso. Revisa la fila.',
          );
        }
      } else {
        rememberPending(pending);
        if (pending.email != email ||
            pending.studentCode != row.row.studentCode.trim()) {
          return _identityConflict(
            row,
            'El código ya está autorizado para otro correo. Revisa la fila.',
          );
        }
      }
    }

    final emailEnrollments = await repository.findCourseEnrollmentsByEmail(
      courseId: courseId,
      email: email,
    );
    _assertSession(uid);
    if (emailEnrollments.length > 1) {
      for (final enrollment in emailEnrollments) {
        rememberEnrollment(enrollment);
      }
      return _identityConflict(
        row,
        'El correo aparece en varias matrículas del curso. Revisa la identidad.',
      );
    }
    for (final enrollment in emailEnrollments) {
      rememberEnrollment(enrollment);
      if (enrollment.studentCode != row.row.studentCode.trim() ||
          (row.candidate != null &&
              enrollment.studentUid != row.candidate!.uid)) {
        return _identityConflict(
          row,
          'El correo está asociado a una matrícula con otros datos. Revisa antes de cambiar la lista.',
        );
      }
    }

    final pending = await repository.getCoursePendingEnrollment(
      courseId: courseId,
      email: email,
    );
    _assertSession(uid);
    if (pending != null) {
      if (pending.status == 'linked') {
        final linkedUid = pending.studentUid;
        if (linkedUid == null) {
          return _identityConflict(
            row,
            'La autorización vinculada no conserva la cuenta. Revisa el curso.',
          );
        }
        final enrollment = await repository.findCourseEnrollmentByUid(
          courseId: courseId,
          studentUid: linkedUid,
        );
        _assertSession(uid);
        if (enrollment == null ||
            enrollment.rosterEntryId != pending.rosterEntryId) {
          return _identityConflict(
            row,
            'La autorización vinculada no coincide con la matrícula canónica. Revisa el curso.',
          );
        }
        rememberEnrollment(enrollment);
      } else {
        rememberPending(pending);
        if (pending.studentCode != row.row.studentCode.trim()) {
          return _identityConflict(
            row,
            'El correo ya tiene una autorización con otro código. Revisa la fila.',
          );
        }
      }
    }

    if (row.candidate case final candidate?) {
      final ownEnrollment = await repository.findCourseEnrollmentByUid(
        courseId: courseId,
        studentUid: candidate.uid,
      );
      _assertSession(uid);
      if (ownEnrollment != null) {
        rememberEnrollment(ownEnrollment);
        if (ownEnrollment.email != email ||
            ownEnrollment.studentCode != row.row.studentCode.trim()) {
          return _identityConflict(
            row,
            'El perfil cambió frente a una matrícula anterior. Revisa la identidad antes de actualizar.',
          );
        }
      }
    }
    return row;
  }

  ExcelReviewedRow _identityConflict(ExcelReviewedRow row, String message) =>
      ExcelReviewedRow(
        row: row.row,
        candidate: row.candidate,
        status: ExcelReviewStatus.identityConflict,
        message: message,
      );

  bool _sameCandidateAtRow(ExcelReviewedRow row, StudentCandidate current) {
    final reviewed = row.candidate;
    return reviewed != null &&
        _sameCandidate(reviewed, current) &&
        current.email == row.row.email.trim() &&
        current.studentCode == row.row.studentCode.trim();
  }

  ExcelReview _unavailableSnapshotReview({
    required ExcelImportSheet sheet,
    required ExcelImportMode mode,
    required EnrollmentFailure error,
  }) => ExcelReview(
    rows: sheet.rows
        .map(
          (row) => ExcelReviewedRow(
            row: row,
            status: row.isValid
                ? ExcelReviewStatus.error
                : ExcelReviewStatus.invalid,
            message: row.isValid
                ? 'No se cargó la lista completa del curso. ${_failureMessage(error)}'
                : row.validationError ?? 'Revisa los datos de esta fila.',
          ),
        )
        .toList(growable: false),
    mode: mode,
    isComplete: false,
    retirementsAllowed: false,
    retirementBlockReason: 'No se cargaron todas las páginas del curso. Vuelve a comparar antes de confirmar cambios.',
  );

  ExcelReviewedRow _copyRow(ExcelReviewedRow row, {String? operationId}) =>
      ExcelReviewedRow(
        row: row.row,
        status: row.status,
        message: row.message,
        candidate: row.candidate,
        enrollment: row.enrollment,
        pendingEnrollment: row.pendingEnrollment,
        action: row.action,
        operationId: operationId ?? row.operationId,
      );

  ExcelConfirmedRow _rowResult(
    ExcelReviewedRow item,
    ExcelImportOutcome outcome,
    String message,
  ) => ExcelConfirmedRow(reviewed: item, outcome: outcome, message: message);

  ExcelConfirmedRow _existingOutcome(
    ExcelReviewedRow item,
    Enrollment existing,
  ) {
    if (existing.status == 'active') {
      return _rowResult(
        item,
        ExcelImportOutcome.alreadyEnrolled,
        'La matrícula ya estaba activa; no se cambió.',
      );
    }
    if (existing.status == 'withdrawn') {
      return _rowResult(
        item,
        ExcelImportOutcome.withdrawn,
        'La matrícula ya estaba retirada. Usa la reincorporación explícita.',
      );
    }
    return _rowResult(
      item,
      ExcelImportOutcome.failed,
      'Estado de matrícula inesperado. Consulta la lista.',
    );
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
    await repository.countCourseStudents(course.id);
    _assertSession(uid);
    return uid;
  }

  void _assertSession(String uid) {
    if (repository.currentUid != uid) {
      throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
    }
  }

  AcademicDate _defaultEffectiveDate(Course course) {
    final today = _todayBogota();
    if (today.compareTo(course.schedule.startDate) < 0) {
      return course.schedule.startDate;
    }
    if (today.compareTo(course.schedule.endDate) > 0) {
      return course.schedule.endDate;
    }
    return today;
  }

  AcademicDate _defaultWithdrawalDate(Course course) {
    final today = _todayBogota();
    return today.compareTo(course.schedule.endDate) > 0
        ? course.schedule.endDate
        : today;
  }

  AcademicDate _todayBogota() => AcademicDate.fromDateTime(
    DateTime.now().toUtc().subtract(const Duration(hours: 5)),
  );

  void _validateEffectiveDate(
    Course course,
    AcademicDate date, {
    required bool allowFutureCourseStart,
  }) {
    final start = course.schedule.startDate;
    final end = course.schedule.endDate;
    final today = _todayBogota();
    final beforeStart = date.compareTo(start) < 0;
    final afterEnd = date.compareTo(end) > 0;
    final future = date.compareTo(today) > 0;
    final allowedFutureStart =
        allowFutureCourseStart && start.compareTo(today) > 0 && date == start;
    if (afterEnd ||
        (beforeStart && !allowedFutureStart) ||
        (future && !allowedFutureStart)) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }

  void _validateWithdrawalDate(Course course, AcademicDate date) {
    final today = _todayBogota();
    final start = course.schedule.startDate;
    final end = course.schedule.endDate;
    final earliest = start.compareTo(today) > 0 ? today : start;
    if (date.compareTo(earliest) < 0 ||
        date.compareTo(today) > 0 ||
        date.compareTo(end) > 0) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
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
      'No tienes permiso para revisar o cambiar la lista de este curso.',
    EnrollmentFailureKind.candidateChanged ||
    EnrollmentFailureKind.staleEnrollment => 'La identidad o el estado cambió desde la comparación. Vuelve a revisar antes de continuar.',
    EnrollmentFailureKind.courseUnavailable =>
      'El curso ya no está disponible para esta operación.',
    EnrollmentFailureKind.emailNotVerified =>
      'Tu correo debe estar verificado para continuar.',
    EnrollmentFailureKind.profileInvalid =>
      'Tu perfil no está disponible o no coincide con la sesión.',
    EnrollmentFailureKind.unauthenticated =>
      'La sesión cambió. Vuelve a entrar antes de continuar.',
    EnrollmentFailureKind.invalidInput =>
      'La fecha o los datos de esta operación no son válidos para el curso.',
    _ => 'No se pudo confirmar esta operación. Consulta su estado y reintenta.',
  };
}
