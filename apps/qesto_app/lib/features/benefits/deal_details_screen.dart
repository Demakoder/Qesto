import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../data/models/qesto_models.dart';
import 'widgets/deal_card.dart';

class DealDetailsScreen extends StatelessWidget {
  const DealDetailsScreen({required this.deal, super.key});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final visual = visualForKey(deal.visualKey);
    final conditions = _conditions(deal);
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          deal.kind == DealKind.coupon ? 'Промокод' : 'Акция',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          QestoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: visual.color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(visual.icon, color: visual.color, size: 32),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deal.category.toUpperCase(),
                            style: TextStyle(
                              color: visual.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            deal.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (deal.promoCode != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: QestoColors.primarySoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            deal.promoCode!,
                            style: const TextStyle(
                              color: QestoColors.primary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('copy-promo-code'),
                          tooltip: 'Скопировать промокод',
                          onPressed: () => _copyCode(context),
                          icon: const Icon(Icons.copy_rounded),
                          color: QestoColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 14),
            QestoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Условия',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final condition in conditions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                            color: QestoColors.green,
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: Text(condition)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          QestoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Описание',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(deal.description),
                if (deal.confidence != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Надёжность распознавания: ${deal.confidence}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (deal.targetUrl != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('open-deal-target'),
              onPressed: () => _open(context, deal.targetUrl!),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Открыть предложение'),
            ),
          ],
          if (deal.sourceUrl != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _open(context, deal.sourceUrl!),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Посмотреть источник'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: deal.promoCode!));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Промокод скопирован')));
  }

  Future<void> _open(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }
}

List<String> _conditions(Deal deal) {
  final result = <String>[];
  if (deal.minimumOrder != null) {
    result.add('Минимальный заказ: ${formatMoney(deal.minimumOrder!, 'RUB')}');
  }
  if (deal.maximumDiscount != null) {
    result.add(
      'Максимальная скидка: ${formatMoney(deal.maximumDiscount!, 'RUB')}',
    );
  }
  switch (deal.customerType) {
    case 'new':
      result.add('Для новых пользователей или первого заказа');
    case 'repeat':
      result.add('Для повторного заказа');
    case 'all':
      result.add('Для всех пользователей');
  }
  if (deal.validUntil != null) {
    result.add(
      'Действует до ${formatDate(deal.validUntil!, includeYear: true)}',
    );
  }
  return result;
}
