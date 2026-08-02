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
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/persona_gate.dart';

final authProvider = AuthProvider();
final notifyProvider = NotifyProvider();
final callProvider = CallProvider();
final listenProvider = ListenProvider();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await LocalCache.instance.init();
  ApiClient.instance.onUnauthorized = () {
    notifyProvider.stop();
    authProvider.forceLogout();
  };
  authProvider.bootstrap();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: notifyProvider),
        ChangeNotifierProvider.value(value: callProvider),
        ChangeNotifierProvider.value(value: listenProvider),
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
    return MaterialApp(
      title: 'Throughline',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return auth.isAuthenticated ? const PersonaGate() : const AuthScreen();
        },
      ),
    );
  }
}
