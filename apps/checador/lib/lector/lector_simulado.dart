import 'dart:async';
import 'dart:math';

import 'lector.dart';

/// Lector de mentira para probar todo el flujo sin hardware: la pantalla
/// muestra un teclado y el número de empleado hace las veces del dedo.
/// Las plantillas se guardan con formato 'sim' y nunca se confunden con las
/// de un lector real.
class LectorSimulado extends LectorHuella {
  final Set<String> _cargados = {};
  Completer<String?>? _espera;
  final _rnd = Random.secure();

  @override
  String get formato => 'sim';

  @override
  String get nombre => 'Lector simulado';

  @override
  bool get simulado => true;

  @override
  EstadoLector get estado => EstadoLector.listo;

  @override
  Future<void> iniciar() async {}

  @override
  Future<void> cargar(List<PlantillaRegistrada> plantillas) async {
    _cargados
      ..clear()
      ..addAll(plantillas.where((p) => p.formato == formato).map((p) => p.empleadoId));
  }

  /// Lo llama la pantalla: [empleadoId] es a quien "pertenece" el dedo
  /// (o null para simular un dedo desconocido).
  void tocar([String? empleadoId]) {
    final e = _espera;
    _espera = null;
    if (e != null && !e.isCompleted) e.complete(empleadoId);
  }

  Future<String?> _esperarToque() {
    final anterior = _espera;
    if (anterior != null && !anterior.isCompleted) anterior.completeError(LectorCancelado());
    final c = Completer<String?>();
    _espera = c;
    return c.future;
  }

  @override
  Future<Coincidencia?> identificar() async {
    final id = await _esperarToque();
    if (id == null || !_cargados.contains(id)) return null;
    return Coincidencia(id, 90 + _rnd.nextInt(10));
  }

  @override
  Future<Captura> capturar() async {
    await _esperarToque();
    return Captura(_ruido(), 70 + _rnd.nextInt(30));
  }

  @override
  Future<Captura> combinar(List<Captura> capturas) async {
    final calidad = capturas.map((c) => c.calidad).reduce(min);
    return Captura('SIM:${_ruido()}', calidad);
  }

  String _ruido() => List.generate(24, (_) => _rnd.nextInt(16).toRadixString(16)).join();

  @override
  Future<void> cancelar() async {
    final e = _espera;
    _espera = null;
    if (e != null && !e.isCompleted) e.completeError(LectorCancelado());
  }

  @override
  Future<void> cerrar() => cancelar();
}
