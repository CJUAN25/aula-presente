import '../../schedule/application/course_schedule_validator.dart';
import '../domain/course_draft.dart';

class CourseValidationIssue {
  const CourseValidationIssue({
    required this.code,
    required this.field,
    required this.message,
    this.blockId,
  });

  final String code;
  final String field;
  final String message;
  final String? blockId;
}

abstract final class CourseDraftValidator {
  static List<CourseValidationIssue> validate(CourseDraft draft) {
    final issues = <CourseValidationIssue>[];
    if (!RegExp(r'^[A-Za-z0-9_-]{20,40}$').hasMatch(draft.id)) {
      issues.add(
        const CourseValidationIssue(
          code: 'invalid_course_id',
          field: 'id',
          message: 'El borrador no tiene un identificador estable válido.',
        ),
      );
    }
    _validateText(
      issues,
      'subject',
      draft.subject,
      120,
      'Escribe la asignatura.',
    );
    _validateText(issues, 'group', draft.group, 40, 'Escribe el grupo.');
    _validateText(issues, 'period', draft.period, 32, 'Escribe el período.');
    _validateText(
      issues,
      'program',
      draft.program,
      120,
      'Escribe el programa.',
    );

    for (final issue in CourseScheduleValidator.validate(draft.schedule)) {
      issues.add(
        CourseValidationIssue(
          code: issue.code,
          field: issue.field,
          message: issue.message,
          blockId: issue.blockId,
        ),
      );
    }
    return List.unmodifiable(issues);
  }

  static String normalizeText(String value) => normalizeCourseText(value);

  static void _validateText(
    List<CourseValidationIssue> issues,
    String field,
    String value,
    int maxLength,
    String emptyMessage,
  ) {
    final normalized = normalizeCourseText(value);
    if (normalized.isEmpty) {
      issues.add(
        CourseValidationIssue(
          code: 'required',
          field: field,
          message: emptyMessage,
        ),
      );
    } else if (normalized.length > maxLength) {
      issues.add(
        CourseValidationIssue(
          code: 'text_too_long',
          field: field,
          message: 'Usa máximo $maxLength caracteres.',
        ),
      );
    }
  }
}
