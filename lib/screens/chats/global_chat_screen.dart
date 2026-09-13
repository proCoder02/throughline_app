import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/theme_provider.dart';
import '../../theme.dart';
import 'global_chat_body.dart';

/// Persistent cross-session thread (§6): "what did I discuss with Rahul
/// last week?" -- scoped to the whole account, not one conversation.
///
/// The actual thread (load/send/image-attach/etc.) lives in GlobalChatBody
/// now -- this is just that body's original Scaffold/AppBar/gradient shell,
/// kept as a real standalone route (e.g. for a deep link or any future
/// entry point that isn't Home) with its look completely unchanged. Home's
/// own "Chat"/"Add" quick actions embed GlobalChatBody directly instead of
/// pushing this -- see home_screen.dart's own note on why.
class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key});

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.dmGradient,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.dmText),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ask about your people & conversations',
                  style: TextStyle(color: AppColors.dmText, fontSize: 16, fontWeight: FontWeight.w600)),
              Text("Ask across everything you've recorded",
                  style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft)),
            ],
          ),
        ),
        body: const GlobalChatBody(),
      ),
    );
  }
}
