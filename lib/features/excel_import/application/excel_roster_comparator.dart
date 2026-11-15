import '../../enrollments/domain/enrollment.dart';
import '../../enrollments/domain/pending_enrollment.dart';
import '../../enrollments/domain/pending_enrollment_page.dart';
import '../domain/excel_import_document.dart';
import '../domain/excel_import_review.dart';

/// Compares already validated spreadsheet rows with a complete course
/// snapshot. It has no Firebase dependency and never writes.
class ExcelRosterComparator {
  const ExcelRosterComparator();

  ExcelReview compare({
    required ExcelImportSheet sheet,
    required List<ExcelReviewedRow> resolvedRows,
    required CourseRosterSnapshot snapshot,
    required ExcelImportMode mode,
  }) {
    if (mode == ExcelImportMode.completeList && !snapshot.complete) {
      final rows = resolvedRows
          .map((row) {
            if (row.status == ExcelReviewStatus.invalid ||
                row.status == ExcelReviewStatus.duplicate) {
              return row;
            }
            return _copy(
              row,
              status: ExcelReviewStatus.error,
              action: ExcelReviewAction.none,
              message: 'No se cargaron todas las páginas del curso. Vuelve a comparar antes de confirmar cambios.',
            );
          })
          .toList(growable: false);
      return ExcelReview(
        rows: rows,
        mode: mode,
        isComplete: false,
        retirementsAllowed: false,
        retirementBlockReason: 'No se cargaron todas las páginas del curso. Vuelve a comparar antes de confirmar cambios.',
      );
    }
    final uniqueRows = _blockRepeatedCandidates(resolvedRows);
    final classified = uniqueRows
        .map((row) => _classify(row, snapshot))
        .toList(growable: false);

    final activeMembers = <ExcelRosterMember>[
      ...snapshot.activeEnrollments.map(ExcelRosterMember.fromEnrollment),
      ...snapshot.pendingEnrollments.map(ExcelRosterMember.fromPending),
    ];
    final representedOrConflicted = <String>{};
    for (final row in classified) {
      final email = row.row.email.trim();
      final code = row.row.studentCode.trim();
      if (email.isEmpty && code.isEmpty) continue;
      for (final member in activeMembers) {
        if (member.email == email || member.studentCode?.trim() == code) {
          // A partial identity match is deliberately protected from becoming
          // both an addition and a withdrawal proposal.
          representedOrConflicted.add(member.identityKey);
        }
      }
    }

    final trustworthyFile =
        sheet.rows.isNotEmpty &&
        classified.isNotEmpty &&
        classified.every((row) => !_blocksFullList(row.status));
    final complete =
        (mode == ExcelImportMode.additionsOnly || snapshot.complete) &&
        classified.every((row) => row.status != ExcelReviewStatus.error);
    final withdrawalsAllowed =
        mode == ExcelImportMode.completeList && complete && trustworthyFile;

    final possibleWithdrawals = <ExcelRosterMember>[];
    if (mode == ExcelImportMode.completeList && snapshot.complete) {
      for (final member in activeMembers) {
        if (!representedOrConflicted.contains(member.identityKey)) {
          possibleWithdrawals.add(member);
        }
      }
    }

    return ExcelReview(
      rows: classified,
      mode: mode,
      potentialWithdrawals: possibleWithdrawals,
      isComplete: complete,
      retirementsAllowed: withdrawalsAllowed,
      retirementBlockReason: _retirementBlockReason(
        mode: mode,
        snapshotComplete: snapshot.complete,
        sheet: sheet,
        rows: classified,
      ),
    );
  }

  List<ExcelReviewedRow> _blockRepeatedCandidates(List<ExcelReviewedRow> rows) {
    final rowsByUid = <String, List<int>>{};
    for (final row in rows) {
      final uid = row.candidate?.uid;
      if (uid != null) {
        rowsByUid.putIfAbsent(uid, () => []).add(row.row.rowNumber);
      }
    }
    return rows
        .map((row) {
          final uid = row.candidate?.uid;
          if (uid == null || (rowsByUid[uid]?.length ?? 0) < 2) return row;
          final affected = rowsByUid[uid]!..sort();
          return _copy(
            row,
            status: ExcelReviewStatus.duplicate,
            action: ExcelReviewAction.none,
            message:
                'La misma cuenta coincide con las filas ${affected.join(', ')}.',
          );
        })
        .toList(growable: false);
  }

