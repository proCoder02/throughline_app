import 'package:flutter/material.dart';

import '../services/category_service.dart';

/// Builtin-only fallback -- used by the register form (auth_screen.dart)
/// where no account/token exists yet to fetch custom categories with.
const kCategories = ['personal', 'office', 'study'];

/// 3-dot category filter menu: All / <builtin + custom categories>.
class CategoryMenu extends StatelessWidget {
  final String? selected; // null = all
  final ValueChanged<String?> onChanged;

  const CategoryMenu({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: CategoryService().list(),
      builder: (context, snapshot) {
        final names = snapshot.data?.all ?? kCategories;
        return PopupMenuButton<String?>(
          icon: const Icon(Icons.more_vert),
          initialValue: selected,
          onSelected: onChanged,
          itemBuilder: (context) => [
            const PopupMenuItem(value: null, child: Text('All categories')),
            ...names.map(
              (c) => PopupMenuItem(value: c, child: Text(_capitalize(c))),
            ),
          ],
        );
      },
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
