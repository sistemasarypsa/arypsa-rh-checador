import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'theme.dart';
import 'responsive.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  logConfig('ArypsaRH');
  if (configCompleta) {
    try {
      await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
      log('ArypsaRH', 'Supabase inicializado');
    } catch (e, st) {
      log('ArypsaRH', 'ERROR al inicializar Supabase: $e\n$st');
    }
  } else {
    log('ArypsaRH', 'Sin configuración de Supabase: se muestra la pantalla de aviso');
  }
  runApp(ArypsaRhApp());
}

class ArypsaRhApp extends StatelessWidget {
  const ArypsaRhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        // El tema también usa tamaños escalados: se calcula con la pantalla
        // actual (y se recalcula si cambia, p. ej. pantalla dividida).
        Responsive.actual = Responsive.de(context);
        return MaterialApp(
        builder: Responsive.envolver,
        title: 'Arypsa RH',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.mode,
        locale: Locale('es', 'MX'),
        supportedLocales: [Locale('es', 'MX'), Locale('es'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: configCompleta ? _Puerta() : _SinConfig(),
      );
      },
    );
  }
}

/// Sesión de Supabase guardada en el teléfono: el día a día cae directo al
/// tablero. Si la sesión se cierra (o vence), regresa al acceso.
class _Puerta extends StatelessWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        return auth.currentSession == null ? LoginScreen() : HomeShell();
      },
    );
  }
}

class _SinConfig extends StatelessWidget {
  const _SinConfig();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'Falta la conexión a Supabase',
        message: 'Compila con --dart-define-from-file=supabase.json\n(ver README.md)',
      ),
    );
  }
}
