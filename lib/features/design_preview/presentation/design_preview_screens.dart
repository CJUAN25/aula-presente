import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../mockup_catalog.dart';
import '../mockup_frame.dart';

class DesignPreviewCatalogScreen extends StatefulWidget {
  const DesignPreviewCatalogScreen({super.key});

  @override
  State<DesignPreviewCatalogScreen> createState() =>
      _DesignPreviewCatalogScreenState();
}

class _DesignPreviewCatalogScreenState
    extends State<DesignPreviewCatalogScreen> {
  MockupRole? _role;
  String _query = '';

  List<MockupFrame> get _visibleFrames => mockupFrames.where((frame) {
    final matchesRole = _role == null || frame.role == _role;
    final matchesQuery =
        _query.isEmpty ||
        '${frame.title} ${frame.pageLabel} ${frame.route}'
            .toLowerCase()
            .contains(_query.toLowerCase());
    return matchesRole && matchesQuery;
  }).toList();

  void _openFrame(MockupFrame frame) {
    final roleFrames = mockupFrames
        .where((item) => item.role == frame.role)
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MockupFrameScreen(frame: frame, roleFrames: roleFrames),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frames = _visibleFrames;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorridos de diseño'),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DemoBanner(
                  text: 'Datos ficticios. Esta vista no consulta ni guarda en Firebase.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aula Presente',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Explora cada pantalla',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 25,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${frames.length} de ${mockupFrames.length} marcos · ${_role?.label ?? 'todos los perfiles'}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    key: const Key('mockup-search'),
                    onChanged: (value) => setState(() => _query = value.trim()),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar pantalla o ruta',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _RoleChoice(
                        label: 'Todos',
                        selected: _role == null,
                        keyName: 'role-all',
                        onSelected: () => setState(() => _role = null),
                      ),
                      for (final role in MockupRole.values)
                        _RoleChoice(
                          label: role.label,
                          selected: _role == role,
                          keyName: 'role-${role.name}',
                          onSelected: () => setState(() => _role = role),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: frames.isEmpty
                      ? const Center(
                          child: Text('No hay marcos que coincidan.'),
                        )
                      : ListView.separated(
                          key: const Key('mockup-frame-list'),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          itemCount: frames.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final frame = frames[index];
                            return _FrameCard(
                              frame: frame,
                              onTap: () => _openFrame(frame),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.label,
    required this.selected,
    required this.keyName,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final String keyName;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ChoiceChip(
      key: Key(keyName),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        color: selected ? AppColors.primaryInk : AppColors.text,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.outline),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _FrameCard extends StatelessWidget {
  const _FrameCard({required this.frame, required this.onTap});

  final MockupFrame frame;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      key: Key('mockup-${frame.page.toString().padLeft(3, '0')}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.phone_android_rounded,
                color: AppColors.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    frame.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${frame.pageLabel} · ${frame.role.label}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              frame.connected ? Icons.link_rounded : Icons.touch_app_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    ),
  );
}

class MockupFrameScreen extends StatefulWidget {
  const MockupFrameScreen({
    super.key,
    required this.frame,
    required this.roleFrames,
  });

  final MockupFrame frame;
  final List<MockupFrame> roleFrames;

  @override
  State<MockupFrameScreen> createState() => _MockupFrameScreenState();
}

class _MockupFrameScreenState extends State<MockupFrameScreen> {
  final _noteController = TextEditingController();
  bool _actionDone = false;
  bool _present = true;
  String? _decision;
  String _method = 'Bluetooth';
  DateTime _selectedDate = DateTime(2026, 11, 23);
  String _selectedSlot = '10:00–12:00';
  String _scheduleScope = 'Solo fechas futuras';

  MockupFrame get _frame => widget.frame;
  int get _position =>
      widget.roleFrames.indexWhere((frame) => frame.page == _frame.page);
  MockupFrame? get _nextFrame =>
      _position >= 0 && _position + 1 < widget.roleFrames.length
      ? widget.roleFrames[_position + 1]
      : null;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _openNext() {
    final next = _nextFrame;
    if (next == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            MockupFrameScreen(frame: next, roleFrames: widget.roleFrames),
      ),
    );
  }

  void _finishAction() {
    setState(() => _actionDone = true);
  }

  Future<void> _confirmCancellation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar esta clase'),
        content: const Text('La acción solo cambia el estado de esta demo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _finishAction();
    }
  }

  Future<void> _confirmFinalize() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar registro'),
        content: const Text(
          'Las marcas sin registro quedarán como ausentes en esta demostración.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Seguir registrando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar cierre'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _finishAction();
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2026, 11, 17),
      lastDate: DateTime(2027, 12, 31),
      helpText: 'Nueva fecha de la clase de prueba',
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  Widget _rescheduleFields() => Column(
    children: [
      _selectableField(
        icon: Icons.calendar_month_outlined,
        label: 'Nueva fecha',
        value:
            '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
        onTap: _chooseDate,
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nuevo horario',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final slot in [
                  '08:00–10:00',
                  '10:00–12:00',
                  '14:00–16:00',
                ])
                  ChoiceChip(
                    label: Text(slot),
                    selected: _selectedSlot == slot,
                    onSelected: (_) => setState(() => _selectedSlot = slot),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.glass,
                    labelStyle: TextStyle(
                      color: _selectedSlot == slot
                          ? AppColors.primaryInk
                          : AppColors.text,
                      fontSize: 11,
                    ),
                    showCheckmark: false,
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _selectableField(
        icon: Icons.location_on_outlined,
        label: 'Lugar',
        value: 'Aula 204',
      ),
    ],
  );

  Widget _futureScheduleFields() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿A qué clases aplica?',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          children: [
            for (final scope in ['Solo fechas futuras', 'Una fecha puntual'])
              ChoiceChip(
                label: Text(scope),
                selected: _scheduleScope == scope,
                onSelected: (_) => setState(() => _scheduleScope = scope),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.glass,
                labelStyle: TextStyle(
                  color: _scheduleScope == scope
                      ? AppColors.primaryInk
                      : AppColors.text,
                  fontSize: 12,
                ),
                showCheckmark: false,
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final canEditNote =
        _frame.page == 32 ||
        _frame.page == 33 ||
        _frame.page == 43 ||
        _frame.page == 44 ||
        _frame.page == 48 ||
        _frame.page == 49 ||
        _frame.page == 74 ||
        _frame.page == 146 ||
        _frame.page == 68 ||
        _frame.page == 71;
    final isAttendanceCorrection = const {
      48,
      49,
      74,
      146,
    }.contains(_frame.page);
    final isJustificationReview = _frame.page == 54;
    final isCancel = _frame.page == 43;
    final isFinalize = _frame.page == 47;
    final isTextJustification = _frame.page == 32 || _frame.page == 33;
    final needsJustificationText =
        isTextJustification && _noteController.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aula Presente'),
        backgroundColor: AppColors.background,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _frame.pageLabel,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const _DemoBanner(
                text: 'DEMO · Interacciones locales; no se envían datos.',
              ),
              const SizedBox(height: 20),
              Text(
                '${_frame.role.label.toUpperCase()}  ·  ${_frame.pageLabel}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _headline(_frame),
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 27,
                  height: 1.17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _description(_frame),
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              if (_frame.page == 23) ...[
                TextField(
                  key: const Key('demo-course-search'),
                  decoration: const InputDecoration(
                    hintText: 'Buscar materia o grupo',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_showsCourseCard(_frame))
                _courseCard(_frame)
              else
                _authPreviewCard(_frame),
              const SizedBox(height: 12),
              if (_showsMetrics(_frame)) ...[
                _metricsCard(_frame),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 30 || _frame.page == 58) ...[
                _calculationCard(),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 67) ...[
                _scheduleCard(_frame),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 44) ...[
                _rescheduleFields(),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 71) ...[
                _futureScheduleFields(),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 35) ...[
                _qrPreviewPanel(),
                const SizedBox(height: 12),
              ] else if (_frame.page == 27 ||
                  _frame.page == 45 ||
                  _frame.page == 46 ||
                  _frame.page == 135 ||
                  (_frame.page >= 111 && _frame.page <= 125)) ...[
                _methodPanel(
                  _method,
                  (value) => setState(() => _method = value),
                ),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 32 || _frame.page == 33) ...[
                _sectionTitle('Tu justificación'),
                const SizedBox(height: 9),
                TextField(
                  key: const Key('demo-note'),
                  controller: _noteController,
                  maxLines: 3,
                  maxLength: 180,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Cuéntale brevemente al docente qué ocurrió',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                  ),
                ),
                _infoCard(
                  Icons.info_outline_rounded,
                  'El flujo de C8 guarda texto. En este mockup, el adjunto PDF es solo visual y no se carga.',
                  AppColors.information,
                ),
                const SizedBox(height: 12),
              ] else if (canEditNote) ...[
                _sectionTitle('Detalle opcional'),
                const SizedBox(height: 9),
                TextField(
                  key: const Key('demo-note'),
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Añade un motivo (opcional)',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (isAttendanceCorrection) ...[
                _sectionTitle('Marca de asistencia'),
                const SizedBox(height: 9),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Presente'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Ausente'),
                      icon: Icon(Icons.cancel_outlined),
                    ),
                  ],
                  selected: {_present},
                  onSelectionChanged: (value) =>
                      setState(() => _present = value.first),
                ),
                const SizedBox(height: 12),
              ],
              if (isJustificationReview) ...[
                _infoCard(
                  Icons.article_outlined,
                  '“Tuve una cita médica durante este encuentro.”',
                  AppColors.information,
                ),
                const SizedBox(height: 12),
                if (_decision == null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('demo-reject'),
                          onPressed: () => setState(() {
                            _decision = 'Rechazada';
                            _actionDone = true;
                          }),
                          child: const Text('Rechazar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: const Key('demo-approve'),
                          onPressed: () => setState(() {
                            _decision = 'Aprobada';
                            _actionDone = true;
                          }),
                          child: const Text('Aprobar'),
                        ),
                      ),
                    ],
                  )
                else
                  _infoCard(
                    Icons.check_circle_outline,
                    'Solicitud ${_decision!.toLowerCase()} en esta demostración.',
                    AppColors.primary,
                  ),
                const SizedBox(height: 12),
              ],
              if (_frame.page == 34 ||
                  _frame.page == 51 ||
                  _frame.page == 52 ||
                  _frame.page == 53) ...[
                _statusRow('Programación Móvil', 'Pendiente de revisión'),
                _statusRow('Bases de Datos', 'Aprobada'),
                _statusRow('Redes Informáticas', 'Rechazada'),
                const SizedBox(height: 12),
              ],
              if (_hasSpecialState(_frame.page)) ...[
                _stateCard(_frame),
                const SizedBox(height: 12),
              ],
              _sectionTitle(_sectionFor(_frame)),
              const SizedBox(height: 9),
              for (final item in _rowsFor(_frame))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _listRow(item.$1, item.$2, item.$3),
                ),
              const SizedBox(height: 12),
              if (_actionDone && !isJustificationReview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _infoCard(
                    Icons.check_circle_outline,
                    _resultMessage(_frame, _present),
                    AppColors.primary,
                  ),
                ),
              if (!isJustificationReview)
                FilledButton.icon(
                  key: const Key('demo-primary-action'),
                  onPressed: _actionDone
                      ? null
                      : needsJustificationText
                      ? null
                      : isCancel
                      ? _confirmCancellation
                      : isFinalize
                      ? _confirmFinalize
                      : _finishAction,
                  icon: Icon(_actionDone ? Icons.check : _actionIcon(_frame)),
                  label: Text(_actionDone ? 'Listo' : _actionLabel(_frame)),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('demo-next-frame'),
                onPressed: _nextFrame == null ? null : _openNext,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  _nextFrame == null
                      ? 'Último marco de ${_frame.role.label.toLowerCase()}'
                      : 'Siguiente: ${_nextFrame!.pageLabel}',
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Volver al catálogo'),
              ),
              const SizedBox(height: 6),
              Text(
                'Ruta Flutter relacionada\n${_frame.route}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _PreviewNavigation(role: _frame.role),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: AppColors.outline.withValues(alpha: 0.55)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.visibility_outlined,
          color: AppColors.primary,
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PreviewNavigation extends StatelessWidget {
  const _PreviewNavigation({required this.role});
  final MockupRole role;

  @override
  Widget build(BuildContext context) {
    final secondLabel = role == MockupRole.teacher ? 'Cursos' : 'Materias';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.home_outlined, 'Inicio', true),
          _navItem(Icons.menu_book_outlined, secondLabel, false),
          _navItem(Icons.person_outline_rounded, 'Perfil', false),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool selected) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 19,
        color: selected ? AppColors.primary : AppColors.muted,
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primary : AppColors.muted,
          fontSize: 10,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

Widget _courseCard(MockupFrame frame) {
  final icon = switch (frame.role) {
    MockupRole.student => Icons.code_rounded,
    MockupRole.teacher => Icons.school_outlined,
    MockupRole.shared => Icons.auto_awesome_outlined,
    MockupRole.admin => Icons.admin_panel_settings_outlined,
  };
  final courseName = switch (frame.page) {
    40 || 41 || 42 => 'Bases de Datos',
    25 => 'Cálculo I',
    26 => 'Redes Informáticas',
    _ => 'Programación Móvil',
  };
  final status = switch (frame.page) {
    19 || 37 => 'Próxima clase',
    20 || 38 => 'Registro abierto',
    21 => 'Asistencia lista',
    22 => 'Después',
    27 => 'Registro disponible',
    28 || 137 => 'Presente',
    43 => 'Sin reprogramación',
    44 => 'Nueva fecha',
    46 => 'Bluetooth · hasta 10:39',
    47 => 'Cierre de asistencia',
    _ =>
      frame.role == MockupRole.teacher ? 'Curso de prueba' : 'Materia activa',
  };
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.outline.withValues(alpha: 0.75)),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                courseName,
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                frame.role == MockupRole.teacher
                    ? 'Grupo 2 · Aula 204'
                    : 'Grupo 2 · Docente de prueba',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: AppColors.muted),
      ],
    ),
  );
}

