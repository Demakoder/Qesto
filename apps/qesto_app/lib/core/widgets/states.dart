import 'package:flutter/material.dart';

import '../theme/qesto_theme.dart';
import 'qesto_card.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return QestoCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: context.qestoColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 29, color: context.qestoColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.42, end: 0.88),
      duration: QestoMotion.effective(context, QestoMotion.normal),
      curve: Curves.easeInOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          _SkeletonBlock(height: 142),
          SizedBox(height: 14),
          _SkeletonBlock(height: 260),
          SizedBox(height: 14),
          _SkeletonBlock(height: 72),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.qestoColors.surfaceSecondary,
        borderRadius: QestoGeometry.control,
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: context.qestoColors.secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              'Не удалось загрузить данные',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Попробуйте ещё раз. Ваши данные не были изменены.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.qestoColors.secondaryText,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
