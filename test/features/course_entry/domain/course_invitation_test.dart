import 'package:aula_presente/features/course_entry/domain/course_invitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active invitation can await its server expiry readback', () {
    const invitation = CourseInvitation(
      courseId: 'course-1',
      code: 'ABCD2345EFGHJKMN',
      status: 'active',
      createdAt: null,
      updatedAt: null,
    );
    expect(invitation.state, CourseInvitationState.active);
    expect(invitation.expiresAt, isNull);
  });

  test('expiry is derived from confirmed creation exactly 14 days later', () {
    final createdAt = DateTime.utc(2026, 11, 1, 12, 30);
    const invitation = CourseInvitation(
      courseId: 'course-1',
      code: 'ABCD2345EFGHJKMN',
      status: 'active',
      createdAt: null,
      updatedAt: null,
    );
    final actual = CourseInvitation(
      courseId: invitation.courseId,
      code: invitation.code,
      status: invitation.status,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    expect(actual.expiresAt, createdAt.add(const Duration(days: 14)));
    expect(actual.state, CourseInvitationState.active);
    expect(actual.expiresAt, createdAt.add(const Duration(days: 14)));
  });

  test('stored status does not change with a device clock skew', () {
    final createdLongAgo = DateTime(2000, 1, 1);
    final createdFarInFuture = DateTime(2099, 1, 1);
    final oldInvitation = CourseInvitation(
      courseId: 'course-1',
      code: 'ABCD2345EFGHJKMN',
      status: 'active',
      createdAt: createdLongAgo,
      updatedAt: createdLongAgo,
    );
    final futureInvitation = CourseInvitation(
      courseId: 'course-1',
      code: 'ABCD2345EFGHJKMN',
      status: 'active',
      createdAt: createdFarInFuture,
      updatedAt: createdFarInFuture,
    );

    expect(oldInvitation.state, CourseInvitationState.active);
    expect(futureInvitation.state, CourseInvitationState.active);
    expect(
      oldInvitation.expiresAt,
      createdLongAgo.add(const Duration(days: 14)),
    );
    expect(
      futureInvitation.expiresAt,
      createdFarInFuture.add(const Duration(days: 14)),
    );
  });

  test('inactive invitation remains inactive regardless of its date', () {
    final createdAt = DateTime(2099, 1, 1);
    final invitation = CourseInvitation(
      courseId: 'course-1',
      code: 'ABCD2345EFGHJKMN',
      status: 'inactive',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    expect(invitation.state, CourseInvitationState.inactive);
    expect(invitation.groupedCode, 'ABCD-2345-EFGH-JKMN');
  });
}