bool _showsCourseCard(MockupFrame frame) {
  if (frame.page == 134) return false;
  return frame.page > 18 && frame.role != MockupRole.shared ||
      const {7, 8, 18}.contains(frame.page);
}

Widget _authPreviewCard(MockupFrame frame) {
  if (frame.page == 1) {
    return _infoCard(
      Icons.school_outlined,
      'Aula Presente · asistencia y cursos en un mismo lugar.',
      AppColors.primary,
    );
  }
  if (frame.page == 2 || frame.page == 14 || frame.page == 132) {
    return Column(
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.mail_outline),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
        const SizedBox(height: 10),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: Icon(Icons.lock_outline),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
        if (frame.page == 132) ...[
          const SizedBox(height: 10),
          _infoCard(
            Icons.error_outline,
            'No pudimos iniciar sesión. Revisa los datos de prueba.',
            AppColors.danger,
          ),
        ],
      ],
    );
  }
  if (frame.page == 4 || frame.page == 15 || frame.page == 17) {
    return _infoCard(
      Icons.mark_email_read_outlined,
      frame.page == 17
          ? 'Tu solicitud docente está en revisión.'
          : 'Revisa tu correo para continuar con el acceso.',
      AppColors.information,
    );
  }
  if (frame.page == 5 || frame.page == 16) {
    return Column(
      children: [
        _listRow(
          'Espacio estudiante',
          'Mis materias y asistencia',
          Icons.school_outlined,
        ),
        const SizedBox(height: 8),
        _listRow(
          'Espacio docente',
          'Cursos y lista de asistencia',
          Icons.co_present_outlined,
        ),
      ],
    );
  }
  return _infoCard(
    Icons.account_circle_outlined,
    '${frame.title} · vista visual de la ruta conectada.',
    AppColors.information,
  );
}

