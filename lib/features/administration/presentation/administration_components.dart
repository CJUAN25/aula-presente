import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/teacher_access_repository.dart';

Stream<T> withInitialServerResponseTimeout<T>(Stream<T> source) {
  return Stream<T>.multi((controller) {
    Timer? timer = Timer(const Duration(seconds: 15), () {
      controller.addError(
        const TeacherAccessFailure(TeacherAccessFailureKind.network),
      );
    });
    final subscription = source.listen(
      (value) {
        timer?.cancel();
        timer = null;
        controller.add(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        timer?.cancel();
        timer = null;
        controller.addError(error, stackTrace);
      },
      onDone: () {
        timer?.cancel();
        timer = null;
        controller.close();
      },
    );
    controller.onPause = subscription.pause;
    controller.onResume = subscription.resume;
    controller.onCancel = () async {
      timer?.cancel();
      await subscription.cancel();
    };
  });
}

class AdministrationPage extends StatelessWidget {
  const AdministrationPage({
    super.key,
    required this.title,
    required this.child,
    this.leading,
  });

  final String title;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: leading,
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
    ),
    body: SafeArea(child: child),
  );
}

class AdministrationContent extends StatelessWidget {
  const AdministrationContent({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
    this.maxWidth = 600,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView(padding: padding, children: children),
    ),
  );
}

class AdministrationIntro extends StatelessWidget {
  const AdministrationIntro({super.key, required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 28,
          height: 36 / 28,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (body != null) ...[
        const SizedBox(height: 8),
        Text(
          body!,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 16,
            height: 24 / 16,
          ),
        ),
      ],
    ],
  );
}

class AdministrationCard extends StatelessWidget {
  const AdministrationCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.surface,
    this.borderColor = AppColors.outline,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
}

class AdministrationPrimaryButton extends StatelessWidget {
  const AdministrationPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Text(label, textAlign: TextAlign.center);
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: icon == null
          ? FilledButton(onPressed: onPressed, child: child)
          : FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: child,
            ),
    );
  }
}

class AdministrationSecondaryButton extends StatelessWidget {
  const AdministrationSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Text(label, textAlign: TextAlign.center);
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: icon == null
          ? OutlinedButton(onPressed: onPressed, child: child)
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: child,
            ),
    );
  }
}

class AdministrationSectionTitle extends StatelessWidget {
  const AdministrationSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: AppColors.text,
      fontSize: 18,
      height: 26 / 18,
      fontWeight: FontWeight.w700,
    ),
  );
}

class AdministrationStatus extends StatelessWidget {
  const AdministrationStatus({
    super.key,
    required this.label,
    this.color = AppColors.information,
    this.icon = Icons.schedule_outlined,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.55)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 18 / 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class AdministrationMessageCard extends StatelessWidget {
  const AdministrationMessageCard({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
    this.color = AppColors.information,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AdministrationCard(
    color: AppColors.glass.withValues(alpha: 0.55),
    borderColor: color.withValues(alpha: 0.65),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 24 / 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 14,
                  height: 21 / 14,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AdministrationLoading extends StatelessWidget {
  const AdministrationLoading({super.key, this.message = 'Cargando…'});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
