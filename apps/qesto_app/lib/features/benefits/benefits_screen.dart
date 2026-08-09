import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../core/widgets/states.dart';
import '../../data/models/qesto_models.dart';
import '../shared/placeholder_screen.dart';
import 'deal_details_screen.dart';
import 'widgets/benefits_segmented_control.dart';
import 'widgets/deal_card.dart';

class BenefitsScreen extends StatefulWidget {
  const BenefitsScreen({
    required this.coupons,
    required this.promotions,
    required this.trackedProducts,
    super.key,
  });

  final List<Deal> coupons;
  final List<Deal> promotions;
  final List<TrackedProduct> trackedProducts;

  @override
  State<BenefitsScreen> createState() => BenefitsScreenState();
}

class BenefitsScreenState extends State<BenefitsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  var _section = BenefitSection.coupons;
  var _query = '';

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _openDeal(Deal deal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DealDetailsScreen(deal: deal)),
    );
  }

  void _openTracked(TrackedProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(
          title: 'Отслеживание цены',
          description: 'История цены появится здесь',
          icon: Icons.show_chart_rounded,
          child: Column(
            children: [
              QestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    AmountText(
                      formatMoney(product.currentPrice, product.currency),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Лучшая цена: ${product.bestMarketplace}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: QestoColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: QestoColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: QestoColors.border),
                ),
                child: const Center(
                  child: Icon(
                    Icons.area_chart_outlined,
                    color: QestoColors.border,
                    size: 70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('benefits-scroll'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        BenefitsSegmentedControl(
          value: _section,
          onChanged: (value) => setState(() => _section = value),
        ),
        if (_section != BenefitSection.tracked) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('benefits-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Поиск купонов и акций',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('clear-benefits-search'),
                      tooltip: 'Очистить поиск',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildSection(),
        ),
      ],
    );
  }

  Widget _buildSection() {
    return switch (_section) {
      BenefitSection.coupons => _DealsList(
        key: const ValueKey('coupons'),
        deals: _filterDeals(widget.coupons),
        emptyMessage: _query.trim().isEmpty
            ? 'Купонов пока нет'
            : 'Купоны не найдены',
        onTap: _openDeal,
      ),
      BenefitSection.promotions => _DealsList(
        key: const ValueKey('promotions'),
        deals: _filterDeals(widget.promotions),
        emptyMessage: _query.trim().isEmpty
            ? 'Акций пока нет'
            : 'Акции не найдены',
        onTap: _openDeal,
      ),
      BenefitSection.tracked => _TrackedList(
        key: const ValueKey('tracked'),
        products: widget.trackedProducts,
        onTap: _openTracked,
      ),
    };
  }

  List<Deal> _filterDeals(List<Deal> deals) {
    final query = _normalizeSearch(_query);
    if (query.isEmpty) return deals;
    return deals
        .where((deal) {
          final searchable = <String?>[
            deal.title,
            deal.category,
            deal.description,
            deal.promoCode,
            deal.merchantName,
            deal.badge,
          ].whereType<String>().map(_normalizeSearch).join('\n');
          return searchable.contains(query);
        })
        .toList(growable: false);
  }
}

String _normalizeSearch(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');

class _DealsList extends StatelessWidget {
  const _DealsList({
    required this.deals,
    required this.emptyMessage,
    required this.onTap,
    super.key,
  });

  final List<Deal> deals;
  final String emptyMessage;
  final ValueChanged<Deal> onTap;

  @override
  Widget build(BuildContext context) {
    if (deals.isEmpty) {
      return EmptyState(
        message: emptyMessage,
        icon: Icons.local_offer_outlined,
      );
    }
    return Column(
      children: [
        for (final deal in deals) ...[
          DealCard(deal: deal, onTap: () => onTap(deal)),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}

class _TrackedList extends StatelessWidget {
  const _TrackedList({required this.products, required this.onTap, super.key});

  final List<TrackedProduct> products;
  final ValueChanged<TrackedProduct> onTap;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(
        message: 'Вы пока не отслеживаете товары',
        icon: Icons.visibility_off_outlined,
      );
    }
    return Column(
      children: [
        for (final product in products) ...[
          TrackedProductCard(product: product, onTap: () => onTap(product)),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}