  ExcelReviewedRow _classify(
    ExcelReviewedRow row,
    CourseRosterSnapshot snapshot,
  ) {
    if (row.status != ExcelReviewStatus.eligible &&
        row.status != ExcelReviewStatus.pendingEligible) {
      return row;
    }
    final email = row.row.email.trim();
    final code = row.row.studentCode.trim();
    if (row.candidate case final candidate?) {
      if (candidate.email != email) {
        return _conflict(
          row,
          'El correo de la cuenta ya no coincide. Revisa la fila.',
        );
      }
      if (candidate.studentCode == null || candidate.studentCode != code) {
        return _copy(
          row,
          status: ExcelReviewStatus.codeMismatch,
          action: ExcelReviewAction.none,
          message: 'Revisar código estudiantil; no se vincula por nombre.',
        );
      }
    }

    final related = <ExcelRosterMember>[
      ...snapshot.activeEnrollments.map(ExcelRosterMember.fromEnrollment),
      ...snapshot.withdrawnEnrollments.map(ExcelRosterMember.fromEnrollment),
      ...snapshot.pendingEnrollments.map(ExcelRosterMember.fromPending),
      ...snapshot.withdrawnPendingEnrollments.map(
        ExcelRosterMember.fromPending,
      ),
    ].where((member) => member.email == email || member.studentCode == code);
    if (related.length > 1) {
      return _conflict(
        row,
        'El correo o el código aparece en más de una inscripción. Revisa los datos del curso.',
      );
    }
    if (related.isNotEmpty) {
      final member = related.single;
      if (member.email != email || member.studentCode != code) {
        return _conflict(
          row,
          'El correo y el código apuntan a datos distintos. Corrige la identidad antes de actualizar.',
        );
      }
      if (member.enrollment case final enrollment?) {
        final candidate = row.candidate;
        if (candidate != null && candidate.uid != enrollment.studentUid) {
          return _conflict(
            row,
            'El correo ya está asociado a otra matrícula. No se creará una identidad duplicada.',
          );
        }
        if (enrollment.status == 'active') {
          return _copy(
            row,
            status: ExcelReviewStatus.alreadyEnrolled,
            enrollment: enrollment,
            action: ExcelReviewAction.none,
            message: 'Sin cambios: ya pertenece al curso.',
          );
        }
        return _copy(
          row,
          status: ExcelReviewStatus.rejoinEnrollment,
          enrollment: enrollment,
          action: ExcelReviewAction.rejoinEnrollment,
          operationId: row.operationId,
          message: 'Retirado. Reincorpora solo si lo confirmas explícitamente.',
        );
      }
      final pending = member.pendingEnrollment!;
      if (pending.status == 'pending') {
        return _copy(
          row,
          status: ExcelReviewStatus.unchangedPending,
          pendingEnrollment: pending,
          action: ExcelReviewAction.none,
          message: 'Sin cambios: ya está pendiente de vincular.',
        );
      }
      return _copy(
        row,
        status: ExcelReviewStatus.reopenPending,
        pendingEnrollment: pending,
        action: ExcelReviewAction.reopenPending,
        operationId: row.operationId,
        message:
            'La autorización estaba retirada. Reactívala solo si lo confirmas.',
      );
    }

    if (row.candidate == null) {
      return _copy(
        row,
        status: ExcelReviewStatus.pendingEligible,
        action: ExcelReviewAction.authorizePending,
        message: 'Cuenta no disponible: puedes autorizarla como pendiente de vincular.',
      );
    }
    return _copy(
      row,
      status: ExcelReviewStatus.eligible,
      action: ExcelReviewAction.enrollDirect,
      message: 'Cuenta verificada y disponible para agregar.',
    );
  }

  ExcelReviewedRow _conflict(ExcelReviewedRow row, String message) => _copy(
    row,
    status: ExcelReviewStatus.identityConflict,
    action: ExcelReviewAction.none,
    message: message,
  );

  ExcelReviewedRow _copy(
    ExcelReviewedRow row, {
    required ExcelReviewStatus status,
    required ExcelReviewAction action,
    required String message,
    Enrollment? enrollment,
    PendingEnrollment? pendingEnrollment,
    String? operationId,
  }) => ExcelReviewedRow(
    row: row.row,
    status: status,
    candidate: row.candidate,
    enrollment: enrollment ?? row.enrollment,
    pendingEnrollment: pendingEnrollment ?? row.pendingEnrollment,
    action: action,
    operationId: operationId ?? row.operationId,
    message: message,
  );

  bool _blocksFullList(ExcelReviewStatus status) => switch (status) {
    ExcelReviewStatus.invalid ||
    ExcelReviewStatus.duplicate ||
    ExcelReviewStatus.unavailable ||
    ExcelReviewStatus.codeMismatch ||
    ExcelReviewStatus.identityConflict ||
    ExcelReviewStatus.withdrawn ||
    ExcelReviewStatus.error => true,
    _ => false,
  };

  String? _retirementBlockReason({
    required ExcelImportMode mode,
    required bool snapshotComplete,
    required ExcelImportSheet sheet,
    required List<ExcelReviewedRow> rows,
  }) {
    if (mode != ExcelImportMode.completeList) {
      return 'El modo «Solo agregar» conserva a quienes no aparecen en el archivo.';
    }
    if (!snapshotComplete) {
      return 'No se cargaron todas las páginas del curso. Vuelve a comparar antes de proponer retiros.';
    }
    if (sheet.rows.isEmpty) {
      return 'La hoja está vacía. No se puede retirar a todo el curso desde una lista vacía.';
    }
    if (rows.any((row) => _blocksFullList(row.status))) {
      return 'Hay filas inválidas, repetidas o con conflictos. Corrígelas o usa «Solo agregar»; no se habilitan retiros.';
    }
    return null;
  }
}
