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
            child: const Text('Volver'),
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

  @override
  Widget build(BuildContext context) {
    final canEditNote =
        _frame.page == 32 ||
        _frame.page == 33 ||
        _frame.page == 44 ||
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
              _courseCard(_frame),
              const SizedBox(height: 12),
              if (_frame.page >= 23 && _frame.page <= 31 ||
                  _frame.page == 37 ||
                  _frame.page == 38 ||
                  _frame.page == 39 ||
                  _frame.page == 40 ||
                  _frame.page == 41) ...[
                _metricsCard(_frame),
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
                      : isCancel
                      ? _confirmCancellation
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
              const Text(
                'Programación Móvil',
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

String _headline(MockupFrame frame) {
  if (frame.page == 19 || frame.page == 20 || frame.page == 21) {
    return 'Hola, Alex';
  }
  if (frame.page == 22) {
    return 'Hoy tienes un respiro.';
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
  if (frame.page == 32 || frame.page == 33) {
    return 'Una falta. Un contexto.';
  }
  if (frame.page == 34) {
    return 'Sigue tus solicitudes.';
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
