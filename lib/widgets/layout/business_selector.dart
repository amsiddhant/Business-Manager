import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/business.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';

/// Global business scope selector. Owners get an "All Businesses" option that
/// aggregates every accessible business.
class BusinessSelector extends StatelessWidget {
  const BusinessSelector({super.key, this.showAllOption = true});

  final bool showAllOption;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();
    final businesses = data.selectableBusinesses;

    final selectedId = filter.selectedBusinessId;
    // If the current selection is no longer valid, treat as "All".
    final validSelected =
        businesses.any((b) => b.id == selectedId) ? selectedId : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: validSelected,
          hint: const _Selected(icon: Icons.apartment, label: 'All Businesses'),
          isDense: true,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          items: [
            if (showAllOption)
              const DropdownMenuItem<String?>(
                value: null,
                child: _Selected(icon: Icons.apartment, label: 'All Businesses'),
              ),
            for (final Business b in businesses)
              DropdownMenuItem<String?>(
                value: b.id,
                child: _Selected(icon: Icons.business, label: b.name),
              ),
          ],
          onChanged: (value) => filter.selectBusiness(value),
        ),
      ),
    );
  }
}

class _Selected extends StatelessWidget {
  const _Selected({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
