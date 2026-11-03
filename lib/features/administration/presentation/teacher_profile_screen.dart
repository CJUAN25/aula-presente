import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/domain/auth_access.dart';
import '../../auth/domain/auth_repository.dart';
import 'administration_components.dart';
import 'teacher_access_screens.dart';

class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({
    super.key,
    required this.access,
    required this.authRepository,
    required this.onChangeSpace,
    required this.onSignOut,
  });

  final AuthAccess access;
  final AuthRepository authRepository;
  final VoidCallback onChangeSpace;
  final Future<void> Function() onSignOut;

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  late final StreamSubscription<AuthAccess> _accessSubscription;
  AuthAccess? _currentAccess;
  Object? _streamError;
  bool _changingSpace = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _currentAccess = widget.access;
    try {
      _accessSubscription = widget.authRepository.watchAccess().listen(
        (access) {
          if (mounted) {
            setState(() {
              _currentAccess = access;
              _streamError = null;
            });
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _streamError = error);
        },
      );
    } catch (error) {
      _accessSubscription = const Stream<AuthAccess>.empty().listen((_) {});
      _streamError = error;
    }
  }

  @override
  void dispose() {
    _accessSubscription.cancel();
    super.dispose();
  }

  Future<void> _changeSpace() async {
    if (_changingSpace) return;
    setState(() => _changingSpace = true);
    try {
      final latest = await widget.authRepository.refreshAccess();
      if (!mounted) return;
      setState(() => _currentAccess = latest);
      if (hasUsableAuthAccess(latest) && hasAuthRole(latest, 'student')) {
        widget.onChangeSpace();
      } else {
        _showMessage('Tu cuenta ya no tiene un espacio estudiante autorizado.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(teacherAccessErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _changingSpace = false);
    }
  }

  Future<void> _confirmSignOut() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres cerrar la sesión de esta cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        _showMessage('No pudimos cerrar sesión. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final access = _currentAccess ?? widget.access;
    final hasTeacherAccess =
        _streamError == null &&
        hasUsableAuthAccess(access) &&
        hasAuthRole(access, 'teacher');
    return AdministrationPage(
      title: 'Perfil docente',
      child: hasTeacherAccess ? _profileContent(access) : _accessUnavailable(),
    );
  }

  Widget _profileContent(AuthAccess access) => AdministrationContent(
    children: [
      const AdministrationIntro(
        title: 'Tu perfil docente',
        body: 'Este es el perfil de la cuenta con la que iniciaste sesión.',
      ),
      const SizedBox(height: 20),
      AdministrationCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdministrationStatus(
              label: 'Identidad verificada por tu sesión',
              icon: Icons.verified_user_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            _ProfileField(
              label: 'Nombre',
              value: _valueOrFallback(access.name),
            ),
            const SizedBox(height: 12),
            _ProfileField(
              label: 'Correo',
              value: _valueOrFallback(access.email),
            ),
            if (access.studentCode?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _ProfileField(
                label: 'Código de estudiante',
                value: access.studentCode!.trim(),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      AdministrationCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdministrationSectionTitle('Permisos actuales'),
            const SizedBox(height: 8),
            const Text(
              'Estos roles provienen del perfil autorizado de tu cuenta.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: access.roles
                  .map((role) => _RoleTag(role: role))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const AdministrationMessageCard(
        title: 'Cursos y estadísticas',
        body: 'Esta cuenta no muestra cursos ni estadísticas hasta que esos datos estén disponibles en el sistema.',
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 20),
      AdministrationPrimaryButton(
        label: _changingSpace
            ? 'Comprobando permisos…'
            : 'Cambiar a estudiante',
        icon: _changingSpace ? null : Icons.school_outlined,
        onPressed: _changingSpace || !hasAuthRole(access, 'student')
            ? null
            : _changeSpace,
      ),
      if (!hasAuthRole(access, 'student')) ...[
        const SizedBox(height: 8),
        const Text(
          'No hay un espacio estudiante autorizado para esta cuenta.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            height: 18 / 12,
          ),
        ),
      ],
      const SizedBox(height: 8),
      AdministrationSecondaryButton(
        label: _signingOut ? 'Cerrando sesión…' : 'Cerrar sesión',
        icon: Icons.logout,
        onPressed: _signingOut ? null : _confirmSignOut,
      ),
    ],
  );

  Widget _accessUnavailable() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AdministrationMessageCard(
        title: _streamError != null
            ? 'No pudimos confirmar tus permisos'
            : 'El acceso docente ya no está disponible',
        body: _streamError != null
            ? 'Comprueba tu conexión e inténtalo de nuevo.'
            : 'Tu sesión o tus roles cambiaron. Vuelve al inicio para elegir un espacio autorizado.',
        icon: Icons.lock_outline,
        color: AppColors.danger,
      ),
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 18 / 12,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        softWrap: true,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
          height: 24 / 16,
        ),
      ),
    ],
  );
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role.toLowerCase()) {
      'student' => 'Estudiante',
      'teacher' => 'Docente',
      'admin' => 'Administración',
      _ => role,
    };
    return Chip(
      avatar: const Icon(Icons.verified_outlined, size: 16),
      label: Text(label),
      backgroundColor: AppColors.glass,
      side: const BorderSide(color: AppColors.outline),
      labelStyle: const TextStyle(color: AppColors.text),
    );
  }
}

String _valueOrFallback(String? value) =>
    value?.trim().isNotEmpty == true ? value!.trim() : 'No disponible';
