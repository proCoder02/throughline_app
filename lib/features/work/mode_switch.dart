import 'package:flutter/material.dart';

import '../../theme.dart';
import 'work_live.dart';
import 'work_screen.dart';

/// Opens Work (or, if it's already open, takes it to [target]).
Future<void> openWork(NavigatorState nav, {WorkTarget? target}) async {
  final live = WorkLive.instance;
  if (live.openInPlace != null) {
    if (target != null) live.openInPlace!(target);
    return;
  }
  await live.rememberMode('work');
  await nav.push(MaterialPageRoute(settings: const RouteSettings(name: WorkScreen.routeName), builder: (_) => WorkScreen(target: target)));
}

/// Personal | Work, the same switch the website has. Shown only to people
/// in an organisation; the Work side carries the unread work-message count.
class ModeSwitch extends StatelessWidget {
  final bool work; // which side is current
  const ModeSwitch({super.key, required this.work});

  @override
  Widget build(BuildContext context) {
    final live = WorkLive.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: live.hasWork,
      builder: (context, hasWork, _) {
        if (!hasWork && !work) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: live.unread,
          builder: (context, unread, _) => Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.dmPillFill,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.dmBubbleBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _Side(
                label: 'Personal',
                selected: !work,
                onTap: work
                    ? () {
                        live.rememberMode('personal');
                        Navigator.of(context).maybePop();
                      }
                    : null,
              ),
              _Side(
                label: 'Work',
                selected: work,
                badge: work ? 0 : unread,
                onTap: work ? null : () => openWork(Navigator.of(context)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _Side extends StatelessWidget {
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback? onTap;
  const _Side({required this.label, required this.selected, this.badge = 0, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge unread' : label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.dmAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.dmText,
                )),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Badge(label: Text(badge > 99 ? '99+' : '$badge'), backgroundColor: AppColors.unreadBadge),
            ],
          ]),
        ),
      ),
    );
  }
}