Widget _metricsCard(MockupFrame frame) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
  ),
  child: Column(
    children: [
      Row(
        children: [
          Expanded(child: _metric('20', 'Realizadas')),
          Expanded(child: _metric('16', 'Asistencias')),
          Expanded(child: _metric('4', 'Faltas')),
        ],
      ),
      const SizedBox(height: 14),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: const LinearProgressIndicator(
          value: 0.8,
          minHeight: 8,
          backgroundColor: AppColors.glass,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: 7),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          frame.role == MockupRole.teacher
              ? '32 estudiantes · 31 clases previstas'
              : '80 % de asistencia · datos ficticios',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ),
    ],
  ),
);

bool _showsMetrics(MockupFrame frame) => const {
  24,
  25,
  26,
  37,
  38,
  40,
  41,
  55,
  56,
  126,
  127,
  128,
}.contains(frame.page);

Widget _calculationCard() => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
  ),
  child: const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '3 ÷ 20 × 100 = 15 %',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(height: 8),
      Text(
        'La app cuenta las clases válidas hasta hoy. El resultado es informativo: no asigna una nota.',
        style: TextStyle(color: AppColors.muted, height: 1.45),
      ),
      SizedBox(height: 12),
      _CalculationTag(label: 'Justificadas aprobadas no cuentan como falta'),
    ],
  ),
);

class _CalculationTag extends StatelessWidget {
  const _CalculationTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline, color: AppColors.information, size: 17),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: AppColors.text, fontSize: 12),
        ),
      ),
    ],
  );
}

