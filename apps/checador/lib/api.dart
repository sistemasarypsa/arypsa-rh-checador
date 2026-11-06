import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'equipo.dart';

/// El equipo no es un usuario de Supabase: solo puede llamar las funciones
/// rh_* que validan su id + secreto (ver 001_reloj_checador.sql).
class Api {
  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<dynamic> _rpc(String fn, Map<String, dynamic> params, {Duration limite = const Duration(seconds: 15)}) async {
    final t0 = DateTime.now();
    log('Checador', '→ $fn');
    try {
      final r = await _sb.rpc(fn, params: params).then((v) => v).timeout(limite);
      log('Checador', '← $fn OK (${DateTime.now().difference(t0).inMilliseconds} ms)');
      return r;
    } on PostgrestException catch (e) {
      log('Checador', '← $fn ERROR ${e.code}: ${e.message}');
      // RH dio de baja el equipo: se olvida la identidad y la app regresa a
      // la pantalla de activación.
      if (e.message.contains('equipo_invalido')) await equipo.olvidar();
      rethrow;
    } catch (e) {
      log('Checador', '← $fn FALLA DE RED/TIEMPO: $e');
      rethrow;
    }
  }

  static Map<String, dynamic> get _cred => {'p_id': equipo.id, 'p_secreto': equipo.secreto};

  static Future<Map<String, dynamic>> activar(String codigo) async {
    final info = await Equipo.infoDispositivo();
    final r = await _rpc('rh_activar', {'p_codigo': codigo, 'p_info': info});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> kioscoSync(DateTime? desde) async {
    final r = await _rpc(
      'rh_kiosco_sync',
      {..._cred, 'p_desde': desde?.toUtc().toIso8601String()},
      limite: const Duration(seconds: 60),
    );
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> kioscoCodigo(String codigo) async {
    final r = await _rpc('rh_kiosco_codigo', {..._cred, 'p_codigo': codigo});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> kioscoEnrolar(
    String codigo, {
    List<Map<String, dynamic>> plantillas = const [],
    List<Map<String, dynamic>> rostros = const [],
  }) async {
    final r = await _rpc('rh_kiosco_enrolar', {
      ..._cred,
      'p_codigo': codigo,
      'p_plantillas': plantillas,
      'p_rostros': rostros,
    });
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> movilEstado() async {
    final r = await _rpc('rh_movil_estado', _cred);
    return Map<String, dynamic>.from(r as Map);
  }

  /// Devuelve un resultado por checada, en el orden en que el servidor las
  /// procesó (por hora), cada uno con su `cliente_id`.
  static Future<List<Map<String, dynamic>>> checar(List<Map<String, dynamic>> checadas, {Duration? limite}) async {
    final r = await _rpc(
      'rh_checar',
      {..._cred, 'p_checadas': checadas},
      limite: limite ?? const Duration(seconds: 20),
    );
    final lista = (r as Map)['resultados'] as List;
    return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}

/// ¿El error es de red (vale la pena guardar y reintentar) o del servidor
/// (reintentar no lo va a arreglar)?
bool esErrorDeRed(Object e) {
  if (e is TimeoutException) return true;
  if (e is PostgrestException) {
    // Postgrest envuelve fallas de red con código nulo o 5xx.
    final code = e.code ?? '';
    return code.isEmpty || code.startsWith('5') || e.message.contains('SocketException');
  }
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection') ||
      s.contains('HandshakeException');
}
