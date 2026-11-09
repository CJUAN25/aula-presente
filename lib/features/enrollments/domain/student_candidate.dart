/// Basic identity that a verified student has published for exact-email lookup.
class StudentCandidate {
  const StudentCandidate({
    required this.uid,
    required this.name,
    required this.email,
    required this.studentCode,
  });

  final String uid;
  final String name;
  final String email;
  final String? studentCode;
}