Widget _scheduleCard(MockupFrame frame) => Column(
  children: [
    for (final item in [
      ('Lunes', 'Programación Móvil · 10:00–12:00 · Aula 204'),
      ('Lunes', 'Redes Informáticas · 14:00–16:00 · Laboratorio 2'),
      ('Miércoles', 'Cálculo I · 08:00–10:00 · Grupo 3'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _listRow(item.$1, item.$2, Icons.calendar_month_outlined),
      ),
    if (frame.role == MockupRole.teacher)
      _infoCard(
        Icons.event_note_outlined,
        'Las reprogramaciones aparecen en el calendario del curso.',
        AppColors.information,
      ),
  ],
);

Widget _methodPanel(
  String selected,
  ValueChanged<String> onSelected,
) => Container(
  padding: const EdgeInsets.all(15),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Método de prueba',
        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text(
        'Elige una opción para ver su estado. No se activa ningún sensor.',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 7,
        runSpacing: 4,
        children: [
          for (final method in ['Manual', 'Bluetooth', 'QR', 'NFC'])
            ChoiceChip(
              label: Text(method),
              selected: selected == method,
              onSelected: (_) => onSelected(method),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.glass,
              labelStyle: TextStyle(
                color: selected == method
                    ? AppColors.primaryInk
                    : AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              showCheckmark: false,
            ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.primary, size: 18),
          const SizedBox(width: 7),
          Text(
            selected == 'Manual'
                ? 'Registro manual disponible'
                : '$selected · sesión local',
            style: const TextStyle(color: AppColors.text, fontSize: 12),
          ),
        ],
      ),
    ],
  ),
);

Widget _qrPreviewPanel() => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
  ),
  child: Column(
    children: [
      const Text(
        'QR dinámico',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Container(
        width: 124,
        height: 124,
        decoration: BoxDecoration(
          color: const Color(0xFFF4FAF7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.qr_code_2,
          size: 108,
          color: AppColors.background,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Muestra visual · sin código válido',
        style: TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    ],
  ),
);

bool _hasSpecialState(int page) => const {
  6,
  9,
  10,
  13,
  21,
  22,
  28,
  36,
  50,
  138,
  68,
  69,
  70,
  71,
  72,
  136,
  137,
  139,
  142,
  143,
  144,
  147,
  148,
  150,
  155,
  153,
  154,
  157,
  158,
}.contains(page);

Widget _stateCard(MockupFrame frame) {
  final (label, icon, color) = switch (frame.page) {
    6 || 133 => (
      'Permiso desactivado',
      Icons.bluetooth_disabled,
      AppColors.information,
    ),
    9 || 10 => ('Todo al día', Icons.notifications_none, AppColors.primary),
    13 => ('¿Necesitas ayuda?', Icons.help_outline, AppColors.information),
    22 => (
      'Sin clases programadas',
      Icons.event_available,
      AppColors.information,
    ),
    21 || 28 || 137 => (
      'Asistencia registrada',
      Icons.check_circle_outline,
      AppColors.primary,
    ),
    36 => ('Cursos encontrados', Icons.search, AppColors.primary),
    50 || 147 => ('Reapertura activa', Icons.restart_alt, AppColors.primary),
    68 ||
    69 ||
    70 => ('Curso archivado', Icons.archive_outlined, AppColors.information),
    71 || 72 => (
      'Cambio de horario futuro',
      Icons.edit_calendar_outlined,
      AppColors.information,
    ),
    136 => (
      'Registro cerrado',
      Icons.lock_clock_outlined,
      AppColors.information,
    ),
    139 || 144 => (
      'Cambios pendientes de sincronizar',
      Icons.sync_problem_outlined,
      AppColors.information,
    ),
    142 => (
      'No se pudo leer el documento',
      Icons.error_outline,
      AppColors.danger,
    ),
    143 => (
      'Bluetooth no disponible',
      Icons.bluetooth_disabled,
      AppColors.danger,
    ),
    138 => ('Llegaste tarde', Icons.schedule, AppColors.information),
    148 => (
      'Justificación aprobada',
      Icons.verified_outlined,
      AppColors.primary,
    ),
    150 => ('Justificación rechazada', Icons.cancel_outlined, AppColors.danger),
    153 => ('Invitación no válida', Icons.link_off_outlined, AppColors.danger),
    154 => ('Sin acceso a esta clase', Icons.lock_outline, AppColors.danger),
    157 => (
      'Revisa tus datos',
      Icons.manage_accounts_outlined,
      AppColors.information,
    ),
    155 => ('El QR venció', Icons.timer_off_outlined, AppColors.danger),
    158 => (
      'Marco de revisión',
      Icons.remove_red_eye_outlined,
      AppColors.information,
    ),
    _ => ('Estado de demostración', Icons.info_outline, AppColors.information),
  };
  final detail = switch (frame.page) {
    6 || 133 => 'Puedes cambiar el permiso en Configuración. Esta demo no abre ajustes del teléfono.',
    9 || 10 =>
      'Aquí aparecen avisos de clases, solicitudes y cambios de asistencia.',
    13 => 'Consulta preguntas frecuentes sobre tus materias y el registro de asistencia.',
    22 => 'No hay clases para hoy. Puedes consultar el horario de la semana.',
    21 ||
    28 ||
    137 => 'La marca de prueba quedó vinculada a Programación Móvil.',
    36 => 'Coincidió el código y el curso tiene cupos disponibles (datos ficticios).',
    136 => 'La sesión cerró. Si necesitas ayuda, comunícate con tu docente.',
    139 || 144 =>
      'La app conserva el estado local y permite volver a intentar en la demo.',
    142 => 'El archivo de ejemplo no se puede revisar. La app real C8 almacena texto, sin adjuntos.',
    143 => 'Elige otro método o espera a tener Bluetooth disponible. No se solicitó permiso.',
    138 => 'La marca tardía es una muestra visual; consulta el historial para ver el resultado.',
    148 => 'La falta cubierta no cuenta; el total de encuentros se conserva.',
    150 =>
      'La falta sigue contando. No se puede reenviar esta misma solicitud.',
    153 => 'El código de ejemplo venció o no coincide con un curso disponible.',
    154 => 'La invitación no tiene acceso a este curso de prueba.',
    157 => 'Comprueba que el correo verificado coincide con los datos de la solicitud.',
    155 =>
      'Solicita al docente un código vigente para registrar la asistencia.',
    _ => 'Este estado usa datos de muestra y no modifica el curso real.',
  };
  return _infoCard(icon, '$label. $detail', color);
}

Widget _metric(String value, String label) => Column(
  children: [
    Text(
      value,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.muted, fontSize: 10),
    ),
  ],
);

Widget _sectionTitle(String text) => Text(
  text,
  style: const TextStyle(
    color: AppColors.text,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  ),
);

Widget _listRow(String title, String detail, IconData icon) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(17),
  ),
  child: Row(
    children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
      const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
    ],
  ),
);

