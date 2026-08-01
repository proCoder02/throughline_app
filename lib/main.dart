import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
