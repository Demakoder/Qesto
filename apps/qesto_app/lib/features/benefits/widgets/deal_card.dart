import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../data/models/qesto_models.dart';

class DealVisual {
  const DealVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}

DealVisual visualForKey(String key) => switch (key) {
  'groceries' => const DealVisual(
    Icons.shopping_basket_rounded,
    QestoColors.green,
  ),
  'restaurant' => const DealVisual(
    Icons.lunch_dining_rounded,
    QestoColors.orange,
  ),
  'electronics' => const DealVisual(
    Icons.headphones_rounded,
    QestoColors.primary,
  ),
  'fashion' => const DealVisual(Icons.checkroom_rounded, QestoColors.purple),
  'fuel' => const DealVisual(
    Icons.local_gas_station_rounded,
    Color(0xFF38A85C),
  ),
  'taxi' => const DealVisual(Icons.local_taxi_rounded, QestoColors.orange),
  'delivery' => const DealVisual(
    Icons.delivery_dining_rounded,
    QestoColors.green,
  ),
  'coffee' => const DealVisual(Icons.coffee_rounded, Color(0xFF9A704B)),
  _ => const DealVisual(Icons.local_offer_rounded, QestoColors.primary),
};

class DealCard extends StatelessWidget {
  const DealCard({required this.deal, required this.onTap, super.key});

  final Deal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = visualForKey(deal.visualKey);
    return QestoCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.all(12),
      semanticsLabel: 'Открыть предложение ${deal.title}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DealIcon(visual: visual, badge: deal.badge),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deal.category.toUpperCase(),
                  style: TextStyle(
                    color: visual.color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deal.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  deal.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            color: context.qestoColors.secondaryText,
          ),
        ],
      ),
    );
  }
}

class _DealIcon extends StatelessWidget {
  const _DealIcon({required this.visual, required this.badge});

  final DealVisual visual;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.13),
              borderRadius: QestoGeometry.control,
            ),
            child: Icon(visual.icon, color: visual.color, size: 36),
          ),
          if (badge != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: context.qestoColors.surface,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: visual.color.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: visual.color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TrackedProductCard extends StatelessWidget {
  const TrackedProductCard({
    required this.product,
    required this.onTap,
    super.key,
  });

  final TrackedProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = visualForKey(product.visualKey);
    final falling = product.changePercent < 0;
    return QestoCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.13),
              borderRadius: QestoGeometry.control,
            ),
            child: Icon(visual.icon, color: visual.color, size: 35),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      formatMoney(product.currentPrice, product.currency),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '${falling ? '↓' : '↑'} ${product.changePercent.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: falling
                            ? context.qestoColors.green
                            : context.qestoColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${product.bestMarketplace} • ${product.trackedStoresCount} магазинов',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.qestoColors.secondaryText,
          ),
        ],
      ),
    );
  }
}
