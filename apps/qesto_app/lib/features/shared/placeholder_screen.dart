import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/qesto_card.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    this.description,
    this.icon = Icons.construction_rounded,
    this.child,
    super.key,
  });

  final String title;
  final String? description;
  final IconData icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: [
            ?child,
            if (child != null && description != null)
              const SizedBox(height: 14),
            if (description != null)
              QestoCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: context.qestoColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: context.qestoColors.primary,
                          size: 31,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        description!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: context.qestoColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
