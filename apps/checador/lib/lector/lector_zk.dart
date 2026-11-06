import 'package:flutter/services.dart';

import 'lector.dart';

/// Lector ZKTeco (SLK20R / ZK9500 / Live20R) por USB-OTG en Android.
///
/// El lado nativo vive en `android/app/src/main/kotlin/com/arypsa/checador/
/// LectorZkPlugin.kt` y habla con el SDK "ZKFinger Android" del fabricante
/// (los .jar/.so van en android/app/libs, ver README › Lector de huella).
///
/// Contrato del canal `arypsa/lector_zk` (todo en base64):
///   disponible()              -> bool   SDK presente y lector conectado
///   abrir()                   -> void
///   cargar({plantillas:[{id, plantilla}]}) -> int cargadas
///   identificar()             -> {id, puntaje} | null   (bloquea hasta un dedo)
///   capturar()                -> {plantilla, calidad}
///   combinar({plantillas:[b64,b64,b64]}) -> {plantilla, calidad}
///   cancelar(), cerrar()
/// Errores: PlatformException con code 'cancelado' | 'desconectado' | 'sdk'.
class LectorZk extends LectorHuella {
  static const _canal = MethodChannel('arypsa/lector_zk');

  EstadoLector _estado = EstadoLector.buscando;

  @override
  String get formato => 'zk10';

  @override
  String get nombre => 'ZKTeco USB';

  @override
  EstadoLector get estado => _estado;

  void _set(EstadoLector e) {
    if (_estado == e) return;
    _estado = e;
    notifyListeners();
  }

  Future<bool> disponible() async {
    try {
      return await _canal.invokeMethod<bool>('disponible') ?? false;
    } on MissingPluginException {
      return false; // iOS, o Android sin el SDK integrado
    } on PlatformException {
      return false;
    }
  }

  Future<T?> _llamar<T>(String m, [Object? args]) async {
    try {
      return await _canal.invokeMethod<T>(m, args);
    } on PlatformException catch (e) {
      if (e.code == 'cancelado') throw LectorCancelado();
      if (e.code == 'desconectado') _set(EstadoLector.desconectado);
      throw LectorError(e.message ?? 'Falla del lector (${e.code})');
    }
  }

  @override
  Future<void> iniciar() async {
    await _llamar<void>('abrir');
    _set(EstadoLector.listo);
  }

  @override
  Future<void> cargar(List<PlantillaRegistrada> plantillas) async {
    await _llamar<int>('cargar', {
      'plantillas': [
        for (final p in plantillas.where((p) => p.formato == formato))
          // El SDK identifica por número; se manda "empleado:dedo" y se
          // corta al regresar.
          {'id': '${p.empleadoId}:${p.dedo}', 'plantilla': p.plantilla},
      ],
    });
  }

  @override
  Future<Coincidencia?> identificar() async {
    final r = await _llamar<Map<Object?, Object?>>('identificar');
    _set(EstadoLector.listo);
    if (r == null) return null;
    final id = (r['id'] as String).split(':').first;
    return Coincidencia(id, (r['puntaje'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<Captura> capturar() async {
    final r = await _llamar<Map<Object?, Object?>>('capturar');
    return Captura(r!['plantilla'] as String, (r['calidad'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<Captura> combinar(List<Captura> capturas) async {
    final r = await _llamar<Map<Object?, Object?>>('combinar', {
      'plantillas': capturas.map((c) => c.plantilla).toList(),
    });
    return Captura(r!['plantilla'] as String, (r['calidad'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> cancelar() async {
    try {
      await _canal.invokeMethod<void>('cancelar');
    } catch (_) {}
  }

  @override
  Future<void> cerrar() async {
    try {
      await _canal.invokeMethod<void>('cerrar');
    } catch (_) {}
  }
}
