import 'dart:async';

import 'package:geolocator/geolocator.dart';

class UbicacionError implements Exception {
  UbicacionError(this.mensaje, {this.abrirAjustes = false});

  final String mensaje;

  /// El permiso quedó negado para siempre: solo se arregla en Ajustes.
  final bool abrirAjustes;

  @override
  String toString() => mensaje;
}

class Sitio {
  Sitio({required this.id, required this.nombre, required this.lat, required this.lng, required this.radioM});

  final String id;
  final String nombre;
  final double lat;
  final double lng;
  final int radioM;

  factory Sitio.fromJson(Map<String, dynamic> j) => Sitio(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radioM: (j['radio_m'] as num).toInt(),
      );
}

/// Dónde estoy respecto a la sede más cercana. La misma regla que el servidor
/// (rh_checar): dentro si `distancia - min(precisión, 50) <= radio`.
class Geocerca {
  Geocerca(this.sitio, this.distancia, this.precision);

  final Sitio sitio;
  final double distancia;
  final double precision;

  bool get dentro => distancia - (precision < 50 ? precision : 50) <= sitio.radioM;

  static Geocerca? evaluar(Position p, List<Sitio> sitios) {
    Geocerca? mejor;
    for (final s in sitios) {
      final d = Geolocator.distanceBetween(p.latitude, p.longitude, s.lat, s.lng);
      if (mejor == null || d < mejor.distancia) mejor = Geocerca(s, d, p.accuracy);
    }
    return mejor;
  }
}

class Ubicacion {
  static Position? ultima;

  static Future<void> asegurarPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw UbicacionError('La ubicación (GPS) está apagada. Actívala para poder checar.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) {
      throw UbicacionError('El permiso de ubicación está negado. Actívalo en Ajustes.', abrirAjustes: true);
    }
    if (p == LocationPermission.denied) {
      throw UbicacionError('Sin permiso de ubicación no se puede checar.');
    }
  }

  /// Ubicación fresca. Si el GPS tarda más que [limite], usa la última
  /// conocida si no tiene más de [vigencia].
  static Future<Position> actual({
    Duration limite = const Duration(seconds: 15),
    Duration vigencia = const Duration(minutes: 2),
    LocationAccuracy precision = LocationAccuracy.high,
  }) async {
    await asegurarPermiso();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: precision, timeLimit: limite),
      );
      ultima = p;
      return p;
    } on TimeoutException {
      final u = ultima ?? await Geolocator.getLastKnownPosition();
      if (u != null && DateTime.now().difference(u.timestamp).abs() < vigencia) return u;
      throw UbicacionError('No se pudo obtener la ubicación. Acércate a una ventana o sal al patio e intenta de nuevo.');
    }
  }

  static Future<void> abrirAjustes() => Geolocator.openAppSettings();
}
