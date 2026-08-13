import 'package:flutter/material.dart';

IconData budgetCategoryIcon(String key) => switch (key) {
  'home' => Icons.home_rounded,
  'bolt' => Icons.bolt_rounded,
  'cart' => Icons.shopping_cart_rounded,
  'cafe' => Icons.local_cafe_rounded,
  'delivery' => Icons.delivery_dining_rounded,
  'transport' => Icons.directions_transit_rounded,
  'car' => Icons.directions_car_rounded,
  'health' => Icons.favorite_rounded,
  'beauty' => Icons.spa_rounded,
  'clothes' => Icons.checkroom_rounded,
  'shopping' => Icons.shopping_bag_rounded,
  'household' => Icons.chair_rounded,
  'phone' => Icons.phone_android_rounded,
  'wifi' => Icons.wifi_rounded,
  'subscriptions' => Icons.subscriptions_rounded,
  'fun' => Icons.sports_esports_rounded,
  'hobby' => Icons.palette_rounded,
  'gift' => Icons.card_giftcard_rounded,
  'family' => Icons.people_alt_rounded,
  'travel' => Icons.flight_rounded,
  'education' => Icons.school_rounded,
  'children' => Icons.child_friendly_rounded,
  'pets' => Icons.pets_rounded,
  'taxes' => Icons.receipt_long_rounded,
  'loans' => Icons.credit_score_rounded,
  'insurance' => Icons.shield_rounded,
  'charity' => Icons.volunteer_activism_rounded,
  'business' => Icons.business_center_rounded,
  'warning' => Icons.warning_amber_rounded,
  'savings' => Icons.savings_rounded,
  'investment' => Icons.trending_up_rounded,
  'fitness' => Icons.fitness_center_rounded,
  'music' => Icons.music_note_rounded,
  'book' => Icons.menu_book_rounded,
  'camera' => Icons.photo_camera_rounded,
  _ => Icons.category_rounded,
};

class BudgetCategoryIcon extends StatelessWidget {
  const BudgetCategoryIcon({
    required this.iconKey,
    required this.color,
    this.size = 48,
    super.key,
  });

  final String iconKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(budgetCategoryIcon(iconKey), color: color, size: size * 0.53),
    );
  }
}
