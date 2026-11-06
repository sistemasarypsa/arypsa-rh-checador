import 'package:flutter/foundation.dart';

/// Conexión a Supabase (proyecto arypsa-rh).
///
/// Igual que en la app del scanner: la URL y la llave **anon** van compiladas
/// aquí para que `flutter run` funcione sin parámetros, desde la terminal,
/// VS Code o Android Studio. La llave anon es pública por diseño (la
/// seguridad la ponen RLS y las funciones rh_*); la service_role / secret
/// NUNCA va en una app.
///
/// Para apuntar a otro proyecto sin tocar código:
///   flutter run --dart-define-from-file=supabase.json
const String _urlCompilada = 'https://yqxpkingngbvudwzsbrn.supabase.co';
const String _llaveCompilada =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxeHBraW5nbmdidnVkd3pzYnJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5MjI2NjgsImV4cCI6MjEwNzQ5ODY2OH0.QKrS98-a2OE7SAO3KsN-AMuEEl7RAw2x1cEeEzLbHxQ';

const String _urlDefine = String.fromEnvironment('SUPABASE_URL');
const String _llaveDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

String get kSupabaseUrl => _urlDefine.isNotEmpty ? _urlDefine : _urlCompilada;
String get kSupabaseAnonKey => _llaveDefine.isNotEmpty ? _llaveDefine : _llaveCompilada;

bool get configCompleta => kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty;

/// Log de diagnóstico. Sale en la consola de `flutter run` y en `adb logcat`.
void log(String tag, String msg) => debugPrint('[$tag] $msg');

void logConfig(String app) {
  final origen = _urlDefine.isNotEmpty ? '--dart-define' : 'compilada en config.dart';
  final k = kSupabaseAnonKey;
  log(app, 'Supabase URL: $kSupabaseUrl ($origen)');
  log(app, 'Llave anon: ${k.isEmpty ? '(VACÍA)' : '${k.substring(0, k.length < 12 ? k.length : 12)}… (${k.length} caracteres)'}');
}
