import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_litert/flutter_litert.dart';

import '../config.dart';

/// Red MobileFaceNet (LiteRT / TensorFlow Lite) que corre DENTRO del equipo: recibe
/// una cara de 112×112 y devuelve 192 números (su "huella facial"). Dos fotos
/// de la misma persona dan vectores cercanos; de personas distintas, lejanos.
///
/// Modelo: assets/models/mobilefacenet.tflite (licencia BSD-3, ver
/// assets/models/LICENSE-mobilefacenet.txt).
class MotorRostro {
  MotorRostro._(this._interprete, this.lado, this.dim);

  static const modelo = 'mobilefacenet-192';
  static const _asset = 'assets/models/mobilefacenet.tflite';

  final Interpreter _interprete;

  /// Lado de la imagen de entrada (112).
  final int lado;

  /// Largo del vector de salida (192).
  final int dim;

  static MotorRostro? _instancia;

  static Future<MotorRostro> cargar() async {
    final ya = _instancia;
    if (ya != null) return ya;
    // Se carga desde bytes: así no importa cómo resuelva rutas fromAsset.
    final datos = await rootBundle.load(_asset);
    final bytes = datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
    final it = Interpreter.fromBuffer(bytes, options: InterpreterOptions());
    log('Rostro', 'Modelo cargado (${bytes.length ~/ 1024} KB): entrada 112×112×3, salida 192');
    // Medidas fijas de este modelo (verificadas al empaquetarlo).
    return _instancia = MotorRostro._(it, 112, 192);
  }

  /// [rgb] = lado×lado×3 valores ya normalizados a [-1, 1].
  List<double> vector(Float32List rgb) {
    final entrada = rgb.reshape([1, lado, lado, 3]);
    final salida = List.generate(1, (_) => List<double>.filled(dim, 0));
    _interprete.run(entrada, salida);
    return normalizar(salida[0]);
  }

  static List<double> normalizar(List<double> v) {
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    final n = math.sqrt(s);
    if (n == 0) return v;
    return [for (final x in v) x / n];
  }

  /// Distancia euclidiana entre vectores normalizados: 0 = idénticos,
  /// ~1.4 = nada que ver.
  static double distancia(List<double> a, List<double> b) {
    var s = 0.0;
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      final d = a[i] - b[i];
      s += d * d;
    }
    return math.sqrt(s);
  }
}

class CoincidenciaRostro {
  CoincidenciaRostro(this.empleadoId, this.distancia, this.segunda);

  final String empleadoId;
  final double distancia;

  /// Distancia de la segunda persona más parecida (para no confundir dos
  /// caras parecidas).
  final double segunda;
}

/// Las caras registradas de todo el personal, en memoria.
class GaleriaRostros {
  final Map<String, List<List<double>>> _caras = {};

  /// Distancia máxima para aceptar (la manda el servidor por sede).
  double umbral = 0.85;

  /// Ventaja mínima sobre la segunda persona más parecida.
  static const margen = 0.06;

  int get personas => _caras.length;
  bool get vacia => _caras.isEmpty;

  void reemplazar(Map<String, List<List<double>>> caras) {
    _caras
      ..clear()
      ..addAll(caras);
  }

  /// Mejor y segunda mejor persona para [v] (sin aplicar umbral).
  CoincidenciaRostro? buscar(List<double> v, {String? excepto}) {
    String? mejor;
    var d1 = double.infinity;
    var d2 = double.infinity;
    _caras.forEach((id, lista) {
      if (id == excepto) return;
      var d = double.infinity;
      for (final r in lista) {
        final x = MotorRostro.distancia(v, r);
        if (x < d) d = x;
      }
      if (d < d1) {
        d2 = d1;
        d1 = d;
        mejor = id;
      } else if (d < d2) {
        d2 = d;
      }
    });
    final m = mejor;
    if (m == null) return null;
    return CoincidenciaRostro(m, d1, d2);
  }

  /// Coincidencia aceptada o null.
  CoincidenciaRostro? identificar(List<double> v) {
    final c = buscar(v);
    if (c == null) return null;
    final ok = c.distancia <= umbral && (c.segunda - c.distancia) >= margen;
    log('Rostro', 'mejor=${c.empleadoId.substring(0, 6)} d=${c.distancia.toStringAsFixed(3)} '
        '2da=${c.segunda.isFinite ? c.segunda.toStringAsFixed(3) : '-'} umbral=$umbral → ${ok ? 'OK' : 'no'}');
    return ok ? c : null;
  }
}
