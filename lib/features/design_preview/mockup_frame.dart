enum MockupRole { student, teacher, shared, admin }

extension MockupRoleLabel on MockupRole {
  String get label => switch (this) {
    MockupRole.student => 'Estudiante',
    MockupRole.teacher => 'Docente',
    MockupRole.shared => 'Compartido',
    MockupRole.admin => 'Administración',
  };
}

class MockupFrame {
  const MockupFrame({
    required this.page,
    required this.title,
    required this.role,
    required this.route,
    required this.connected,
    required this.section,
  });

  factory MockupFrame.fromTsv(String row) {
    final values = row.split('\t');
    return MockupFrame(
      page: int.parse(values[0]),
      role: MockupRole.values.byName(values[1]),
      title: values[2],
      route: values[3],
      connected: values[4] == 'true',
      section: values[5],
    );
  }

  final int page;
  final String title;
  final MockupRole role;
  final String route;
  final bool connected;
  final String section;

  String get pageLabel => 'PDF p. ${page.toString().padLeft(3, '0')}';
}