Widget _statusRow(String title, String detail) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: _listRow(title, detail, Icons.description_outlined),
);

Widget _infoCard(IconData icon, String message, Color color) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: color.withValues(alpha: 0.45)),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ),
    ],
  ),
);

Widget _selectableField({
  required IconData icon,
  required String label,
  required String value,
  VoidCallback? onTap,
}) => Material(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(17),
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(17),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    ),
  ),
);

String _headline(MockupFrame frame) {
  if (frame.page == 19 || frame.page == 20 || frame.page == 21) {
    return 'Hola, Alex';
  }
  if (frame.page == 22) {
    return 'Hoy tienes un respiro.';
  }
  if (frame.page == 23) {
    return 'Tus materias, en un solo lugar.';
  }
  if (frame.page == 27) {
    return 'Estás cerca de tu clase.';
  }
  if (frame.page == 28 || frame.page == 137) {
    return '¡Listo, Alex!';
  }
  if (frame.page == 29) {
    return 'Programación Móvil';
  }
  if (frame.page == 30) {
    return 'Cada materia tiene su cuenta.';
  }
  if (frame.page == 31) {
    return 'Tus clases, organizadas.';
  }
  if (frame.page == 37 || frame.page == 38) {
    return 'Hola, profe';
  }
  if (frame.page == 43) {
    return 'Actualiza el calendario.';
  }
  if (frame.page == 47) {
    return '¿Terminamos el registro?';
  }
  if (frame.page == 48 || frame.page == 49 || frame.page == 74) {
    return 'Corrige con claridad.';
  }
  if (frame.page == 57 || frame.page == 149) {
    return 'Informes claros, a tiempo.';
  }
  if (frame.page == 58) {
    return 'Reglas claras para el cálculo.';
  }
  if (frame.page == 32 || frame.page == 33) {
    return 'Una falta. Un documento.';
  }
  if (frame.page == 34) {
    return 'Sigue tus solicitudes.';
  }
  if (frame.page == 134) {
    return 'Tu semestre empieza aquí.';
  }
  if (frame.page == 140) {
    return 'Revisa tu asistencia.';
  }
  if (frame.page == 54) {
    return 'Revisa esta justificación.';
  }
  if (frame.page == 111) {
    return 'Elige cómo registrar.';
  }
  if (frame.page == 128) {
    return 'Estadísticas del proyecto';
  }
  if (frame.title == 'Aula') {
    return frame.role == MockupRole.teacher
        ? 'Tu clase ya está abierta.'
        : 'Tus materias, siempre aquí.';
  }
  return frame.title;
}

String _description(MockupFrame frame) {
  if (frame.connected) {
    return 'Previsualización del marco ${frame.pageLabel.toLowerCase()}. La ruta real conserva sus repositorios y controles de acceso.';
  }
  if (frame.page == 32 || frame.page == 33) {
    return 'Cuéntale brevemente al docente qué ocurrió. Este formulario es una maqueta y no se adjunta ni envía ningún documento.';
  }
  if (frame.page >= 111 && frame.page <= 125 ||
      frame.page == 35 ||
      frame.page == 135) {
    return 'Explora el estado del registro con datos simulados. No se activa la cámara, Bluetooth ni una sesión real.';
  }
  return 'Recorrido de demostración basado en el diseño. Las acciones operan solo en esta pantalla.';
}

String _sectionFor(MockupFrame frame) {
  if (const {19, 20, 21, 22, 37, 38}.contains(frame.page)) {
    return 'Hoy';
  }
  if (frame.page == 23 || frame.page == 39) {
    return frame.role == MockupRole.teacher ? 'Tus cursos' : 'Mis materias';
  }
  if (frame.page == 27 ||
      frame.page == 35 ||
      frame.page == 45 ||
      frame.page == 46) {
    return 'Registro de asistencia';
  }
  if (frame.page == 29 || frame.page == 140) {
    return 'Encuentros recientes';
  }
  if (frame.page == 31 || frame.page == 42 || frame.page == 67) {
    return 'Esta semana';
  }
  if (frame.page == 134) {
    return 'Empieza por vincular una materia';
  }
  if (frame.role == MockupRole.admin) {
    return 'Resumen de prueba';
  }
  if (frame.page >= 111 && frame.page <= 125 || frame.page == 35) {
    return 'Estado del método';
  }
  if (frame.page >= 57 && frame.page <= 58 ||
      frame.page == 128 ||
      frame.page == 149) {
    return 'Resumen del periodo';
  }
  if (frame.page >= 32 && frame.page <= 34 ||
      frame.page >= 51 && frame.page <= 54) {
    return 'Actividad reciente';
  }
  if (frame.role == MockupRole.teacher) {
    return 'Lo que sigue';
  }
  return 'Tu actividad';
}

