import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/presentation/enrollment_components.dart';
import '../application/excel_import_coordinator.dart';
import '../data/device_excel_import_reader.dart';
import '../domain/excel_import_document.dart';
import '../domain/excel_import_review.dart';

enum _ImportStep { file, columns, review, selection, confirmation, result }

/// The selected course is the only destination. Reading and reviewing the
/// workbook cannot create an enrollment; only the final confirmation can.
class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({
    super.key,
    required this.course,
    required this.repository,
    this.reader,
  });

  final Course course;
  final EnrollmentRepository repository;
  final ExcelImportReader? reader;

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  late final ExcelImportCoordinator _coordinator;
  late final ExcelImportReader _reader;
  _ImportStep _step = _ImportStep.file;
  ExcelImportDocument? _document;
  ExcelImportSheet? _sheet;
  ExcelReview? _review;
  ExcelImportResult? _result;
  final Set<int> _selectedRows = {};
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _coordinator = ExcelImportCoordinator(widget.repository);
    _reader = widget.reader ?? DeviceExcelImportReader();
  }

  String get _destination =>
      '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}';

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final document = await _reader.pickAndRead();
      if (!mounted || document == null) return;
      setState(() {
        _document = document;
        _sheet = document.sheets.length == 1 ? document.sheets.first : null;
        _review = null;
        _result = null;
        _selectedRows.clear();
        _step = _ImportStep.columns;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewRows() async {
    final sheet = _sheet;
    if (_busy || sheet == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _selectedRows.clear();
    });
    try {
      final review = await _coordinator.review(
        course: widget.course,
        sheet: sheet,
      );
      if (!mounted) return;
      setState(() {
        _review = review;
        _result = null;
        _step = _ImportStep.review;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final review = _review;
    if (_busy || review == null || _selectedRows.isEmpty) return;
    final selected = review.rows
        .where(
          (row) => row.selectable && _selectedRows.contains(row.row.rowNumber),
        )
        .toList(growable: false);
    if (selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _coordinator.confirm(
        course: widget.course,
        selected: selected,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _ImportStep.result;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_busy) return;
    setState(() => _error = null);
    switch (_step) {
      case _ImportStep.file:
        Navigator.of(context).maybePop();
        return;
      case _ImportStep.columns:
        setState(() => _step = _ImportStep.file);
        return;
      case _ImportStep.review:
        setState(() => _step = _ImportStep.columns);
        return;
      case _ImportStep.selection:
        setState(() => _step = _ImportStep.review);
        return;
      case _ImportStep.confirmation:
        setState(() => _step = _ImportStep.selection);
        return;
      case _ImportStep.result:
        Navigator.of(context).pop(true);
        return;
    }
  }

  void _toggle(int rowNumber) => setState(() {
    if (!_selectedRows.add(rowNumber)) _selectedRows.remove(rowNumber);
  });

  String get _title => switch (_step) {
    _ImportStep.file => 'Importar Excel',
    _ImportStep.columns => 'Columnas del Excel',
    _ImportStep.review => 'Revisar importación',
    _ImportStep.selection => 'Seleccionar altas del Excel',
    _ImportStep.confirmation => 'Confirmar importación',
    _ImportStep.result => 'Importación completada',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.repository.currentUid != widget.course.ownerUid) {
      return const CoursePage(
        title: 'Importar Excel',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    return PopScope(
      canPop: !_busy,
      child: CoursePage(
        title: _title,
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: _busy ? null : _back,
          icon: const Icon(Icons.arrow_back),
        ),
        bottomNavigationBar: _bottomAction(),
        child: CourseContent(
          key: ValueKey(_step),
          children: [
            ..._content(),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              CourseStateCard(
                title: 'No pudimos continuar',
                message: _errorMessage(_error!),
                icon: Icons.error_outline,
                color: AppColors.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is ExcelImportException) return error.message;
    return enrollmentErrorMessage(error);
  }

  Widget? _bottomAction() {
    final Widget? action = switch (_step) {
      _ImportStep.file => null,
      _ImportStep.columns => CoursePrimaryButton(
        label: 'Revisar coincidencias',
        onPressed: _busy || _sheet == null || _sheet!.rows.isEmpty
            ? null
            : _reviewRows,
        busy: _busy,
      ),
      _ImportStep.review => CoursePrimaryButton(
        label: 'Seleccionar estudiantes',
        onPressed: _busy || (_review?.eligibleCount ?? 0) == 0
            ? null
            : () => setState(() => _step = _ImportStep.selection),
      ),
      _ImportStep.selection => CoursePrimaryButton(
        label: 'Revisar selección',
        onPressed: _busy || _selectedRows.isEmpty
            ? null
            : () => setState(() => _step = _ImportStep.confirmation),
      ),
      _ImportStep.confirmation => CoursePrimaryButton(
        label: 'Confirmar inscripciones',
        onPressed: _busy ? null : _confirm,
        busy: _busy,
      ),
      _ImportStep.result => CoursePrimaryButton(
        label: 'Ver estudiantes',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    };
    if (action == null) return null;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: action,
        ),
      ),
    );
  }

  List<Widget> _content() => switch (_step) {
    _ImportStep.file => _fileContent(),
    _ImportStep.columns => _columnsContent(),
    _ImportStep.review => _reviewContent(),
    _ImportStep.selection => _selectionContent(),
    _ImportStep.confirmation => _confirmationContent(),
    _ImportStep.result => _resultContent(),
  };

  Widget _destinationTile() => EnrollmentTile(
    title: 'Destino de importación',
    subtitle: _destination,
    iconAsset: '51a24.svg',
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: CoursePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: AppColors.text, fontSize: 16),
          ),
        ],
      ),
    ),
  );

  List<Widget> _fileContent() => [
    const CoursePageHeading(title: 'Carga la lista del curso.'),
    const SizedBox(height: 16),
    _destinationTile(),
    _field(
      'Archivo',
      _document?.fileName ?? 'Selecciona un archivo .xls o .xlsx',
    ),
    SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: _busy ? null : _pickFile,
        icon: SvgPicture.asset('assets/figma/18f6c.svg', width: 24, height: 24),
        label: Text(_document == null ? 'Seleccionar Excel' : 'Cambiar Excel'),
      ),
    ),
    const SizedBox(height: 16),
    const CourseStateCard(
      title: 'Solo datos necesarios',
      message: 'Se usan código estudiantil, correo y nombre. Documento, teléfono, EPS y otras columnas no se importan. Las filas ausentes no se retiran.',
      icon: Icons.info_outline,
    ),
    const SizedBox(height: 12),
    const CourseStateCard(
      title: 'Sin escrituras al revisar',
      message:
          'Puedes salir antes de confirmar; aún no se crea ninguna matrícula.',
      icon: Icons.preview_outlined,
    ),
  ];

  List<Widget> _columnsContent() {
    final document = _document!;
    final sheet = _sheet;
    return [
      const CoursePageHeading(title: 'Reconocimos tu archivo.'),
      const SizedBox(height: 8),
      Text(document.fileName, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      for (final warning in document.warnings) ...[
        CourseStateCard(
          title: 'Hoja omitida',
          message: warning,
          icon: Icons.warning_amber_outlined,
        ),
        const SizedBox(height: 12),
      ],
      if (document.sheets.length > 1) ...[
        CoursePanel(
          child: DropdownButtonFormField<ExcelImportSheet>(
            key: ValueKey('${document.fileName}:${sheet?.name}'),
            initialValue: sheet,
            decoration: const InputDecoration(labelText: 'Hoja del curso'),
            items: [
              for (final item in document.sheets)
                DropdownMenuItem(
                  value: item,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _sheet = value;
                    _review = null;
                  }),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (sheet != null) ...[
        Text(
          '${sheet.name} · ${sheet.rows.length} filas',
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 16),
        if (sheet.rows.isEmpty) ...[
          const CourseStateCard(
            title: 'Hoja sin estudiantes',
            message: 'La hoja tiene encabezados, pero no contiene filas para revisar. Elige otra hoja o selecciona otro archivo.',
            icon: Icons.table_rows_outlined,
          ),
          const SizedBox(height: 16),
        ],
        _field(
          'Código estudiantil',
          sheet.columnMapping['studentCode'] ?? 'No reconocido',
        ),
        _field(
          'Correo institucional',
          sheet.columnMapping['email'] ?? 'No reconocido',
        ),
        _field(
          'Nombre completo',
          sheet.columnMapping['name'] ?? 'No reconocido',
        ),
        _field('Ingreso al curso', 'Al confirmar'),
        const CourseStateCard(
          title: 'Fecha de matrícula',
          message: 'FECHAMATRICULA no se usa automáticamente como ingreso a esta materia. La fecha efectiva la fija el servidor al confirmar.',
          icon: Icons.info_outline,
        ),
      ] else
        const CourseStateCard(
          title: 'Elige una hoja',
          message: 'Hay varias hojas compatibles. Selecciona la que pertenece a este curso antes de revisar.',
          icon: Icons.table_chart_outlined,
        ),
    ];
  }

  Widget _indicator(String value, String label) => SizedBox(
    width: 104,
    child: CoursePanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  List<Widget> _reviewContent() {
    final rows = _review!.rows;
    final eligible = _review!.eligibleCount;
    final unavailable = rows
        .where((row) => row.status == ExcelReviewStatus.unavailable)
        .length;
    final conflicts = rows.length - eligible - unavailable;
    return [
      const CoursePageHeading(title: 'Comprueba tu lista.'),
      const SizedBox(height: 16),
      _destinationTile(),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _indicator('$eligible', 'Listas'),
          _indicator('$unavailable', 'Sin cuenta'),
          _indicator('$conflicts', 'Otros estados'),
        ],
      ),
      const SizedBox(height: 16),
      const CourseStateCard(
        title: 'Coincidencias verificadas',
        message: 'Código y correo coinciden con la cuenta publicada. El nombre ayuda a identificar; no vincula cuentas.',
        icon: Icons.verified_outlined,
      ),
      const SizedBox(height: 16),
      if (rows.isEmpty)
        const CourseStateCard(
          title: 'Lista vacía',
          message: 'No hay filas con datos para revisar.',
          icon: Icons.table_rows_outlined,
        ),
      for (final row in rows) _reviewTile(row),
      if (eligible == 0) ...[
        const CourseStateCard(
          title: 'No hay altas elegibles',
          message: 'Revisa los motivos de cada fila. Puedes corregir el archivo o volver a importarlo más adelante.',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 12),
      ],
      CourseSecondaryButton(
        label: 'Volver sin importar',
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
      ),
    ];
  }

  Widget _reviewTile(ExcelReviewedRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: CoursePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fila ${row.row.rowNumber} · ${row.row.name.isEmpty ? 'Sin nombre' : row.row.name}',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${row.row.studentCode} · ${row.row.email}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            row.message,
            style: TextStyle(
              color: row.selectable ? AppColors.primary : AppColors.information,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _selectionContent() {
    final rows = _review!.rows;
    final eligible = rows
        .where((row) => row.selectable)
        .toList(growable: false);
    return [
      CoursePageHeading(
        title: 'Elige quién ingresa.',
        description: _document?.fileName,
      ),
      const SizedBox(height: 16),
      _indicator('${_selectedRows.length}', 'Seleccionadas'),
      const SizedBox(height: 16),
      CourseSecondaryButton(
        label: 'Seleccionar todas las elegibles',
        onPressed: _busy
            ? null
            : () => setState(
                () => _selectedRows.addAll(
                  eligible.map((row) => row.row.rowNumber),
                ),
              ),
      ),
      const SizedBox(height: 12),
      CourseSecondaryButton(
        label: 'Desmarcar todas',
        onPressed: _busy ? null : () => setState(_selectedRows.clear),
      ),
      const SizedBox(height: 16),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CoursePanel(
            child: Row(
              children: [
                Checkbox(
                  value: _selectedRows.contains(row.row.rowNumber),
                  onChanged: row.selectable && !_busy
                      ? (_) => _toggle(row.row.rowNumber)
                      : null,
                  semanticLabel: 'Seleccionar fila ${row.row.rowNumber}',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fila ${row.row.rowNumber} · ${row.row.name.isEmpty ? 'Sin nombre' : row.row.name}',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        row.message,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_selectedRows.isEmpty)
        const CourseStateCard(
          title: 'Selecciona al menos una alta',
          message: 'Solo se pueden confirmar las filas listas para matricular.',
          icon: Icons.info_outline,
        ),
    ];
  }

  List<Widget> _confirmationContent() {
    final rows = _review!.rows
        .where((row) => _selectedRows.contains(row.row.rowNumber))
        .toList();
    return [
      const CoursePageHeading(title: 'Comprueba las altas.'),
      const SizedBox(height: 16),
      _destinationTile(),
      _indicator('${rows.length}', 'Por agregar'),
      const SizedBox(height: 16),
      _field('Ingreso efectivo', 'Al confirmar'),
      const CourseStateCard(
        title: 'Confirmación por estudiante',
        message: 'Cada alta se verifica de nuevo antes de guardarse. Si alguna falla, las demás pueden quedar confirmadas.',
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 16),
      for (final row in rows)
        EnrollmentTile(
          title: row.candidate?.name ?? row.row.name,
          subtitle:
              'Fila ${row.row.rowNumber} · ${row.row.studentCode} · Agregar al curso',
          iconAsset: '51a24.svg',
        ),
      CourseSecondaryButton(
        label: 'Volver a la selección',
        onPressed: _busy ? null : _back,
      ),
    ];
  }

  List<Widget> _resultContent() {
    final rows = _result!.rows;
    final untouched = _review!.rows
        .where((row) => !_selectedRows.contains(row.row.rowNumber))
        .toList(growable: false);
    int count(ExcelImportOutcome outcome) =>
        rows.where((row) => row.outcome == outcome).length;
    int untouchedCount(ExcelReviewStatus status) =>
        untouched.where((row) => row.status == status).length;
    final enrolled = count(ExcelImportOutcome.enrolledNow);
    final already =
        count(ExcelImportOutcome.alreadyEnrolled) +
        untouchedCount(ExcelReviewStatus.alreadyEnrolled);
    final withdrawn =
        count(ExcelImportOutcome.withdrawn) +
        untouchedCount(ExcelReviewStatus.withdrawn);
    final needsReview =
        count(ExcelImportOutcome.needsReview) +
        untouched
            .where(
              (row) =>
                  row.status != ExcelReviewStatus.eligible &&
                  row.status != ExcelReviewStatus.alreadyEnrolled &&
                  row.status != ExcelReviewStatus.withdrawn,
            )
            .length;
    return [
      CoursePageHeading(
        title: enrolled > 0
            ? 'Inscripciones confirmadas.'
            : 'Resultado de la importación.',
        description: _destination,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _indicator('$enrolled', 'Matriculadas ahora'),
          _indicator('$already', 'Ya inscritas'),
          _indicator('$withdrawn', 'Retiradas'),
          _indicator('$needsReview', 'Por revisar'),
          _indicator('${count(ExcelImportOutcome.failed)}', 'Sin confirmar'),
          _indicator(
            '${untouchedCount(ExcelReviewStatus.eligible)}',
            'No elegidas',
          ),
        ],
      ),
      const SizedBox(height: 16),
      const CourseStateCard(
        title: 'Resultado por fila',
        message: 'Una cuenta sin entrada disponible puede revisarse al importar otra vez después de registrarse, verificar su correo y abrir el espacio Estudiante. No se guarda una reserva.',
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 16),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CoursePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fila ${row.reviewed.row.rowNumber} · ${row.reviewed.row.name}',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  row.message,
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      if (untouched.isNotEmpty) ...[
        const CourseSectionHeading(title: 'Filas sin escritura'),
        const SizedBox(height: 12),
        for (final row in untouched)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fila ${row.row.rowNumber} · ${row.row.name.isEmpty ? 'Sin nombre' : row.row.name}',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.selectable
                        ? 'No seleccionada; no se matriculó.'
                        : row.message,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      CourseSecondaryButton(
        label: 'Revisar de nuevo el archivo',
        onPressed: _busy ? null : _reviewRows,
      ),
      const SizedBox(height: 12),
      const CourseStateCard(
        title: 'Retirados',
        message: 'Una matrícula retirada conserva su historial. La reincorporación se hace desde la ficha del estudiante, fuera de esta importación.',
        icon: Icons.history,
      ),
    ];
  }
}
