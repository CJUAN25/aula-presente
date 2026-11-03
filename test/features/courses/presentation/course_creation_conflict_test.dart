import 'dart:async';
import 'dart:convert';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/courses/domain/course_creation_result.dart';
import 'package:aula_presente/features/courses/domain/course_cursor.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/courses/domain/course_page.dart';
import 'package:aula_presente/features/courses/domain/course_repository.dart';
import 'package:aula_presente/features/courses/presentation/course_creation_flow.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Monday and Friday selections retain ISO days and times when saved',
    (tester) async {
      final repository = _Repository();
      await _openReview(
        tester,
        repository,
        weekday: 1,
        endDateText: '10/30/2026',
      );
      await _tapVisible(tester, find.text('Volver a corregir'));
      await tester.tap(find.byTooltip('Opciones del horario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await _enterTime(tester, find.text('Fin 09:00'), '10');
      await _tapVisible(tester, find.text('Guardar cambios'));

      await _tapVisible(tester, find.text('Agregar otro día'));
      await tester.tap(find.text('Lunes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viernes').last);
      await tester.pumpAndSettle();
      await _enterTime(tester, find.text('Inicio 08:00'), '6');
      await _enterTime(tester, find.text('Fin 09:00'), '10');
      await _tapVisible(tester, find.text('Agregar horario'));
      await _tapVisible(tester, find.text('Revisar calendario'));
      expect(find.text('Lunes · 08:00–10:00'), findsOneWidget);
      expect(find.text('Viernes · 06:00–10:00'), findsOneWidget);
      await _tapVisible(tester, find.text('Crear curso'));

      final blocks = repository.savedDraft!.canonicalWeeklyBlockDocuments.values
          .toList();
      expect(repository.createCalls, 1);
      expect(blocks.map((b) => b['weekday']), [1, 5]);
      expect(blocks.map((b) => b['startMinute']), [480, 360]);
      expect(blocks.map((b) => b['endMinute']), [600, 600]);
    },
  );

  testWidgets('different weekdays save without the conflict dialog', (
    tester,
  ) async {
    final repository = _Repository()..courses = [_existingMonday()];
    await _openReview(tester, repository, weekday: 2);

    await _tapVisible(tester, find.text('Crear curso'), settle: false);
    await tester.pumpAndSettle();

    expect(find.text('Horario en conflicto'), findsNothing);
    expect(repository.createCalls, 1);
  });

  testWidgets('a true overlap warns; editing the draft clears it', (
    tester,
  ) async {
    final repository = _Repository()..courses = [_existingMonday()];
    await _openReview(tester, repository, weekday: 1);

    await _tapVisible(tester, find.text('Crear curso'), settle: false);
    expect(find.text('Horario en conflicto'), findsOneWidget);
    expect(find.textContaining('1 encuentro que coincide'), findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.tap(find.text('Volver al borrador'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Volver a corregir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones del horario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Martes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Revisar calendario'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Crear curso'));
    await tester.pumpAndSettle();

    expect(find.text('Horario en conflicto'), findsNothing);
    expect(repository.createCalls, 1);
  });

  testWidgets(
    'a failed agenda read does not save as if there were no conflicts',
    (tester) async {
      final repository = _Repository()..failRead = true;
      await _openReview(tester, repository, weekday: 2);

      await _tapVisible(tester, find.text('Crear curso'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos confirmar el curso'), findsOneWidget);
      expect(repository.createCalls, 0);
    },
  );

  testWidgets('confirming a real conflict creates the course once', (
    tester,
  ) async {
    final repository = _Repository()..courses = [_existingMonday()];
    await _openReview(tester, repository, weekday: 1);

    await _tapVisible(tester, find.text('Crear curso'), settle: false);
    expect(find.text('Horario en conflicto'), findsOneWidget);
    await tester.tap(find.text('Crear de todos modos'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
  });

  testWidgets('debug check exports the compared schedules without saving', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repository = _Repository()..courses = [_existingMonday()];
    await _openReview(tester, repository, weekday: 2);
    await _tapVisible(tester, find.text('Diagnosticar sin guardar (debug)'));

    expect(find.text('Diagnóstico de horarios'), findsOneWidget);
    final report = _diagnostic(tester);
    expect(report['existingCourseCount'], 1);
    expect(report['affectedCandidateMeetingCount'], 0);
    expect(report['candidate']['blocks'].single['weekdayIso'], 2);
    expect(report['existingCourses'].single['blocks'].single['weekdayIso'], 1);
    expect(repository.createCalls, 0);
    expect(repository.readCalls, 1);
    await tester.tap(find.text('Copiar diagnóstico'));
    await tester.pumpAndSettle();
    expect(jsonDecode(copied!), report);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Lógica'), findsOneWidget);
    expect(find.text('Crear curso'), findsOneWidget);
  });

  testWidgets(
    'dialog diagnostic is the exact evaluation that triggered its count',
    (tester) async {
      final repository = _Repository()..courses = [_existingMonday()];
      await _openReview(tester, repository, weekday: 1);
      await _tapVisible(tester, find.text('Crear curso'), settle: false);
      // A later repository change must not replace the evidence for this dialog.
      repository.courses = [];
      await tester.tap(find.text('Ver diagnóstico'));
      await tester.pumpAndSettle();

      final report = _diagnostic(tester);
      expect(report['existingCourseCount'], 1);
      expect(report['affectedCandidateMeetingCount'], 1);
      expect(report['overlapPairs'].single['existing']['date'], '2026-10-26');
      expect(repository.readCalls, 1);
      expect(repository.createCalls, 0);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Volver al borrador'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('closing a pending check cannot open diagnostics or save later', (
    tester,
  ) async {
    final pending = Completer<List<Course>>();
    final repository = _Repository()..pendingRead = pending;
    await _openReview(tester, repository, weekday: 2);
    await _tapVisible(
      tester,
      find.text('Diagnosticar sin guardar (debug)'),
      settle: false,
    );
    await tester.pumpWidget(const MaterialApp(home: Text('Session closed')));
    pending.complete([_existingMonday()]);
    await tester.pumpAndSettle();

    expect(find.text('Session closed'), findsOneWidget);
    expect(find.text('Diagnóstico de horarios'), findsNothing);
    expect(repository.createCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _diagnostic(WidgetTester tester) =>
    jsonDecode(tester.widget<SelectableText>(find.byType(SelectableText)).data!)
        as Map<String, dynamic>;

Future<void> _openReview(
  WidgetTester tester,
  _Repository repository, {
  required int weekday,
  String endDateText = '10/27/2026',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: CourseCreationFlow(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Lógica');
  await tester.enterText(fields.at(1), '01');
  await tester.enterText(fields.at(2), '2026-2');
  await tester.enterText(fields.at(3), 'Ingeniería');
  await tester.tap(find.text('Definir calendario'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Elegir fechas'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined).last);
  await tester.pumpAndSettle();
  final dateFields = find.byType(TextField);
  await tester.enterText(dateFields.at(0), '10/26/2026');
  await tester.enterText(dateFields.at(1), endDateText);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await _tapVisible(tester, find.text('Agregar día y horario'));
  await tester.pumpAndSettle();
  if (weekday != 1) {
    await tester.tap(find.text('Lunes').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(
            const [
              'Lunes',
              'Martes',
              'Miércoles',
              'Jueves',
              'Viernes',
              'Sábado',
              'Domingo',
            ][weekday - 1],
          )
          .last,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Agregar horario'));
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.text('Revisar calendario'));
  await tester.pumpAndSettle();
  expect(find.text('Revisar calendario'), findsWidgets);
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _enterTime(WidgetTester tester, Finder button, String hour) async {
  await _tapVisible(tester, button);
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(0), hour);
  await tester.enterText(find.byType(TextFormField).at(1), '00');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Course _existingMonday() => Course(
  id: 'existingcourse00000001',
  ownerUid: 'teacher',
  subject: 'Móvil',
  group: '01',
  period: '2026-2',
  program: 'Ingeniería',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 10, day: 26),
    endDate: AcademicDate(year: 2026, month: 10, day: 27),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'existingmondayblock0001',
        weekday: 1,
        startTime: '08:00',
        endTime: '09:00',
      ),
    ],
  ),
);

class _Repository implements CourseRepository {
  List<Course> courses = [];
  bool failRead = false;
  int createCalls = 0;
  int readCalls = 0;
  CourseDraft? savedDraft;
  Completer<List<Course>>? pendingRead;

  @override
  Future<List<Course>> getAllOwnCourses({int pageSize = 25}) async {
    readCalls++;
    if (failRead) throw StateError('offline');
    if (pendingRead != null) return pendingRead!.future;
    return courses;
  }

  @override
  Future<CoursePage> getOwnCoursePage({
    CourseCursor? cursor,
    int pageSize = 25,
  }) async => CoursePage(items: courses, nextCursor: null);

  @override
  Future<CourseCreationResult> createCourse(CourseDraft draft) async {
    createCalls++;
    savedDraft = draft;
    return CourseCreationResult(
      course: Course(
        id: draft.id,
        ownerUid: 'teacher',
        subject: draft.subject,
        group: draft.group,
        period: draft.period,
        program: draft.program,
        schedule: draft.schedule,
      ),
      wasAlreadyCreated: false,
    );
  }
}
