import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../schedule/application/schedule_conflict_detector.dart';
import '../../schedule/application/schedule_conflict_diagnostic.dart';
import 'course_presentation_components.dart';

/// Only opened behind kDebugMode in the creation flow. It does not write data.
class CourseScheduleDiagnosticScreen extends StatelessWidget {
  const CourseScheduleDiagnosticScreen({super.key, required this.check});

  final ScheduleConflictCheck check;

  @override
  Widget build(BuildContext context) {
    final report = scheduleConflictDiagnostic(check);
    return CoursePage(
      title: 'Diagnóstico de horarios',
      child: CourseContent(
        children: [
          Text(
            '${check.existingCourses.length} cursos recuperados · '
            '${check.conflicts.length} encuentros afectados · '
            '${check.overlapPairs.length} parejas de coincidencias',
          ),
          const SizedBox(height: 12),
          const Text(
            'Solo lectura. Son los valores que recibió el comparador en esta '
            'comprobación, no una extracción de documentos sin procesar. '
            'Los cursos y bloques usan alias. El informe omite nombres, correos, '
            'UID, IDs reales, aulas y datos de acceso. Esta acción no guarda cursos.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar diagnóstico'),
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: report));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnóstico copiado.')),
                );
              } on PlatformException {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No se pudo copiar. Puedes seleccionar el texto.',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          SelectableText(
            report,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
