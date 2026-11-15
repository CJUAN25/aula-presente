import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/presentation/enrollment_components.dart';
import '../../schedule/domain/academic_date.dart';
import '../application/excel_import_coordinator.dart';
import '../data/device_excel_import_reader.dart';
import '../domain/excel_import_document.dart';
import '../domain/excel_import_review.dart';

enum _RosterUpdateStep {
  file,
  columns,
  review,
  additions,
  withdrawals,
  confirmation,
  noChanges,
  result,
}

/// Compare an Excel file with the complete course roster, explicitly select
/// the changes, then apply independent per-person transactions.
class ExcelRosterUpdateScreen extends StatefulWidget {
  const ExcelRosterUpdateScreen({
    super.key,
    required this.course,
    required this.repository,
    this.reader,
  });

  final Course course;
  final EnrollmentRepository repository;
  final ExcelImportReader? reader;

  @override
  State<ExcelRosterUpdateScreen> createState() =>
      _ExcelRosterUpdateScreenState();
}

class _ExcelRosterUpdateScreenState extends State<ExcelRosterUpdateScreen> {
  late final ExcelImportCoordinator _coordinator;
  late final ExcelImportReader _reader;
  _RosterUpdateStep _step = _RosterUpdateStep.file;
  ExcelImportMode _mode = ExcelImportMode.additionsOnly;
  ExcelImportDocument? _document;
  ExcelImportSheet? _sheet;
  ExcelReview? _review;
  ExcelImportResult? _result;
  AcademicDate? _effectiveStartDate;
  AcademicDate? _withdrawalEffectiveDate;
  final Set<int> _selectedRows = {};
  final Set<String> _selectedWithdrawals = {};
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _coordinator = ExcelImportCoordinator(widget.repository);
    _reader = widget.reader ?? DeviceExcelImportReader();
    _effectiveStartDate = _defaultStartDate(widget.course);
    _withdrawalEffectiveDate = _defaultWithdrawalDate(widget.course);
  }

  String get _destination =>
      '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}';

  List<ExcelReviewedRow> get _selectedRowsInReview {
    final review = _review;
    if (review == null) return const [];
    return review.rows
        .where(
          (row) => row.selectable && _selectedRows.contains(row.row.rowNumber),
        )
        .toList(growable: false);
  }

  List<ExcelRosterMember> get _selectedWithdrawalMembers {
    final review = _review;
    if (review == null) return const [];
    return review.potentialWithdrawals
        .where((member) => _selectedWithdrawals.contains(_memberKey(member)))
        .toList(growable: false);
  }

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
        _selectedWithdrawals.clear();
        _step = _RosterUpdateStep.columns;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewRows({ExcelImportMode? mode}) async {
    final sheet = _sheet;
    if (_busy || sheet == null) return;
    final selectedMode = mode ?? _mode;
    setState(() {
      _busy = true;
      _error = null;
      _selectedRows.clear();
      _selectedWithdrawals.clear();
    });
    try {
      final review = await _coordinator.review(
        course: widget.course,
        sheet: sheet,
        mode: selectedMode,
      );
      if (!mounted) return;
      setState(() {
        _mode = selectedMode;
        _review = review;
        _result = null;
        _step = _RosterUpdateStep.review;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseStartDate() async {
    final course = widget.course;
    final today = _todayBogota();
    final firstDate = course.schedule.startDate;
    final lastDate = today.compareTo(firstDate) < 0
        ? firstDate
        : _minimum(today, course.schedule.endDate);
    final initial = _clamp(
      _effectiveStartDate ?? _defaultStartDate(course),
      firstDate,
      lastDate,
    );
    final value = await showDatePicker(
      context: context,
      initialDate: _localDate(initial),
      firstDate: _localDate(firstDate),
      lastDate: _localDate(lastDate),
      helpText: 'Fecha de ingreso o reincorporación',
      cancelText: 'Cancelar',
      confirmText: 'Usar fecha',
    );
    if (mounted && value != null) {
      setState(() => _effectiveStartDate = AcademicDate.fromDateTime(value));
    }
  }

  Future<void> _chooseWithdrawalDate() async {
    final course = widget.course;
    final today = _todayBogota();
    final firstDate = today.compareTo(course.schedule.startDate) < 0
        ? today
        : course.schedule.startDate;
    final lastDate = _minimum(today, course.schedule.endDate);
    if (firstDate.compareTo(lastDate) > 0) {
      setState(() {
        _error = StateError(
          'No hay una fecha efectiva de retiro válida para este curso.',
        );
      });
      return;
    }
    final initial = _clamp(
      _withdrawalEffectiveDate ?? _defaultWithdrawalDate(course),
      firstDate,
      lastDate,
    );
    final value = await showDatePicker(
      context: context,
      initialDate: _localDate(initial),
      firstDate: _localDate(firstDate),
      lastDate: _localDate(lastDate),
      helpText: 'Fecha efectiva de retiro',
      cancelText: 'Cancelar',
      confirmText: 'Usar fecha',
    );
    if (mounted && value != null) {
      setState(
        () => _withdrawalEffectiveDate = AcademicDate.fromDateTime(value),
      );
    }
  }

  Future<void> _confirmChanges() async {
    if (_busy) return;
    final selected = _selectedRowsInReview;
    final selectedWithdrawals = _selectedWithdrawalMembers;
    if (selected.isEmpty && selectedWithdrawals.isEmpty) {
      setState(() => _step = _RosterUpdateStep.noChanges);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _coordinator.confirm(
        course: widget.course,
        selected: selected,
        review: _review,
        selectedWithdrawals: selectedWithdrawals,
        effectiveStartDate: _effectiveStartDate,
        withdrawalEffectiveDate: _withdrawalEffectiveDate,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _RosterUpdateStep.result;
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
      case _RosterUpdateStep.file:
        Navigator.of(context).maybePop(false);
        return;
      case _RosterUpdateStep.columns:
        setState(() => _step = _RosterUpdateStep.file);
        return;
      case _RosterUpdateStep.review:
        setState(() => _step = _RosterUpdateStep.columns);
        return;
      case _RosterUpdateStep.additions:
        setState(() => _step = _RosterUpdateStep.review);
        return;
      case _RosterUpdateStep.withdrawals:
        setState(() => _step = _RosterUpdateStep.additions);
        return;
      case _RosterUpdateStep.confirmation:
        setState(() {
          _step = _review?.retirementsAllowed == true
              ? _RosterUpdateStep.withdrawals
              : _RosterUpdateStep.additions;
        });
        return;
      case _RosterUpdateStep.noChanges:
        setState(() => _step = _RosterUpdateStep.additions);
        return;
      case _RosterUpdateStep.result:
        Navigator.of(context).pop(true);
        return;
    }
  }

  void _toggleRow(int rowNumber) => setState(() {
    if (!_selectedRows.add(rowNumber)) _selectedRows.remove(rowNumber);
  });

  void _toggleWithdrawal(ExcelRosterMember member) => setState(() {
    final key = _memberKey(member);
    if (!_selectedWithdrawals.add(key)) _selectedWithdrawals.remove(key);
  });

  String get _title => switch (_step) {
    _RosterUpdateStep.file => 'Importar Excel',
    _RosterUpdateStep.columns => 'Columnas del Excel',
    _RosterUpdateStep.review => 'Comparar actualización',
    _RosterUpdateStep.additions => 'Seleccionar cambios',
    _RosterUpdateStep.withdrawals => 'Seleccionar retiros',
    _RosterUpdateStep.confirmation => 'Confirmar actualización',
    _RosterUpdateStep.noChanges => 'Sin cambios seleccionados',
    _RosterUpdateStep.result => 'Actualización aplicada',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.repository.currentUid != widget.course.ownerUid) {
      return const CoursePage(
        title: 'Actualizar lista con Excel',
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
                message: enrollmentErrorMessage(_error),
                icon: Icons.error_outline,
                color: AppColors.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _bottomAction() {
    final review = _review;
    final selectedCount = _selectedRows.length + _selectedWithdrawals.length;
    final Widget? action = switch (_step) {
      _RosterUpdateStep.file => null,
      _RosterUpdateStep.columns => CoursePrimaryButton(
        label: 'Revisar cambios',
        onPressed: _busy || _sheet == null || _sheet!.rows.isEmpty
            ? null
            : () => _reviewRows(),
        busy: _busy,
      ),
      _RosterUpdateStep.review => CoursePrimaryButton(
        label: 'Seleccionar cambios',
        onPressed:
            _busy ||
                (review?.eligibleCount ?? 0) == 0 &&
                    (review?.potentialWithdrawals.isEmpty ?? true)
            ? null
            : () => setState(() => _step = _RosterUpdateStep.additions),
      ),
      _RosterUpdateStep.additions => CoursePrimaryButton(
        label:
            review?.retirementsAllowed == true &&
                review!.potentialWithdrawals.isNotEmpty
            ? 'Revisar posibles retiros'
            : 'Revisar cambios',
        onPressed: _busy
            ? null
            : () => setState(() {
                _step =
                    review?.retirementsAllowed == true &&
                        review!.potentialWithdrawals.isNotEmpty
                    ? _RosterUpdateStep.withdrawals
                    : _RosterUpdateStep.confirmation;
              }),
      ),
      _RosterUpdateStep.withdrawals => CoursePrimaryButton(
        label: 'Revisar selección',
        onPressed: _busy
            ? null
            : () => setState(() => _step = _RosterUpdateStep.confirmation),
      ),
      _RosterUpdateStep.confirmation => CoursePrimaryButton(
        label: selectedCount == 0
            ? 'Volver a seleccionar'
            : 'Confirmar cambios',
        onPressed: _busy
            ? null
            : selectedCount == 0
            ? () => setState(() => _step = _RosterUpdateStep.noChanges)
            : _confirmChanges,
        busy: _busy,
      ),
      _RosterUpdateStep.noChanges => CoursePrimaryButton(
        label: 'Revisar actualización',
        onPressed: _busy
            ? null
            : () => setState(() => _step = _RosterUpdateStep.review),
      ),
      _RosterUpdateStep.result => CoursePrimaryButton(
        label: 'Volver a Gestión de estudiantes',
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
    _RosterUpdateStep.file => _fileContent(),
    _RosterUpdateStep.columns => _columnsContent(),
    _RosterUpdateStep.review => _reviewContent(),
    _RosterUpdateStep.additions => _additionsContent(),
    _RosterUpdateStep.withdrawals => _withdrawalsContent(),
    _RosterUpdateStep.confirmation => _confirmationContent(),
    _RosterUpdateStep.noChanges => _noChangesContent(),
    _RosterUpdateStep.result => _resultContent(),
  };

  Widget _destinationTile() => EnrollmentTile(
    title: 'Destino del curso',
    subtitle: _destination,
    iconAsset: '51a24.svg',
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: CoursePanel(
      padding: const EdgeInsets.all(16),
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
    const SizedBox(height: 18),
    const Text(
      '¿Qué quieres hacer?',
      style: TextStyle(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Solo agregar estudiantes'),
          selected: _mode == ExcelImportMode.additionsOnly,
          onSelected: _busy
              ? null
              : (_) => setState(() => _mode = ExcelImportMode.additionsOnly),
        ),
        ChoiceChip(
          label: const Text('Comparar lista completa'),
          selected: _mode == ExcelImportMode.completeList,
          onSelected: _busy
              ? null
              : (_) => setState(() => _mode = ExcelImportMode.completeList),
        ),
      ],
    ),
    const SizedBox(height: 12),
    CourseStateCard(
      title: _mode == ExcelImportMode.additionsOnly
          ? 'La lista actual no cambia'
          : 'Los retiros requieren confirmación',
      message: _mode == ExcelImportMode.additionsOnly
          ? 'La hoja puede ser parcial. Solo se procesan las personas que selecciones; quienes no aparezcan conservan su estado.'
          : 'Elige esta modalidad solo cuando el Excel sea la lista completa del curso. Los posibles retiros aparecen desmarcados y la hoja debe superar todas las revisiones.',
      icon: _mode == ExcelImportMode.additionsOnly
          ? Icons.person_add_alt_1_outlined
          : Icons.fact_check_outlined,
    ),
    const SizedBox(height: 12),
    const CourseStateCard(
      title: 'Solo datos necesarios',
      message: 'Se usan código estudiantil, correo y nombre. Documento, teléfono, EPS y demás columnas se descartan en el dispositivo.',
      icon: Icons.info_outline,
    ),
  ];

  List<Widget> _columnsContent() {
    final document = _document!;
    final sheet = _sheet;
    return [
      const CoursePageHeading(title: 'Reconocimos tu archivo.'),
      const SizedBox(height: 8),
      Text(document.fileName, style: const TextStyle(color: AppColors.muted)),
      Text(
        _mode == ExcelImportMode.completeList
            ? 'Comparación completa · retiros desmarcados'
            : 'Solo agregar · no cambia quienes faltan',
        style: const TextStyle(color: AppColors.information, fontSize: 14),
      ),
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
            message: 'No se pueden proponer retiros desde una hoja vacía. Elige otra hoja o vuelve a importar un archivo corregido.',
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
        _field('Ingreso al curso', _effectiveStartDate!.isoDate),
        OutlinedButton.icon(
          onPressed: _busy ? null : _chooseStartDate,
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Elegir fecha de ingreso'),
        ),
        const SizedBox(height: 12),
        const CourseStateCard(
          title: 'Fecha de matrícula',
          message: 'FECHAMATRICULA no cambia la fecha efectiva. Se guarda una fecha civil de America/Bogota; la hora de auditoría sigue siendo del servidor.',
          icon: Icons.info_outline,
        ),
      ] else
        const CourseStateCard(
          title: 'Elige una hoja',
          message: 'Hay varias hojas compatibles. Selecciona una; no se combinarán en silencio.',
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
    final review = _review!;
    return [
      const CoursePageHeading(title: 'Revisa qué cambió.'),
      const SizedBox(height: 16),
      _destinationTile(),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _indicator('${review.newCount}', 'Nuevos'),
          _indicator('${review.unchangedCount}', 'Sin cambios'),
          _indicator(
            '${review.potentialWithdrawals.length}',
            'Posibles retiros',
          ),
          _indicator('${review.needsReviewCount}', 'Por revisar'),
        ],
      ),
      const SizedBox(height: 16),
      if (review.mode == ExcelImportMode.completeList && !review.isComplete)
        CourseStateCard(
          title: 'Comparación incompleta',
          message: review.retirementBlockReason ?? 'No se cargó la lista completa. Vuelve a comparar o usa Solo agregar estudiantes.',
          icon: Icons.cloud_off_outlined,
          color: AppColors.danger,
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _reviewRows(mode: ExcelImportMode.completeList),
                icon: const Icon(Icons.refresh),
                label: const Text('Volver a cargar'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _reviewRows(mode: ExcelImportMode.additionsOnly),
                child: const Text('Solo agregar'),
              ),
            ],
          ),
        )
      else if (!review.retirementsAllowed &&
          review.mode == ExcelImportMode.completeList)
        CourseStateCard(
          title: 'No se pueden confirmar retiros',
          message: review.retirementBlockReason ?? 'Corrige las identidades marcadas. Puedes aplicar solo altas válidas en Solo agregar.',
          icon: Icons.warning_amber_outlined,
          color: AppColors.danger,
        )
      else
        const CourseStateCard(
          title: 'Correo y código cotejados',
          message: 'El nombre ayuda a reconocer a la persona. Las altas, pendientes, reincorporaciones y retiros solo se guardan al confirmar.',
          icon: Icons.verified_outlined,
        ),
      const SizedBox(height: 12),
      for (final row in review.rows) _reviewTile(row),
      if (review.retirementsAllowed &&
          review.potentialWithdrawals.isNotEmpty) ...[
        const CourseSectionHeading(
          title: 'Personas que no aparecen en el Excel',
        ),
        const SizedBox(height: 8),
        const Text(
          'Estos posibles retiros empiezan desmarcados. Seleccionar todos solo afecta a este grupo.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        for (final member in review.potentialWithdrawals)
          _rosterMemberTile(member, selectable: false),
      ],
      if (review.rows.isEmpty && review.potentialWithdrawals.isEmpty)
        const CourseStateCard(
          title: 'No hay cambios para revisar',
          message: 'La lista está vacía o no contiene filas con identidad confiable.',
          icon: Icons.table_rows_outlined,
        ),
      CourseSecondaryButton(
        label: 'Volver sin aplicar cambios',
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
      ),
    ];
  }

  Widget _reviewTile(ExcelReviewedRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: CoursePanel(
      padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 6),
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

  List<ExcelReviewedRow> _rowsForActions(Set<ExcelReviewAction> actions) =>
      _review!.rows
          .where((row) => row.selectable && actions.contains(row.action))
          .toList(growable: false);

  void _toggleRows(Iterable<ExcelReviewedRow> rows, {required bool select}) {
    setState(() {
      for (final row in rows) {
        if (select) {
          _selectedRows.add(row.row.rowNumber);
        } else {
          _selectedRows.remove(row.row.rowNumber);
        }
      }
    });
  }

  List<Widget> _additionsContent() {
    final newRows = _rowsForActions({
      ExcelReviewAction.enrollDirect,
      ExcelReviewAction.authorizePending,
    });
    final rejoinRows = _rowsForActions({
      ExcelReviewAction.rejoinEnrollment,
      ExcelReviewAction.reopenPending,
    });
    final allRows = [...newRows, ...rejoinRows];
    return [
      CoursePageHeading(
        title: 'Selecciona las altas.',
        description:
            '${_document?.fileName ?? ''} · marca solo lo que quieres aplicar',
      ),
      const SizedBox(height: 16),
      _indicator('${_selectedRows.length}', 'Seleccionadas'),
      const SizedBox(height: 16),
      if (newRows.isNotEmpty) ...[
        const CourseSectionHeading(title: 'Nuevos y pendientes'),
        const SizedBox(height: 8),
        CourseSecondaryButton(
          label: 'Seleccionar todas las altas',
          onPressed: _busy ? null : () => _toggleRows(newRows, select: true),
        ),
        const SizedBox(height: 8),
        CourseSecondaryButton(
          label: 'Desmarcar las altas',
          onPressed: _busy ? null : () => _toggleRows(newRows, select: false),
        ),
        const SizedBox(height: 10),
        for (final row in newRows) _selectRowTile(row),
      ],
      if (rejoinRows.isNotEmpty) ...[
        const CourseSectionHeading(title: 'Reincorporaciones explícitas'),
        const SizedBox(height: 8),
        CourseSecondaryButton(
          label: 'Seleccionar reincorporaciones',
          onPressed: _busy ? null : () => _toggleRows(rejoinRows, select: true),
        ),
        const SizedBox(height: 8),
        CourseSecondaryButton(
          label: 'Desmarcar reincorporaciones',
          onPressed: _busy
              ? null
              : () => _toggleRows(rejoinRows, select: false),
        ),
        const SizedBox(height: 10),
        for (final row in rejoinRows) _selectRowTile(row),
      ],
      if (allRows.isEmpty)
        const CourseStateCard(
          title: 'No hay altas seleccionables',
          message: 'Revisa los estados de las filas. Los posibles retiros se eligen en el paso siguiente.',
          icon: Icons.info_outline,
        ),
    ];
  }

  Widget _selectRowTile(ExcelReviewedRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: CoursePanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: _selectedRows.contains(row.row.rowNumber),
            onChanged: _busy ? null : (_) => _toggleRow(row.row.rowNumber),
            semanticLabel: 'Seleccionar fila ${row.row.rowNumber}',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.candidate?.name ?? row.row.name,
                  style: const TextStyle(color: AppColors.text, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  row.message,
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  row.row.email,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _withdrawalsContent() {
    final members = _review!.potentialWithdrawals;
    return [
      const CoursePageHeading(
        title: 'Elige quién se retira.',
        description:
            'Solo se compara contra la lista completa que terminó de cargarse.',
      ),
      const SizedBox(height: 16),
      _indicator('${_selectedWithdrawals.length}', 'Seleccionados'),
      const SizedBox(height: 16),
      CourseSecondaryButton(
        label: 'Seleccionar todos los posibles retiros',
        onPressed: _busy
            ? null
            : () => setState(
                () => _selectedWithdrawals.addAll(members.map(_memberKey)),
              ),
      ),
      const SizedBox(height: 8),
      CourseSecondaryButton(
        label: 'Conservar a todas estas personas',
        onPressed: _busy ? null : () => setState(_selectedWithdrawals.clear),
      ),
      const SizedBox(height: 14),
      const CourseStateCard(
        title: 'Historial conservado',
        message: 'Solo se retiran las personas que marques. La fecha elegida no se incluye en el tramo activo; las demás matrículas se conservan.',
        icon: Icons.history,
      ),
      const SizedBox(height: 12),
      for (final member in members) _rosterMemberTile(member, selectable: true),
    ];
  }

  Widget _rosterMemberTile(
    ExcelRosterMember member, {
    required bool selectable,
  }) {
    final selected = _selectedWithdrawals.contains(_memberKey(member));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CoursePanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (selectable)
              Checkbox(
                value: selected,
                onChanged: _busy ? null : (_) => _toggleWithdrawal(member),
                semanticLabel: 'Seleccionar retiro de ${member.name}',
              )
            else
              const Icon(Icons.person_outline, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${member.studentCode ?? 'Sin código'} · ${member.email}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    member.kind == ExcelRosterMemberKind.pending
                        ? 'Pendiente sin cuenta · no aparece en el Excel'
                        : 'Inscripción activa · no aparece en el Excel',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _confirmationContent() {
    final rows = _selectedRowsInReview;
    final withdrawals = _selectedWithdrawalMembers;
    final pendingAdds = rows
        .where(
          (row) =>
              row.action == ExcelReviewAction.authorizePending ||
              row.action == ExcelReviewAction.reopenPending,
        )
        .length;
    final directAdds = rows
        .where(
          (row) =>
              row.action == ExcelReviewAction.enrollDirect ||
              row.action == ExcelReviewAction.rejoinEnrollment,
        )
        .length;
    return [
      const CoursePageHeading(title: 'Estos cambios se aplicarán.'),
      const SizedBox(height: 16),
      _destinationTile(),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _indicator('$directAdds', 'Altas / reincorporaciones'),
          _indicator('$pendingAdds', 'Pendientes'),
          _indicator('${withdrawals.length}', 'Por retirar'),
        ],
      ),
      const SizedBox(height: 16),
      if (rows.isNotEmpty)
        _field(
          'Fecha efectiva de ingreso/reincorporación · Bogotá',
          _effectiveStartDate!.isoDate,
        ),
      if (withdrawals.isNotEmpty)
        _field(
          'Fecha efectiva de retiro · Bogotá',
          _withdrawalEffectiveDate!.isoDate,
        ),
      CourseStateCard(
        title: 'Confirma por persona',
        message: rows.isNotEmpty && withdrawals.isNotEmpty
            ? 'Las altas y reincorporaciones empiezan ${_effectiveStartDate!.isoDate}; los retiros son efectivos desde ${_withdrawalEffectiveDate!.isoDate} y ese día queda fuera del tramo activo. La fecha de retiro no puede preceder la autorización ni el último cambio. Cada persona se confirma por separado.'
            : withdrawals.isNotEmpty
            ? 'Desde ${_withdrawalEffectiveDate!.isoDate} se retiran solo las personas marcadas. Esa fecha no pertenece al tramo activo ni puede preceder la autorización o el último cambio; las personas no seleccionadas conservan su matrícula.'
            : 'Las altas y reincorporaciones se procesan una por una desde ${_effectiveStartDate!.isoDate}. Si una falla, las demás confirmadas se conservan.',
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 14),
      if (rows.isNotEmpty) ...[
        const CourseSectionHeading(
          title: 'Altas, pendientes y reincorporaciones',
        ),
        const SizedBox(height: 8),
        for (final row in rows)
          EnrollmentTile(
            title: row.candidate?.name ?? row.row.name,
            subtitle:
                '${row.row.studentCode} · ${row.row.email} · ${_actionLabel(row.action)}',
            iconAsset: '51a24.svg',
          ),
      ],
      if (withdrawals.isNotEmpty) ...[
        const CourseSectionHeading(title: 'Retiros seleccionados'),
        const SizedBox(height: 8),
        for (final member in withdrawals)
          EnrollmentTile(
            title: member.name,
            subtitle: '${member.studentCode ?? 'Sin código'} · ${member.email}',
            iconAsset: 'df818.svg',
          ),
      ],
      if (rows.isNotEmpty)
        CourseSecondaryButton(
          label: 'Cambiar fecha de ingreso/reincorporación',
          icon: Icons.calendar_month_outlined,
          onPressed: _busy ? null : _chooseStartDate,
        ),
      if (withdrawals.isNotEmpty)
        CourseSecondaryButton(
          label: 'Cambiar fecha de retiro',
          icon: Icons.calendar_month_outlined,
          onPressed: _busy ? null : _chooseWithdrawalDate,
        ),
      const SizedBox(height: 10),
      CourseSecondaryButton(
        label: 'Volver a la selección',
        onPressed: _busy ? null : _back,
      ),
    ];
  }

  List<Widget> _noChangesContent() => [
    const CoursePageHeading(title: 'No seleccionaste cambios.'),
    const SizedBox(height: 18),
    const CourseStateCard(
      title: 'Tu lista se mantiene',
      message: 'Selecciona al menos una alta, reincorporación o retiro para guardar cambios. No se ha escrito nada.',
      icon: Icons.info_outline,
    ),
    const SizedBox(height: 14),
    CourseSecondaryButton(
      label: 'Revisar la selección',
      onPressed: _busy
          ? null
          : () => setState(() => _step = _RosterUpdateStep.additions),
    ),
    const SizedBox(height: 10),
    CourseSecondaryButton(
      label: 'Volver al resumen',
      onPressed: _busy
          ? null
          : () => setState(() => _step = _RosterUpdateStep.review),
    ),
  ];

  List<Widget> _resultContent() {
    final result = _result!;
    final succeeded =
        result.enrolledNow +
        result.pendingNow +
        result.rejoined +
        result.pendingReopened +
        result.withdrawnNow +
        result.pendingWithdrawnNow;
    final notSelectedRows = _review!.rows.where(
      (row) => row.selectable && !_selectedRows.contains(row.row.rowNumber),
    );
    final notSelectedWithdrawals = _review!.potentialWithdrawals.where(
      (member) => !_selectedWithdrawals.contains(_memberKey(member)),
    );
    return [
      CoursePageHeading(
        title: succeeded > 0
            ? 'Tu selección se aplicó.'
            : 'No se confirmaron cambios.',
        description: _destination,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _indicator('${result.enrolledNow + result.rejoined}', 'Agregados'),
          _indicator(
            '${result.pendingNow + result.pendingReopened}',
            'Pendientes',
          ),
          _indicator(
            '${result.withdrawnNow + result.pendingWithdrawnNow}',
            'Retirados',
          ),
          _indicator('${result.needsReview}', 'Por revisar'),
          _indicator('${result.failed}', 'Sin confirmar'),
        ],
      ),
      const SizedBox(height: 14),
      CourseStateCard(
        title: succeeded > 0
            ? 'Cambios guardados'
            : 'Revisa el estado antes de reintentar',
        message: succeeded > 0
            ? 'Los cambios confirmados se conservan aunque otra fila necesite revisión o reintento.'
            : 'No se presenta un éxito sin confirmación de Firestore. Actualiza la comparación antes de volver a confirmar.',
        icon: succeeded > 0 ? Icons.check_circle_outline : Icons.info_outline,
        color: succeeded > 0 ? AppColors.information : AppColors.danger,
      ),
      const SizedBox(height: 12),
      if (result.rows.isNotEmpty) ...[
        const CourseSectionHeading(title: 'Resultado por fila'),
        const SizedBox(height: 8),
        for (final row in result.rows)
          _resultTile(
            'Fila ${row.reviewed.row.rowNumber} · ${row.reviewed.row.name}',
            row.message,
          ),
      ],
      if (result.rosterChanges.isNotEmpty) ...[
        const CourseSectionHeading(title: 'Resultado de retiros'),
        const SizedBox(height: 8),
        for (final change in result.rosterChanges)
          _resultTile(
            '${change.member.name} · ${change.member.email}',
            change.message,
          ),
      ],
      if (notSelectedRows.isNotEmpty || notSelectedWithdrawals.isNotEmpty) ...[
        const CourseSectionHeading(
          title: 'Sin cambios porque no se seleccionaron',
        ),
        const SizedBox(height: 8),
        for (final row in notSelectedRows)
          _resultTile(row.row.name, 'No se guardó; no estaba seleccionada.'),
        for (final member in notSelectedWithdrawals)
          _resultTile(
            member.name,
            'Se conservó; el retiro no estaba seleccionado.',
          ),
      ],
    ];
  }

  Widget _resultTile(String title, String message) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: CoursePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );

  String _actionLabel(ExcelReviewAction action) => switch (action) {
    ExcelReviewAction.enrollDirect => 'Agregar al curso',
    ExcelReviewAction.authorizePending => 'Autorizar vinculación posterior',
    ExcelReviewAction.rejoinEnrollment => 'Abrir un nuevo tramo activo',
    ExcelReviewAction.reopenPending => 'Reabrir autorización',
    ExcelReviewAction.none => 'Sin cambios',
  };

  String _memberKey(ExcelRosterMember member) =>
      '${member.kind.name}:${member.identityKey}';
}

AcademicDate _todayBogota() {
  final bogota = DateTime.now().toUtc().subtract(const Duration(hours: 5));
  return AcademicDate.fromDateTime(bogota);
}

AcademicDate _defaultStartDate(Course course) {
  final today = _todayBogota();
  if (today.compareTo(course.schedule.startDate) < 0) {
    return course.schedule.startDate;
  }
  if (today.compareTo(course.schedule.endDate) > 0) {
    return course.schedule.endDate;
  }
  return today;
}

AcademicDate _defaultWithdrawalDate(Course course) {
  final today = _todayBogota();
  if (today.compareTo(course.schedule.startDate) < 0) return today;
  if (today.compareTo(course.schedule.endDate) > 0) {
    return course.schedule.endDate;
  }
  return today;
}

AcademicDate _minimum(AcademicDate a, AcademicDate b) =>
    a.compareTo(b) <= 0 ? a : b;

AcademicDate _clamp(
  AcademicDate value,
  AcademicDate minimum,
  AcademicDate maximum,
) {
  if (value.compareTo(minimum) < 0) return minimum;
  if (value.compareTo(maximum) > 0) return maximum;
  return value;
}

DateTime _localDate(AcademicDate date) =>
    DateTime(date.year, date.month, date.day);
