import 'package:flutter/material.dart';

import '../../../core/theme/qesto_theme.dart';

enum BenefitSection { coupons, promotions, tracked }

class BenefitsSegmentedControl extends StatelessWidget {
  const BenefitsSegmentedControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final BenefitSection value;
  final ValueChanged<BenefitSection> onChanged;

  static const _items = <({BenefitSection value, String label})>[
    (value: BenefitSection.coupons, label: 'Купоны'),
    (value: BenefitSection.promotions, label: 'Акции'),
    (value: BenefitSection.tracked, label: 'Отслеживаемое'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.qestoColors.surface,
        borderRadius: QestoGeometry.control,
        border: Border.all(color: context.qestoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A26324A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: Semantics(
                selected: value == item.value,
                button: true,
                child: InkWell(
                  onTap: () => onChanged(item.value),
                  borderRadius: QestoGeometry.control,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: value == item.value
                          ? context.qestoColors.primarySoft
                          : Colors.transparent,
                      borderRadius: QestoGeometry.control,
                      border: value == item.value
                          ? Border.all(color: const Color(0xFFD7E5FF))
                          : null,
                    ),
                    child: Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: value == item.value
                            ? context.qestoColors.primary
                            : context.qestoColors.secondaryText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