List<(String, String, IconData)> _rowsFor(MockupFrame frame) {
  switch (frame.page) {
    case 19:
      return [
        ('Hoy', 'Ver agenda · clases de esta semana', Icons.today_outlined),
        (
          'Redes Informáticas',
          '14:00–16:00 · Laboratorio 2',
          Icons.code_rounded,
        ),
        (
          'Mis materias',
          'Consulta tus materias siempre aquí',
          Icons.menu_book_outlined,
        ),
      ];
    case 20:
      return [
        ('Después', 'Redes Informáticas · lunes, 14:00', Icons.schedule),
        (
          'Mis materias',
          'Consulta tu asistencia cuando quieras',
          Icons.menu_book_outlined,
        ),
      ];
    case 21:
      return [
        (
          'Comprobante',
          '10:24 · registro por cercanía',
          Icons.receipt_long_outlined,
        ),
        ('Ver historial', 'Consulta tus encuentros registrados', Icons.history),
      ];
    case 22:
      return [
        (
          'Tu próxima clase',
          'Programación Móvil · lunes, 10:00',
          Icons.schedule,
        ),
        (
          'Mis materias',
          'Consulta el estado de cada curso',
          Icons.menu_book_outlined,
        ),
      ];
    case 23:
      return [
        (
          'Programación Móvil',
          'Grupo 2 · registro abierto',
          Icons.code_rounded,
        ),
        ('Redes Informáticas', 'Grupo 1 · hoy, 14:00', Icons.router_outlined),
        ('Cálculo I', 'Grupo 3 · miércoles, 08:00', Icons.functions_rounded),
      ];
    case 24:
    case 25:
    case 26:
      return [
        (
          'Historial de asistencia',
          'Fechas, justificaciones y cambios',
          Icons.history,
        ),
        (
          'Mi horario',
          'Próximas clases y cambios',
          Icons.calendar_month_outlined,
        ),
        ('Mis materias', 'Consulta otra asignatura', Icons.menu_book_outlined),
      ];
    case 27:
      return [
        (
          'Docente detectado',
          'Registro abierto · aula de prueba',
          Icons.verified_outlined,
        ),
        (
          'Registro hasta las 10:35',
          'Confirma desde el aula para guardar tu marca.',
          Icons.timer_outlined,
        ),
      ];
    case 28:
    case 137:
      return [
        (
          'Programación Móvil',
          'Presente · 10:24 · registro por cercanía',
          Icons.check_circle_outline,
        ),
        (
          'Ver historial',
          'Consulta el detalle de tus asistencias',
          Icons.history,
        ),
      ];
    case 29:
      return [
        (
          '28 sep · presente',
          '10:24 · por cercanía',
          Icons.check_circle_outline,
        ),
        (
          '24 sep · falta',
          'Puedes enviar una justificación',
          Icons.description_outlined,
        ),
        (
          '21 sep · justificada',
          'No cuenta como falta',
          Icons.verified_outlined,
        ),
      ];
    case 30:
      return [
        (
          'Calendario semestral',
          '32 previstas · 1 cancelada · 31 válidas',
          Icons.calendar_month_outlined,
        ),
        (
          'Justificadas y canceladas',
          'No suman falta en el cálculo',
          Icons.verified_outlined,
        ),
        (
          'Umbral · 20 %',
          'Consulta las reglas de tu curso',
          Icons.info_outline,
        ),
      ];
    case 31:
      return [
        (
          'Lunes',
          'Programación Móvil · 10:00–12:00 · Aula 204',
          Icons.calendar_today_outlined,
        ),
        (
          'Lunes',
          'Redes Informáticas · 14:00–16:00 · Laboratorio 2',
          Icons.calendar_today_outlined,
        ),
        (
          'Miércoles',
          'Cálculo I · 08:00–10:00 · Grupo 3',
          Icons.calendar_today_outlined,
        ),
      ];
    case 32:
    case 33:
      return [
        (
          'Programación Móvil',
          'Grupo 2 · falta del 24 sep',
          Icons.code_rounded,
        ),
        (
          'justificacion.pdf',
          'Adjunto visual · no se carga',
          Icons.picture_as_pdf_outlined,
        ),
      ];
    case 35:
      return [
        (
          'Programación Móvil',
          'Registro abierto · QR de muestra',
          Icons.qr_code_2,
        ),
        (
          'Permiso de cámara',
          'No se solicitará en esta demostración',
          Icons.no_photography_outlined,
        ),
      ];
    case 34:
      return [
        (
          'Programación Móvil',
          '24 sep · pendiente de revisión',
          Icons.schedule,
        ),
        ('Programación Móvil', '21 sep · aprobada', Icons.check_circle_outline),
        ('Redes Informáticas', '18 sep · rechazada', Icons.cancel_outlined),
      ];
    case 36:
      return [
        ('Programación Móvil', 'G2 · 2026-2 · vinculada', Icons.code_rounded),
        ('Redes Informáticas', 'G1 · 2026-2 · 1 cupo', Icons.router_outlined),
      ];
    case 37:
      return [
        (
          'Mis cursos',
          'Todos tus grupos, siempre aquí',
          Icons.menu_book_outlined,
        ),
        ('Bases de Datos', 'Grupo 1 · mañana, 08:00', Icons.storage_outlined),
      ];
    case 38:
      return [
        ('Mis cursos', 'Consulta todos tus grupos', Icons.menu_book_outlined),
        (
          'Justificaciones',
          '1 solicitud por revisar',
          Icons.fact_check_outlined,
        ),
      ];
    case 39:
      return [
        (
          'Bases de Datos · Grupo 2',
          '2026-2 · 32 estudiantes activos',
          Icons.storage_outlined,
        ),
        (
          'Bases de Datos · Grupo 1',
          '2026-2 · 28 estudiantes activos',
          Icons.storage_outlined,
        ),
        (
          'Resumen de mis cursos',
          'Estadísticas del grupo',
          Icons.bar_chart_rounded,
        ),
      ];
    case 42:
      return [
        (
          '28 sep · 10:00–12:00',
          'Clase realizada · registro manual',
          Icons.event_available_outlined,
        ),
        (
          '2 oct · 10:00–12:00',
          'Reprogramada · por vacaciones',
          Icons.event_repeat_outlined,
        ),
        (
          'Añadir clase extraordinaria',
          'Fecha puntual del curso',
          Icons.add_circle_outline,
        ),
      ];
    case 45:
      return [
        (
          'Método seleccionado en el panel de prueba',
          'Cambiar a otro método de demostración',
          Icons.sensors_outlined,
        ),
        (
          'Ventana de registro',
          '15 minutos · hasta las 10:39',
          Icons.timer_outlined,
        ),
      ];
    case 46:
      return [
        (
          '32 estudiantes',
          '24 a tiempo · 2 tarde · 6 pendientes',
          Icons.groups_outlined,
        ),
        ('Control de sesión', 'Ampliar tiempo o cambiar método', Icons.tune),
      ];
    case 47:
      return [
        ('24 a tiempo', '2 tarde · 6 sin registro', Icons.check_circle_outline),
        (
          'Las marcas sin registro quedarán como ausentes.',
          'Podrás revisar y corregir después.',
          Icons.info_outline,
        ),
      ];
    case 51:
    case 54:
      return [
        ('Mateo Ruiz', 'Bases de Datos · Grupo 2', Icons.person_outline),
        (
          'Solicitud por encuentro',
          '24 sep · pendiente de revisión',
          Icons.description_outlined,
        ),
      ];
    case 55:
    case 56:
      return [
        (
          'Ana Gómez',
          'Matrícula activa · 16 asistencias',
          Icons.person_outline,
        ),
        (
          'Mateo Ruiz',
          'Matrícula activa · 12 asistencias',
          Icons.person_outline,
        ),
        (
          'Gestionar estudiantes',
          'Excel, ingresos, invitaciones y retiros',
          Icons.groups_outlined,
        ),
      ];
    case 67:
      return [
        ('Hoy · 08:00', 'Bases de Datos · Grupo 1', Icons.event_outlined),
        (
          'Mañana · 10:00',
          'Programación Móvil · Grupo 2',
          Icons.event_outlined,
        ),
        (
          'Viernes · 14:00',
          'Redes Informáticas · Grupo 1',
          Icons.event_outlined,
        ),
      ];
    case 126:
      return [
        (
          'Programación Móvil',
          '16 asistencias · 3 faltas · 1 justificada',
          Icons.code_rounded,
        ),
        ('Cálculo I', '20 asistencias · 0 faltas', Icons.functions_rounded),
      ];
    case 127:
      return [
        (
          'Estudiantes activos',
          '32 estudiantes · cifra de muestra',
          Icons.groups_outlined,
        ),
        (
          'Clases realizadas',
          '20 de 25 previstas',
          Icons.event_available_outlined,
        ),
        (
          'Pendientes',
          '6 estudiantes sin marca en la sesión',
          Icons.pending_actions,
        ),
      ];
    case 134:
      return [
        (
          'Vincular materia',
          'Ingresa el código que te dio tu docente',
          Icons.add_circle_outline,
        ),
        (
          'Ver mi horario',
          'Cuando tengas una materia vinculada',
          Icons.calendar_month_outlined,
        ),
      ];
    case 140:
      return [
        (
          '28 sep · presente',
          '10:24 · encuentro registrado',
          Icons.check_circle_outline,
        ),
        (
          '24 sep · ausencia',
          'Puedes solicitar una justificación',
          Icons.error_outline,
        ),
      ];
    case 141:
      return [
        (
          'Solicitud enviada',
          'Pendiente de revisión del docente',
          Icons.schedule,
        ),
        (
          'Programación Móvil',
          '24 sep · encuentro individual',
          Icons.code_rounded,
        ),
      ];
    case 142:
    case 143:
    case 155:
      return [
        (
          'Intentar otra vez',
          'El estado es simulado y no cambia el registro real',
          Icons.refresh,
        ),
        (
          'Elegir otro método',
          'Continúa desde la sesión del curso',
          Icons.tune,
        ),
      ];
    default:
      break;
  }
  if (frame.page >= 111 && frame.page <= 125 || frame.page == 35) {
    return [
      (
        'Método de prueba',
        frame.page % 2 == 0
            ? 'Código QR · preparado'
            : 'Bluetooth · disponible',
      ),
      ('Tiempo de registro', '15 minutos · sesión local'),
      ('Cerca de la clase', 'Aula 204 · ubicación simulada'),
    ].map((row) => (row.$1, row.$2, Icons.sensors_outlined)).toList();
  }
  if (frame.page >= 57 && frame.page <= 58 ||
      frame.page == 128 ||
      frame.page == 149) {
    return [
      (
        'Asistencia del curso',
        '80 % · resumen de muestra',
        Icons.bar_chart_rounded,
      ),
      (
        'Clases realizadas',
        '20 de 25 encuentros',
        Icons.event_available_outlined,
      ),
      (
        'Exportación',
        'Disponible solo como acción simulada',
        Icons.download_outlined,
      ),
    ];
  }
  if (frame.role == MockupRole.teacher) {
    return [
      (
        'Bases de Datos',
        'Hoy · 10:00–12:00 · Aula 204',
        Icons.menu_book_outlined,
      ),
      ('Justificaciones', '1 solicitud por revisar', Icons.fact_check_outlined),
      (
        'Calendario',
        'Próxima clase · miércoles',
        Icons.calendar_month_outlined,
      ),
    ];
  }
  if (frame.role == MockupRole.admin) {
    return [
      (
        'Solicitudes docentes',
        '3 pendientes · muestra',
        Icons.person_search_outlined,
      ),
      ('Cursos activos', '24 cursos · cifra ficticia', Icons.school_outlined),
      (
        'Cuentas verificadas',
        '120 perfiles · cifra ficticia',
        Icons.verified_user_outlined,
      ),
    ];
  }
  return [
    (
      'Próxima clase',
      'Lunes · 10:00 · Programación Móvil',
      Icons.calendar_today_outlined,
    ),
    ('Asistencia', '80 % · historial de muestra', Icons.fact_check_outlined),
    ('Justificación', 'Una solicitud pendiente', Icons.description_outlined),
  ];
}

