import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lector_simulado.dart';
import 'lector_zk.dart';

/// Una plantilla registrada, lista para cargarse en el lector.
class PlantillaRegistrada {
  PlantillaRegistrada({required this.empleadoId, required this.dedo, required this.formato, required this.plantilla});

  final String empleadoId;
  final int dedo;
  final String formato;
  final String plantilla;
}

class Coincidencia {
  Coincidencia(this.empleadoId, this.puntaje);

  final String empleadoId;
  final int puntaje;
}

class Captura {
  Captura(this.plantilla, this.calidad);

  final String plantilla;
  final int calidad;
}

/// Se lanza cuando la operación en curso se canceló (otra pantalla tomó el
/// lector, la app se fue a segundo plano, etc.). No es un error.
class LectorCancelado implements Exception {}

class LectorError implements Exception {
  LectorError(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

enum EstadoLector { buscando, listo, desconectado }

/// Contrato de un lector de huella USB.
///
/// La comparación 1:N la hace el SDK del fabricante **en el equipo**: el
/// kiosco carga todas las plantillas al iniciar y al sincronizar, y el
/// servidor nunca recibe la imagen del dedo, solo el id del empleado que
/// coincidió.
abstract class LectorHuella extends ChangeNotifier {
  /// Formato de plantilla que guarda en la base: 'zk10', 'sim', …
  String get formato;
  String get nombre;

  EstadoLector get estado;

  /// En el lector simulado la "huella" se pone tocando la pantalla.
  bool get simulado => false;

  Future<void> iniciar();

  /// Reemplaza todo lo cargado. Solo se cargan las plantillas de su formato.
  Future<void> cargar(List<PlantillaRegistrada> plantillas);

  /// Espera un dedo y lo compara contra lo cargado. `null` = dedo leído pero
  /// no reconocido.
  Future<Coincidencia?> identificar();

  /// Una captura suelta (para el registro).
  Future<Captura> capturar();

  /// Une 3 capturas del mismo dedo en una plantilla de registro.
  Future<Captura> combinar(List<Captura> capturas);

  /// Corta lo que esté esperando un dedo.
  Future<void> cancelar();

  Future<void> cerrar();

  // ---------------------------------------------------------------------

  static const _pref = 'lector_preferido';

  /// 'auto' usa el ZKTeco si el SDK está integrado y el lector conectado;
  /// si no, cae al simulado (con el aviso "MODO PRUEBA" en pantalla).
  static Future<LectorHuella> crear() async {
    String pref = 'auto';
    try {
      pref = (await SharedPreferences.getInstance()).getString(_pref) ?? 'auto';
    } catch (_) {}
    if (pref == 'sim') return LectorSimulado();
    final zk = LectorZk();
    if (await zk.disponible()) return zk;
    return LectorSimulado();
  }

  static Future<void> preferir(String valor) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_pref, valor);
    } catch (_) {}
  }
}
