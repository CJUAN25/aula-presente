import '../domain/course_schedule.dart';
import '../domain/planned_meeting_generator.dart';
import '../domain/weekly_block.dart';

class ScheduleValidationIssue {
  const ScheduleValidationIssue({
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

abstract final class CourseScheduleValidator {
  static List<ScheduleValidationIssue> validate(
    CourseSchedule schedule, {
    bool requireOccurrence = true,
  }) {
    final issues = <ScheduleValidationIssue>[];
    if (schedule.timezone != CourseSchedule.academicTimezone) {
      issues.add(
        const ScheduleValidationIssue(
          code: 'unsupported_timezone',
          field: 'timezone',
          message: 'La zona horaria debe ser America/Bogota.',
        ),
      );
    }

    final rangeDays = schedule.startDate.daysUntil(schedule.endDate);
    if (rangeDays < 0) {
      issues.add(
        const ScheduleValidationIssue(
          code: 'end_before_start',
          field: 'endDate',
          message: 'La fecha final debe ser igual o posterior a la inicial.',
        ),
      );
    } else if (rangeDays > 365) {
      issues.add(
        const ScheduleValidationIssue(
          code: 'range_too_long',
          field: 'endDate',
          message: 'El curso puede abarcar máximo 366 días calendario.',
        ),
      );
    }

    if (schedule.weeklyBlocks.isEmpty || schedule.weeklyBlocks.length > 8) {
      issues.add(
        const ScheduleValidationIssue(
          code: 'block_count',
          field: 'weeklyBlocks',
          message: 'Agrega entre 1 y 8 bloques semanales.',
        ),
      );
    }

    final seenIds = <String>{};
    final validBlocks = <({WeeklyBlock block, int start, int end})>[];
    for (var index = 0; index < schedule.weeklyBlocks.length; index++) {
      final block = schedule.weeklyBlocks[index];
      final field = 'weeklyBlocks[$index]';
      if (!RegExp(r'^[A-Za-z0-9_-]{20,40}$').hasMatch(block.id)) {
        issues.add(
          ScheduleValidationIssue(
            code: 'invalid_block_id',
            field: '$field.id',
            message: 'El bloque no tiene un identificador estable válido.',
            blockId: block.id,
          ),
        );
      }
      if (!seenIds.add(block.id)) {
        issues.add(
          ScheduleValidationIssue(
            code: 'duplicate_block_id',
            field: '$field.id',
            message: 'Cada bloque debe tener un identificador distinto.',
            blockId: block.id,
          ),
        );
      }
      if (block.weekday < 1 || block.weekday > 7) {
        issues.add(
          ScheduleValidationIssue(
            code: 'invalid_weekday',
            field: '$field.weekday',
            message: 'Selecciona un día de la semana válido.',
            blockId: block.id,
          ),
        );
      }
      final start = block.startMinutes;
      final end = block.endMinutes;
      if (start == null || end == null) {
        issues.add(
          ScheduleValidationIssue(
            code: 'invalid_time',
            field: field,
            message: 'Usa horas válidas en formato HH:mm.',
            blockId: block.id,
          ),
        );
      } else if (end <= start) {
        issues.add(
          ScheduleValidationIssue(
            code: 'invalid_time_range',
            field: field,
            message: 'La hora final debe ser posterior a la inicial.',
            blockId: block.id,
          ),
        );
      } else if (block.weekday >= 1 && block.weekday <= 7) {
        validBlocks.add((block: block, start: start, end: end));
      }

      final room = WeeklyBlock.normalizeRoom(block.room);
      if (room != null && room.length > 60) {
        issues.add(
          ScheduleValidationIssue(
            code: 'room_too_long',
            field: '$field.room',
            message: 'El aula puede tener máximo 60 caracteres.',
            blockId: block.id,
          ),
        );
      }
    }

    for (var leftIndex = 0; leftIndex < validBlocks.length; leftIndex++) {
      final left = validBlocks[leftIndex];
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < validBlocks.length;
        rightIndex++
      ) {
        final right = validBlocks[rightIndex];
        if (left.block.weekday != right.block.weekday) continue;
        final isDuplicate =
            left.start == right.start &&
            left.end == right.end &&
            WeeklyBlock.normalizeRoom(left.block.room) ==
                WeeklyBlock.normalizeRoom(right.block.room);
        if (isDuplicate) {
          issues.add(
            ScheduleValidationIssue(
              code: 'duplicate_block',
              field: 'weeklyBlocks',
              message: 'Hay bloques semanales repetidos.',
              blockId: right.block.id,
            ),
          );
        } else if (left.start < right.end && right.start < left.end) {
          issues.add(
            ScheduleValidationIssue(
              code: 'overlapping_blocks',
              field: 'weeklyBlocks',
              message: 'Dos bloques del mismo día se superponen.',
              blockId: right.block.id,
            ),
          );
        }
      }
    }

    final dateRangeValid = rangeDays >= 0 && rangeDays <= 365;
    final blocksValid =
        schedule.weeklyBlocks.isNotEmpty &&
        schedule.weeklyBlocks.length <= 8 &&
        validBlocks.length == schedule.weeklyBlocks.length &&
        issues.isEmpty;
    if (requireOccurrence && dateRangeValid && blocksValid) {
      final meetings = generatePlannedMeetings(
        courseId: 'validation-course-id',
        schedule: schedule,
      );
      if (meetings.isEmpty) {
        issues.add(
          const ScheduleValidationIssue(
            code: 'no_occurrences',
            field: 'weeklyBlocks',
            message: 'El rango no contiene encuentros para los días elegidos.',
          ),
        );
      }
    }
    return List.unmodifiable(issues);
  }
}
