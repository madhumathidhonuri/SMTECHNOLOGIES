import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/widgets/glass_card.dart';

class VehicleSearchBar extends StatelessWidget {
  const VehicleSearchBar({
    required this.onSearch,
    required this.onSelect,
    required this.onMenuTap,
    required this.onProfileTap,
    super.key,
  });

  final ValueChanged<String> onSearch;
  final ValueChanged<Vehicle> onSelect;
  final VoidCallback onMenuTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: onMenuTap,
            tooltip: 'Menu',
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: TextField(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search vehicle, driver...',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: onSearch,
            ),
          ),
          const SizedBox(width: Gap.sm),
          IconButton(
            icon: const Icon(Icons.person_rounded, color: Colors.white),
            onPressed: onProfileTap,
            tooltip: 'Profile',
          ),
        ],
      ),
    );
  }
}
