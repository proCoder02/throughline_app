import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/local_cache.dart';
import 'services/push_service.dart';
import 'state/auth_provider.dart';
import 'state/call_provider.dart';
import 'state/listen_provider.dart';
import 'state/notify_provider.dart';
import 'state/theme_provider.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/persona_gate.dart';

final authProvider = AuthProvider();
final notifyProvider = NotifyProvider();
final callProvider = CallProvider();
final listenProvider = ListenProvider();
final themeProvider = ThemeProvider();

/// Lets code with no BuildContext of its own (PushService's notification-tap
/// callback, assigned in home_shell.dart) push a route -- there's no widget
/// backing that callback, so Navigator.of(context) isn't available there.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await LocalCache.instance.init();
  ApiClient.instance.onUnauthorized = () {
    notifyProvider.stop();
    authProvider.forceLogout();
  };
  authProvider.bootstrap();
  themeProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: notifyProvider),
        ChangeNotifierProvider.value(value: callProvider),
        ChangeNotifierProvider.value(value: listenProvider),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const ThroughlineApp(),
    ),
  );

  // Deliberately after runApp(), not before: Firebase.initializeApp() does
  // native/network-adjacent work that has no reason to delay the first
  // frame. No-ops safely if firebase_options.dart is still a placeholder --
  // see PushService.init()/registerDevice(), which awaits this internally.
  PushService.instance.init();
}

class ThroughlineApp extends StatelessWidget {
  const ThroughlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Resolved once, right here at the root, before anything below builds:
    // ThemeMode.system needs the platform's current brightness, light/dark
    // are explicit overrides. isAppDarkMode is a plain global (not a
    // Provider itself) so the dozens of screens already reading AppColors.X
    // directly don't need to change -- setting it here, synchronously
    // before the subtree below builds in this same pass, is what makes
    // those direct reads pick up the right value every rebuild.
    final requestedMode = context.watch<ThemeProvider>().mode;
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    isAppDarkMode = switch (requestedMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Throughline',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isLoading) {
            // No spinner -- this gate now only lasts as long as a single
            // secure-storage read (no network round-trip), so a blank
            // screen matching the native splash's background reads as the
            // splash continuing, not as the app "loading".
            return Scaffold(backgroundColor: AppColors.bgApp, body: const SizedBox.shrink());
          }
          return auth.isAuthenticated ? const PersonaGate() : const AuthScreen();
        },
      ),
    );
  }
}
