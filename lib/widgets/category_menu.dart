import 'package:flutter/material.dart';

const kCategories = ['personal', 'office', 'study'];

/// 3-dot category filter menu: All / Personal / Office / Study.
class CategoryMenu extends StatelessWidget {
  final String? selected; // null = all
  final ValueChanged<String?> onChanged;

  const CategoryMenu({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      icon: const Icon(Icons.more_vert),
      initialValue: selected,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('All categories')),
        ...kCategories.map(
          (c) => PopupMenuItem(value: c, child: Text(_capitalize(c))),
        ),
      ],
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
