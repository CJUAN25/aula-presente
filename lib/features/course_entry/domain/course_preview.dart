class CoursePreview {
  const CoursePreview({
    required this.courseId,
    required this.subject,
    required this.group,
    required this.period,
    required this.code,
    this.expiresAt,
  });

  final String courseId;
  final String subject;
  final String group;
  final String period;
  final String code;
  // Public lookup does not expose the private lifetime configuration.
  final DateTime? expiresAt;
}