String _actionLabel(MockupFrame frame) {
  switch (frame.page) {
    case 19:
      return 'Registrar asistencia';
    case 20:
      return 'Ver materia';
    case 21:
      return 'Ver comprobante';
    case 22:
      return 'Ver mi horario';
    case 23:
    case 36:
      return 'Vincular otra materia';
    case 24:
    case 25:
    case 26:
    case 29:
      return 'Ver historial';
    case 27:
      return 'Simular registro de asistencia';
    case 28:
    case 137:
      return 'Volver al inicio';
    case 30:
      return 'Entendido';
    case 31:
      return 'Ver mis materias';
    case 34:
      return 'Justificar otra falta';
    case 37:
      return 'Iniciar clase de prueba';
    case 38:
      return 'Ver sesión en curso';
    case 39:
      return 'Crear curso de prueba';
    case 45:
      return 'Abrir registro de prueba';
    case 46:
      return 'Agregar tiempo de prueba';
    case 47:
      return 'Confirmar cierre de prueba';
    case 48:
    case 49:
    case 74:
    case 146:
      return 'Guardar corrección local';
    case 57:
    case 149:
      return 'Generar informe de prueba';
    case 58:
      return 'Ver reglas de cálculo';
    case 67:
      return 'Abrir agenda';
    case 68:
      return 'Archivar curso de prueba';
    case 69:
      return 'Abrir cursos archivados';
    case 70:
      return 'Ver curso archivado';
    case 71:
      return 'Guardar horario futuro';
    case 72:
      return 'Confirmar cambio de horario';
    case 126:
      return 'Ver mis materias';
    case 127:
      return 'Ver cursos';
    case 134:
      return 'Vincular primera materia';
    case 136:
      return 'Volver al inicio';
    case 140:
      return 'Revisar ausencia';
  }
  if (frame.page == 32 || frame.page == 33) {
    return 'Enviar solicitud de prueba';
  }
  if (frame.page == 43) {
    return 'Confirmar cancelación';
  }
  if (frame.page == 44) {
    return 'Guardar nueva fecha';
  }
  if (frame.page == 54) {
    return 'Elegir una decisión';
  }
  if (frame.page >= 111 && frame.page <= 125 ||
      frame.page == 35 ||
      frame.page == 135) {
    return 'Simular lectura válida';
  }
  if (frame.page == 57 || frame.page == 149) {
    return 'Generar informe de prueba';
  }
  if (frame.page == 48 ||
      frame.page == 49 ||
      frame.page == 74 ||
      frame.page == 146) {
    return 'Guardar corrección local';
  }
  if (frame.page == 6 || frame.page == 133 || frame.page == 143) {
    return 'Simular permiso disponible';
  }
  return frame.connected
      ? 'Abrir acción de demostración'
      : 'Continuar recorrido';
}

