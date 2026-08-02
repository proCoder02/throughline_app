import 'package:flutter/material.dart';

import '../theme.dart';

/// Rounded pill chip that, unlike Material's Chip/InputChip, lets its label
/// wrap onto multiple lines -- topic tags can now be full questions
/// ("What about the marketing spend?"), not just short noun phrases.
class TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const TagChip({super.key, required this.label, required this.onTap, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: Text(label, style: const TextStyle(color: AppColors.text, fontSize: 13))),
              InkWell(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, top: 1),
                  child: Icon(Icons.close, size: 14, color: AppColors.textSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
