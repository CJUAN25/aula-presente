enum CourseInvitationState { active, paused, inactive }

class CourseInvitation {
  const CourseInvitation({
    required this.courseId,
    required this.code,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.validity = defaultValidity,
  });

  static const defaultValidity = Duration(days: 14);
  static const minValidity = Duration(hours: 1);
  static const maxValidity = Duration(days: 90);

  final String courseId;
  final String code;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Duration validity;

  DateTime? get expiresAt => createdAt?.add(validity);

  /// Mirrors the persisted state only. Expiration is enforced by Firestore
  /// using server time and cannot be inferred from the device clock.
  CourseInvitationState get state => switch (status) {
    'active' => CourseInvitationState.active,
    'paused' => CourseInvitationState.paused,
    _ => CourseInvitationState.inactive,
  };

  String get groupedCode =>
      '${code.substring(0, 4)}-${code.substring(4, 8)}-'
      '${code.substring(8, 12)}-${code.substring(12, 16)}';
}