String _actionMessage(MockupFrame frame) {
  if (frame.page == 43) {
    return 'Clase cancelada solo en la demostración.';
  }
  if (frame.page == 19 ||
      frame.page == 27 ||
      frame.page == 37 ||
      frame.page == 45) {
    return 'La acción se simuló localmente; la asistencia real conserva el flujo C8.';
  }
  if (frame.page == 23 || frame.page == 36 || frame.page == 134) {
    return 'La pantalla de vinculación es una demostración y no crea matrícula.';
  }
  if (frame.page == 47) {
    return 'Cierre de prueba completado en pantalla. No se escribió asistencia.';
  }
  if (frame.page == 43) {
    return 'La cancelación quedó solo en la demostración.';
  }
  if (frame.page == 48 ||
      frame.page == 49 ||
      frame.page == 74 ||
      frame.page == 146) {
    return 'La marca se actualizó localmente; no cambió el resultado C8 real.';
  }
  if (frame.page == 68 || frame.page == 69 || frame.page == 70) {
    return 'El estado de archivo es temporal y solo existe en esta vista.';
  }
  if (frame.page == 71 || frame.page == 72) {
    return 'El horario de muestra se actualizó localmente, sin cambiar el calendario real.';
  }
  if (frame.page == 46) {
    return 'Tiempo ampliado en la vista local; no se prolongó una sesión real.';
  }
  if (frame.page == 32 || frame.page == 33) {
    return 'Solicitud de prueba enviada localmente.';
  }
  if (frame.page == 44) {
    return 'Fecha de prueba guardada localmente.';
  }
  if (frame.page >= 111 && frame.page <= 125 ||
      frame.page == 35 ||
      frame.page == 135) {
    return 'Lectura simulada; no se abrió la cámara ni Bluetooth.';
  }
  if (frame.page == 57 || frame.page == 149) {
    return 'Informe ficticio preparado; no se descargó ningún archivo.';
  }
  if (frame.page == 48 ||
      frame.page == 49 ||
      frame.page == 74 ||
      frame.page == 146) {
    return 'Cambio local guardado en esta demo.';
  }
  return 'Acción completada en la demostración local.';
}

String _resultMessage(MockupFrame frame, bool present) {
  if (frame.page == 43) {
    return 'La clase quedó cancelada solo en este prototipo.';
  }
  if (frame.page == 32 || frame.page == 33) {
    return 'La solicitud queda en estado Pendiente solo en esta demostración.';
  }
  if (frame.page == 44) {
    return 'La fecha se actualizó en el estado local de prueba.';
  }
  if (frame.page == 57 || frame.page == 149) {
    return 'El informe está listo para revisar en pantalla.';
  }
  if (frame.page == 48 ||
      frame.page == 49 ||
      frame.page == 74 ||
      frame.page == 146) {
    return 'Marca ${present ? 'Presente' : 'Ausente'} guardada en el prototipo.';
  }
  return _actionMessage(frame);
}

IconData _actionIcon(MockupFrame frame) {
  if (frame.page == 32 || frame.page == 33) {
    return Icons.send_outlined;
  }
  if (frame.page == 43) {
    return Icons.event_busy_outlined;
  }
  if (frame.page == 44) {
    return Icons.event_available_outlined;
  }
  if (frame.page >= 111 && frame.page <= 125 || frame.page == 35) {
    return Icons.sensors_outlined;
  }
  if (frame.page == 57 || frame.page == 149) {
    return Icons.download_outlined;
  }
  if (frame.page == 48 ||
      frame.page == 49 ||
      frame.page == 74 ||
      frame.page == 146) {
    return Icons.save_outlined;
  }
  return Icons.arrow_forward_rounded;
}
