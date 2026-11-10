import 'package:flutter/material.dart';

/// Which organisation the Work section is showing, and who I am in it.
/// Built from GET /corp/orgs/<id>; passed to every Work screen.
class WorkContext {
  final int orgId;
  final String orgName;
  final int meId;
  final String role; // owner / admin / member -- shown only; admin work stays on the website
  final List<Map> myUnits; // teams/departments I'm in: {id, name, kind, my_role}
  final List<Map> orgs; // every organisation I belong to (for the switcher)
  final VoidCallback onSwitchOrg;

  const WorkContext({
    required this.orgId,
    required this.orgName,
    required this.meId,
    required this.role,
    required this.myUnits,
    required this.orgs,
    required this.onSwitchOrg,
  });

  factory WorkContext.fromOrg(Map data, List<Map> orgs, VoidCallback onSwitchOrg) {
    final units = List<Map>.from(data['units'] ?? []);
    final me = data['me'] as Map;
    return WorkContext(
      orgId: (data['org'] as Map)['id'] as int,
      orgName: (data['org'] as Map)['name'] as String? ?? 'Work',
      meId: me['user_id'] as int,
      role: me['role'] as String? ?? 'member',
      myUnits: units.where((u) => u['my_role'] != null).toList(),
      orgs: orgs,
      onSwitchOrg: onSwitchOrg,
    );
  }

  bool get managesATeam => myUnits.any((u) => u['my_role'] == 'manager');

  /// The tabs aren't routes of their own, so their app bars get an explicit
  /// way back to Personal (Home also has the Personal | Work switch).
  Widget leading(BuildContext context) => IconButton(
        icon: const Icon(Icons.person_outline),
        tooltip: 'Switch to Personal',
        onPressed: () => Navigator.of(context).maybePop(),
      );
}
