import 'package:flutter/material.dart';

import '../services/category_service.dart';
import '../theme.dart';
import 'category_menu.dart' show kCategories;

/// Horizontal filter chips (All / Personal / Office / Study / custom) --
/// same category source as CategoryMenu (the 3-dot menu still used
/// elsewhere, e.g. tasks_screen.dart), just surfaced as a persistently
/// visible bar instead of a menu you have to open.
class CategoryChipBar extends StatelessWidget {
  final String? selected; // null = all
  final ValueChanged<String?> onChanged;

  const CategoryChipBar({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: CategoryService().list(),
      builder: (context, snapshot) {
        final names = snapshot.data?.all ?? kCategories;
        return SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _chip(label: 'All', value: null),
              const SizedBox(width: 8),
              for (final c in names) ...[
                _chip(label: _capitalize(c), value: c),
                const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chip({required String label, required String? value}) {
    final isSelected = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onChanged(value),
      selectedColor: AppColors.accent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.text,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: AppColors.panel,
      side: BorderSide(color: isSelected ? AppColors.accent : AppColors.border),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
