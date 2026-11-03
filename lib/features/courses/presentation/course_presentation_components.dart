import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

class CoursePage extends StatelessWidget {
  const CoursePage({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(title),
      leading: leading,
      actions: actions,
      foregroundColor: AppColors.text,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontFamily: 'Manrope',
        fontSize: 18,
        height: 26 / 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    body: SafeArea(child: child),
    bottomNavigationBar: bottomNavigationBar,
    floatingActionButton: floatingActionButton,
  );
}

class CourseContent extends StatelessWidget {
  const CourseContent({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 32),
    this.maxWidth = 640,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: padding,
        children: children,
      ),
    ),
  );
}

class CoursePanel extends StatelessWidget {
  const CoursePanel({
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
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: borderColor.withValues(alpha: 0.75)),
    ),
    child: child,
  );
}

class CoursePageHeading extends StatelessWidget {
  const CoursePageHeading({
    super.key,
    required this.title,
    this.description,
    this.eyebrow,
  });

  final String title;
  final String? description;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!.toUpperCase(),
          style: const TextStyle(
            color: AppColors.primary,
            letterSpacing: 1.3,
            fontSize: 11,
            height: 16 / 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        title,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 28,
          height: 36 / 28,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (description != null) ...[
        const SizedBox(height: 8),
        Text(
          description!,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            height: 21 / 14,
          ),
        ),
      ],
    ],
  );
}

class CoursePrimaryButton extends StatelessWidget {
  const CoursePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label, textAlign: TextAlign.center);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: icon == null || busy
          ? FilledButton(onPressed: busy ? null : onPressed, child: child)
          : FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: child,
            ),
    );
  }
}

class CourseSecondaryButton extends StatelessWidget {
  const CourseSecondaryButton({
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
      height: 54,
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

class CourseStateCard extends StatelessWidget {
  const CourseStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.color = AppColors.information,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => CoursePanel(
    color: AppColors.glass.withValues(alpha: 0.48),
    borderColor: color.withValues(alpha: 0.7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      height: 24 / 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
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
        if (action != null) ...[const SizedBox(height: 14), action!],
      ],
    ),
  );
}

class CourseSectionHeading extends StatelessWidget {
  const CourseSectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 18,
            height: 26 / 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class CourseStatePill extends StatelessWidget {
  const CourseStatePill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              height: 17 / 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class CourseLoading extends StatelessWidget {
  const CourseLoading({super.key, this.message = 'Cargando cursos…'});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
