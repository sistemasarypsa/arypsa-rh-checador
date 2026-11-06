import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'cola.dart';
import 'lector/lector.dart';
import 'rostro/motor_rostro.dart';

class TurnoLocal {
  TurnoLocal({required this.entrada, required this.tolerancia, required this.dias});

  /// 'HH:MM'
  final String entrada;
  final int tolerancia;
  final List<int> dias;

  factory TurnoLocal.fromJson(Map<String, dynamic> j) => TurnoLocal(
        entrada: j['entrada'] as String,
        tolerancia: (j['tolerancia_min'] as num?)?.toInt() ?? 0,
        dias: ((j['dias'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      );

  /// Minutos de retardo si la entrada fuera a la hora [t]; null si llega a tiempo.
  int? retardo(DateTime t) {
    final l = t.toLocal();
    if (!dias.contains(l.weekday)) return null;
    final p = entrada.split(':');
    final inicio = DateTime(l.year, l.month, l.day, int.parse(p[0]), int.parse(p[1]));
    final min = l.difference(inicio).inMinutes;
    return min > tolerancia ? min : null;
  }
}

class EmpleadoLocal {
  EmpleadoLocal(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get numero => json['numero'] as String;
  String get nombres => json['nombres'] as String;
  String get nombre => '${json['nombres']} ${json['apellidos'] ?? ''}'.trim();
  String? get puesto => json['puesto'] as String?;
  String? get foto => json['foto'] as String?;
  TurnoLocal? get turno => json['turno'] == null ? null : TurnoLocal.fromJson(Map<String, dynamic>.from(json['turno'] as Map));

  /// Vectores faciales del modelo que usa este kiosco.
  List<List<double>> get rostros => [
        for (final r in (json['rostros'] as List? ?? const []))
          if ((r as Map)['modelo'] == MotorRostro.modelo)
            [for (final x in (r['vector'] as List)) (x as num).toDouble()],
      ];

  List<PlantillaRegistrada> get plantillas => [
        for (final p in (json['plantillas'] as List? ?? const []))
          PlantillaRegistrada(
            empleadoId: id,
            dedo: ((p as Map)['dedo'] as num).toInt(),
            formato: p['formato'] as String,
            plantilla: p['plantilla'] as String,
          ),
      ];
}

/// Copia local del personal con huella. El kiosco checa aunque se caiga el
/// internet: reconoce el dedo contra esta copia y guarda la checada en la cola.
class Catalogo extends ChangeNotifier {
  final _archivo = ArchivoJson('catalogo_kiosco.json');
  final Map<String, EmpleadoLocal> empleados = {};

  /// empleado -> {"fecha": "2026-10-13", "tipo": "entrada"} de lo checado aquí.
  final Map<String, Map<String, dynamic>> _ultimas = {};

  String? sedeNombre;

  /// 'cualquiera' | 'respaldo' | 'doble' (lo define RH por sede).
  String modo = 'respaldo';

  /// Caras registradas, listas para comparar.
  final galeria = GaleriaRostros();
  String? equipoNombre;
  DateTime? _servidorTs;
  DateTime? ultimaSync;
  String? errorSync;
  bool sincronizando = false;
  Timer? _timer;

  LectorHuella? lector;

  EmpleadoLocal? porNumero(String n) {
    final q = n.trim().toUpperCase();
    for (final e in empleados.values) {
      if (e.numero.toUpperCase() == q) return e;
    }
    return null;
  }

  Future<void> iniciar(LectorHuella l) async {
    lector = l;
    final r = await _archivo.leer();
    if (r is Map) {
      sedeNombre = r['sede'] as String?;
      modo = r['modo'] as String? ?? 'respaldo';
      galeria.umbral = (r['umbral'] as num?)?.toDouble() ?? 0.85;
      equipoNombre = r['equipo'] as String?;
      _servidorTs = r['servidor_ts'] == null ? null : DateTime.tryParse(r['servidor_ts'] as String);
      ultimaSync = r['ultima_sync'] == null ? null : DateTime.tryParse(r['ultima_sync'] as String);
      for (final e in (r['empleados'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(e as Map);
        empleados[m['id'] as String] = EmpleadoLocal(m);
      }
      final u = r['ultimas'];
      if (u is Map) {
        u.forEach((k, v) => _ultimas[k as String] = Map<String, dynamic>.from(v as Map));
      }
    }
    await _cargarEnLector();
    notifyListeners();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sincronizar());
    unawaited(sincronizar());
  }

  Future<void> _cargarEnLector() async {
    galeria.reemplazar({
      for (final e in empleados.values)
        if (e.rostros.isNotEmpty) e.id: e.rostros,
    });
    final l = lector;
    if (l == null) return;
    try {
      await l.cargar([for (final e in empleados.values) ...e.plantillas]);
    } catch (_) {}
  }

  Future<void> _guardar() => _archivo.escribir({
        'sede': sedeNombre,
        'modo': modo,
        'umbral': galeria.umbral,
        'equipo': equipoNombre,
        'servidor_ts': _servidorTs?.toIso8601String(),
        'ultima_sync': ultimaSync?.toIso8601String(),
        'empleados': [for (final e in empleados.values) e.json],
        'ultimas': _ultimas,
      });

  /// [completa] ignora lo incremental y baja todo de nuevo.
  Future<void> sincronizar({bool completa = false}) async {
    if (sincronizando) return;
    sincronizando = true;
    notifyListeners();
    try {
      final r = await Api.kioscoSync(completa ? null : _servidorTs);
      final activos = ((r['activos'] as List?) ?? const []).map((e) => e as String).toSet();
      if (completa) empleados.clear();
      for (final e in (r['empleados'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(e as Map);
        empleados[m['id'] as String] = EmpleadoLocal(m);
      }
      empleados.removeWhere((id, _) => !activos.contains(id));
      final sede = r['sede'] as Map?;
      sedeNombre = sede?['nombre'] as String?;
      modo = sede?['modo_biometrico'] as String? ?? 'respaldo';
      galeria.umbral = (sede?['umbral_rostro'] as num?)?.toDouble() ?? 0.85;
      equipoNombre = (r['equipo'] as Map?)?['nombre'] as String?;
      _servidorTs = DateTime.tryParse(r['servidor_ts'] as String? ?? '');
      ultimaSync = DateTime.now();
      errorSync = null;
      cola.marcarEnLinea(true);
      await _guardar();
      await _cargarEnLector();
      unawaited(cola.enviar());
    } catch (e) {
      errorSync = e.toString();
      if (esErrorDeRed(e)) cola.marcarEnLinea(false);
    } finally {
      sincronizando = false;
      notifyListeners();
    }
  }

  static String _hoy(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month}-${l.day}';
  }

  /// Adivinanza local (solo se usa si no hay red): alterna con lo último que
  /// se checó EN ESTE kiosco hoy. El servidor recalcula al sincronizar.
  String tipoProbable(String empleadoId, DateTime t) {
    final u = _ultimas[empleadoId];
    if (u != null && u['fecha'] == _hoy(t) && u['tipo'] == 'entrada') return 'salida';
    return 'entrada';
  }

  Future<void> anotar(String empleadoId, DateTime t, String tipo) async {
    _ultimas[empleadoId] = {'fecha': _hoy(t), 'tipo': tipo};
    // Limpia lo de días anteriores.
    _ultimas.removeWhere((_, v) => v['fecha'] != _hoy(DateTime.now()));
    await _guardar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final catalogo = Catalogo();
