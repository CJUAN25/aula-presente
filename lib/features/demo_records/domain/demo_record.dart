class DemoRecord {
  const DemoRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestore document ID. It is not stored as a field in the document.
  final String id;
  final String title;
  final String description;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
