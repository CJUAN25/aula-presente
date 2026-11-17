import 'package:aula_presente/features/attendance/domain/attendance_justification_request.dart';
import 'package:aula_presente/features/attendance/domain/attendance_repository.dart';
import 'package:aula_presente/features/attendance/domain/attendance_calendar_change.dart';

class CalendarAttendanceStub implements AttendanceRepository {
  CalendarAttendanceStub([this.changes = const []]);
  final List<AttendanceCalendarChange> changes;
  @override
  Future<List<AttendanceCalendarChange>> listCalendarChanges({
    required String courseId,
    bool forStudent = false,
  }) async => changes;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listJustificationRequests) return Future<List<AttendanceJustificationRequest>>.value([]);
    if (invocation.memberName == #getMyJustification) return Future<AttendanceJustificationRequest?>.value(null);
    return super.noSuchMethod(invocation);
  }
}
