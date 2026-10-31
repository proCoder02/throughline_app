import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

/// "Meet someone" on the app icon's long-press menu -- one tap from the home
/// screen to the Meet screen, for the moment two people are introducing
/// themselves. Also works on a cold start (the shortcut launches the app).
class MeetShortcut {
  static const _type = 'meet';
  static bool _registered = false;

  /// [open] pushes the Meet screen; the caller decides whether that's
  /// allowed right now (e.g. only when logged in).
  static void register(VoidCallback open) {
    if (_registered) return;
    _registered = true;
    const actions = QuickActions();
    try {
      actions.initialize((type) {
        if (type == _type) open();
      });
      actions.setShortcutItems(const [
        ShortcutItem(type: _type, localizedTitle: 'Meet someone', localizedSubtitle: 'Swap cards in person'),
      ]);
    } catch (e) {
      debugPrint('[meet] shortcut not registered: $e'); // a launcher without shortcuts -- nothing else to do
    }
  }
}
