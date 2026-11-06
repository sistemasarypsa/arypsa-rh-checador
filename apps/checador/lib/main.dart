import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activar_screen.dart';
import 'config.dart';
import 'equipo.dart';
import 'kiosco_screen.dart';
import 'movil_screen.dart';
import 'theme.dart';
import 'responsive.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  logConfig('Checador');
  if (configCompleta) {
    try {
      await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
      log('Checador', 'Supabase inicializado');
    } catch (e, st) {
      log('Checador', 'ERROR al inicializar Supabase: $e\n$st');
    }
  } else {
    log('Checador', 'Sin configuración de Supabase: se muestra la pantalla de aviso');
  }
  await equipo.cargar();
  runApp(ArypsaChecadorApp());
}

class ArypsaChecadorApp extends StatelessWidget {
  const ArypsaChecadorApp({super.key});

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
        title: 'Arypsa Checador',
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

/// Decide qué es este equipo: sin activar, kiosco de la empresa, o celular
/// de un empleado. Si RH lo da de baja, el servidor lo rechaza, se olvida la
/// identidad y esto regresa solo a la activación.
class _Puerta extends StatelessWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: equipo,
      builder: (context, _) {
        if (equipo.cargando) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!equipo.activado) return ActivarScreen();
        if (equipo.esKiosco) return KioscoScreen(key: ValueKey(equipo.id));
        return MovilScreen(key: ValueKey(equipo.id));
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
