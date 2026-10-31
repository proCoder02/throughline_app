/// Throughline Meet -- swap personality cards by holding two phones
/// together. Everything for the feature lives in this folder; the rest of
/// the app only uses [MeetEntryButton], [MeetShortcut] (app-icon shortcut)
/// or pushes [MeetScreen] itself.
/// Backend counterpart: the meet/ package in the speech2text repo.
library;

import 'package:flutter/material.dart';

import 'meet_screen.dart';

export 'meet_screen.dart' show MeetScreen;
export 'meet_shortcut.dart' show MeetShortcut;

/// App-bar button that opens Meet.
class MeetEntryButton extends StatelessWidget {
  const MeetEntryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.contactless_outlined),
      tooltip: 'Meet someone',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MeetScreen())),
    );
  }
}
