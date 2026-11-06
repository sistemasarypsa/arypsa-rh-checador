import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'motor_rostro.dart';

/// Lo que la cámara ve en un cuadro procesado.
class LecturaRostro {
  LecturaRostro({
    required this.tamano,
    this.caja,
    this.aviso,
    this.vector,
    this.yaw = 0,
    this.ojos,
    this.calidad = 0,
    this.recorte,
  });

  /// Tamaño de la imagen ya derecha (para dibujar la caja encima).
  final Size tamano;

  /// Cara más grande, en coordenadas de la imagen derecha.
  final Rect? caja;

  /// Por qué todavía no sirve ("Acércate", "Mira de frente"…). null = sirve.
  final String? aviso;

  /// Vector facial (solo cuando la cara sirve).
  final List<double>? vector;

  /// Giro izquierda/derecha de la cabeza, en grados.
  final double yaw;

  /// Probabilidad de ojos abiertos (la menor de los dos), si se pudo medir.
  final double? ojos;

  /// 0–100: qué tan buena es la cara para registrarla.
  final int calidad;

  /// La cara recortada a 112×112 (solo si se pidió, para revisar el recorte).
  final img.Image? recorte;

  bool get hayCara => caja != null;
  bool get sirve => vector != null;
}

/// Cámara frontal + detector de caras (Google ML Kit) + MobileFaceNet.
/// Todo en el equipo, nada sale a internet.
class CamaraRostro extends ChangeNotifier {
  CamaraRostro({this.intervalo = const Duration(milliseconds: 220)});

  /// Cada cuánto se procesa un cuadro (la cámara manda ~30 por segundo).
  Duration intervalo;

  /// Guardar el recorte de 112×112 en cada lectura (pantalla de registro).
  bool pedirRecorte = false;

  CameraController? controlador;
  CameraDescription? _camara;
  MotorRostro? _motor;
  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.12,
    ),
  );

  String? error;
  bool listo = false;

  /// El equipo tiene cámara frontal (la TC51, por ejemplo, no).
  bool hayFrontal = false;

  static const _prefFrontal = 'camara_frontal';
  static const _prefGiro = 'camara_giro_extra';

  /// Giro extra (0/90/180/270) que se suma al calculado. Algunos equipos
  /// (Zebra, tablets montadas) reportan mal la orientación del sensor y ML
  /// Kit no encuentra caras aunque la imagen esté bien. Mientras no se haya
  /// visto ninguna cara se prueban los cuatro giros; el que funciona se
  /// guarda y ya no se mueve.
  int _giroExtra = 0;
  bool _giroFijo = false;
  int _sinCaraSeguidos = 0;

  /// Cambia la preferencia de cámara; aplica la próxima vez que se inicie.
  static Future<void> preferirFrontal(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefFrontal, v);
    } catch (_) {}
  }
  bool _ocupado = false;
  bool _pausada = false;
  DateTime _ultimo = DateTime.fromMillisecondsSinceEpoch(0);

  final _lecturas = StreamController<LecturaRostro>.broadcast();
  Stream<LecturaRostro> get lecturas => _lecturas.stream;

  bool get espejo => _camara?.lensDirection == CameraLensDirection.front;

  /// Se apagó a propósito (otra pantalla usa la cámara, p. ej. el escáner
  /// de QR). El vigilante no la reabre mientras esté así.
  bool _suspendida = false;
  bool _cerrada = false;
  bool _abriendo = false;
  Timer? _vigilante;
  DateTime _ultimoCuadro = DateTime.now();
  DateTime _ultimoIntento = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> iniciar() async {
    try {
      _motor = await MotorRostro.cargar();
    } catch (e) {
      error = 'No se pudo cargar el modelo de reconocimiento: $e';
      log('Rostro', 'ERROR modelo: $e');
      notifyListeners();
      return;
    }
    await _abrir();
    // Vigilante: la TC51 (y otros Android) solo dejan abrir UNA cámara a la
    // vez. Si otra cosa se la lleva (escáner de QR, otra app) o el sistema la
    // corta, los cuadros dejan de llegar y la vista se queda negra. Si pasan
    // 4 s sin cuadros, se reabre sola.
    _vigilante ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_cerrada || _suspendida || _abriendo) return;
      // Si el último intento falló, se espera más antes de reintentar.
      if (error != null && DateTime.now().difference(_ultimoIntento).inSeconds < 10) return;
      final sinCuadros = DateTime.now().difference(_ultimoCuadro).inSeconds;
      if (controlador == null || sinCuadros >= 4) {
        log('Rostro', 'Vigilante: ${controlador == null ? 'cámara cerrada' : '$sinCuadros s sin cuadros'} → se reabre');
        unawaited(reabrir());
      }
    });
  }

  /// Suelta la cámara para que otra pantalla la use (escáner de QR).
  Future<void> suspender() async {
    _suspendida = true;
    await _soltar();
    notifyListeners();
  }

  /// Vuelve a tomar la cámara después de [suspender].
  Future<void> reanudar() async {
    _suspendida = false;
    await reabrir();
  }

  Future<void> reabrir() async {
    if (_abriendo || _cerrada) return;
    await _soltar();
    await _abrir();
  }

  Future<void> _soltar() async {
    final c = controlador;
    controlador = null;
    listo = false;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _abrir() async {
    if (_abriendo || _cerrada) return;
    _abriendo = true;
    _ultimoIntento = DateTime.now();
    try {
      // Tras soltarla otra pantalla (escáner de QR) Android tarda en liberar
      // la cámara: si el primer intento falla, se reintenta con pausas.
      for (var intento = 1; intento <= 4; intento++) {
        if (_cerrada || _suspendida) return;
        final ok = await _abrirUnaVez(intento);
        if (ok || _cerrada || _suspendida) break;
        if (intento < 4) await Future<void>.delayed(Duration(milliseconds: 700 * intento));
      }
    } finally {
      _abriendo = false;
      _ultimoIntento = DateTime.now();
      _ultimoCuadro = DateTime.now();
      if (!_cerrada) notifyListeners();
    }
  }

  Future<bool> _abrirUnaVez(int intento) async {
    CameraController? c;
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) throw Exception('Este equipo no tiene cámara.');
      log('Rostro', 'Cámaras: ${camaras.map((x) => '${x.name}=${x.lensDirection.name}').join(', ')} (intento $intento)');
      // Por default la frontal; desde el menú del kiosco se puede forzar la
      // trasera (p. ej. la TC51, que solo trae trasera).
      var frontal = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        frontal = prefs.getBool(_prefFrontal) ?? true;
        final g = prefs.getInt(_prefGiro);
        if (g != null) {
          _giroExtra = g;
          _giroFijo = true;
        }
      } catch (_) {}
      final buscada = frontal ? CameraLensDirection.front : CameraLensDirection.back;
      final cam = camaras.firstWhere((x) => x.lensDirection == buscada, orElse: () => camaras.first);
      _camara = cam;
      hayFrontal = camaras.any((x) => x.lensDirection == CameraLensDirection.front);
      c = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      if (_cerrada || _suspendida) {
        await c.dispose();
        return false;
      }
      _ultimoCuadro = DateTime.now();
      await c.startImageStream(_cuadro);
      controlador = c;
      listo = true;
      error = null;
      log('Rostro', 'Cámara lista: ${cam.name} sensor=${cam.sensorOrientation}° ${c.value.previewSize}');
      return true;
    } on CameraException catch (e, st) {
      error = e.code == 'CameraAccessDenied'
          ? 'Sin permiso de cámara. Actívalo en Ajustes › Apps › Arypsa Checador.'
          : 'No se pudo abrir la cámara (${e.code}: ${e.description ?? ''}).';
      log('Rostro', 'ERROR cámara (intento $intento): ${e.code} ${e.description}\n$st');
    } catch (e, st) {
      error = 'No se pudo iniciar la cámara: $e';
      log('Rostro', 'ERROR iniciar (intento $intento): $e\n$st');
    }
    // Falló: se suelta lo que haya quedado a medias antes de reintentar.
    controlador = null;
    listo = false;
    try {
      await c?.dispose();
    } catch (_) {}
    return false;
  }

  void pausar(bool v) => _pausada = v;

  Future<void> cerrar() async {
    _cerrada = true;
    _vigilante?.cancel();
    await _soltar();
    await _detector.close();
    await _lecturas.close();
  }

  // -------------------------------------------------------------------------

  static const _orientaciones = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Grados (en sentido horario) que hay que girar el cuadro para que la
  /// cara quede derecha. Misma fórmula que el ejemplo oficial de ML Kit.
  int _rotacion() {
    final cam = _camara!;
    if (Platform.isIOS) return 0;
    final dispositivo = _orientaciones[controlador?.value.deviceOrientation] ?? 0;
    final base = cam.lensDirection == CameraLensDirection.front
        ? (cam.sensorOrientation + dispositivo) % 360
        : (cam.sensorOrientation - dispositivo + 360) % 360;
    return (base + _giroExtra) % 360;
  }

  /// Lleva la cuenta de cuadros sin cara para probar otro giro, y fija el
  /// giro en cuanto aparece la primera cara.
  void _ajustarGiro(bool hayCara) {
    if (_giroFijo) return;
    if (hayCara) {
      _giroFijo = true;
      log('Rostro', 'Cara encontrada con giro extra $_giroExtra°: se queda fijo');
      SharedPreferences.getInstance().then((p) => p.setInt(_prefGiro, _giroExtra)).catchError((_) => true);
      return;
    }
    // Solo cuenta si la imagen tiene luz (con la cámara tapada o a oscuras no
    // tiene caso girar).
    if (luz < 35) return;
    if (++_sinCaraSeguidos < 12) return;
    _sinCaraSeguidos = 0;
    _giroExtra = (_giroExtra + 90) % 360;
    log('Rostro', 'Sin caras: probando giro extra $_giroExtra°');
  }

  /// Olvida el giro aprendido (menú del kiosco, por si se cambia de equipo
  /// o de montaje).
  static Future<void> olvidarGiro() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_prefGiro);
    } catch (_) {}
  }

  // --- Diagnóstico (sale en consola cada 5 s y en pantalla si algo falla) ---
  int cuadros = 0;
  int procesados = 0;
  int conCara = 0;
  int errores = 0;

  /// Brillo medio (0–255) del último cuadro. ~0 = la cámara entrega negro.
  int luz = -1;
  String? ultimoError;
  DateTime _ultimoResumen = DateTime.now();

  /// Última vez que la IA terminó de analizar un cuadro (para mostrar que
  /// está trabajando).
  DateTime? ultimoProcesado;

  String get diagnostico => 'cámara ${_camara?.lensDirection.name ?? '?'} · cuadros $cuadros · '
      'procesados $procesados · con cara $conCara · luz $luz · giro ${_rotacionSegura()}°'
      '${errores > 0 ? ' · errores $errores' : ''}'
      '${ultimoError != null ? '\n$ultimoError' : ''}';

  int _rotacionSegura() {
    try {
      return _camara == null ? 0 : _rotacion();
    } catch (_) {
      return 0;
    }
  }

  /// Brillo medio del plano Y (o BGRA) con una muestra de 16×16 puntos.
  static int _luzDe(CameraImage im) {
    final p = im.planes.first;
    final b = p.bytes;
    final px = Platform.isIOS ? 4 : 1;
    var s = 0, n = 0;
    for (var j = 0; j < 16; j++) {
      final y = (im.height * (j + 0.5) / 16).floor();
      for (var i = 0; i < 16; i++) {
        final x = (im.width * (i + 0.5) / 16).floor();
        final k = y * p.bytesPerRow + x * px;
        if (k + 2 < b.length) {
          s += Platform.isIOS ? (b[k] + b[k + 1] * 2 + b[k + 2]) ~/ 4 : b[k];
          n++;
        }
      }
    }
    return n == 0 ? 0 : s ~/ n;
  }

  void _resumen() {
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoResumen).inSeconds < 5) return;
    _ultimoResumen = ahora;
    log('Rostro', diagnostico.replaceAll('\n', ' · '));
    notifyListeners();
  }

  Future<void> _cuadro(CameraImage im) async {
    cuadros++;
    _ultimoCuadro = DateTime.now();
    if (cuadros == 1 || cuadros % 15 == 0) luz = _luzDe(im);
    if (cuadros == 1) {
      log('Rostro', 'Primer cuadro: ${im.width}x${im.height} formato=${im.format.raw} '
          'planos=${im.planes.length} bytesPorRenglon=${im.planes.first.bytesPerRow} '
          'bytes=${im.planes.first.bytes.length} rotación=${_rotacion()}° luz=$luz');
    }
    _resumen();
    if (_ocupado || _pausada || _lecturas.isClosed) return;
    final ahora = DateTime.now();
    if (ahora.difference(_ultimo) < intervalo) return;
    _ultimo = ahora;
    _ocupado = true;
    try {
      final lectura = await _procesar(im);
      procesados++;
      ultimoProcesado = DateTime.now();
      if (lectura != null) {
        if (lectura.hayCara) conCara++;
        _ajustarGiro(lectura.hayCara);
        if (!_lecturas.isClosed) _lecturas.add(lectura);
      }
    } catch (e, st) {
      errores++;
      final nuevo = e is PlatformException ? '${e.code}: ${e.message}${e.details != null ? ' · ${e.details}' : ''}' : '$e';
      if (nuevo != ultimoError) {
        log('Rostro', 'cuadro con error: $e\n$st');
        ultimoError = nuevo;
        notifyListeners();
      }
    } finally {
      _ocupado = false;
    }
  }

  Future<LecturaRostro?> _procesar(CameraImage im) async {
    final cuadro = _Cuadro.desde(im, _rotacion());
    if (cuadro == null) {
      throw Exception('Formato de cámara no soportado: ${im.planes.length} planos, formato ${im.format.raw}');
    }

    final caras = await _detector.processImage(cuadro.inputImage);
    final tam = cuadro.tamanoDerecho;
    if (caras.isEmpty) return LecturaRostro(tamano: tam);

    // La más grande: la persona de enfrente, no la de atrás en la fila.
    final f = caras.reduce((a, b) => a.boundingBox.width * a.boundingBox.height >=
            b.boundingBox.width * b.boundingBox.height
        ? a
        : b);
    final caja = f.boundingBox;
    final yaw = f.headEulerAngleY ?? 0;
    final roll = f.headEulerAngleZ ?? 0;
    final ojoI = f.leftEyeOpenProbability;
    final ojoD = f.rightEyeOpenProbability;
    final ojos = (ojoI == null || ojoD == null) ? null : math.min(ojoI, ojoD);

    final relativo = caja.width / tam.width;
    String? aviso;
    if (relativo < 0.20) {
      aviso = 'Acércate un poco';
    } else if (caja.left < 0 || caja.top < 0 || caja.right > tam.width || caja.bottom > tam.height) {
      aviso = 'Centra tu cara';
    } else if (yaw.abs() > 18 || roll.abs() > 15) {
      aviso = 'Mira de frente a la cámara';
    } else if (ojos != null && ojos < 0.35) {
      aviso = 'Abre los ojos';
    }

    // Calidad para el registro: tamaño, frontalidad y luz.
    final luz = cuadro.brilloMedio(caja);
    if (aviso == null && luz < 55) aviso = 'Falta luz en tu cara';
    final calidad = (100 -
            (yaw.abs() * 1.5) -
            (roll.abs() * 1.5) -
            (relativo < 0.3 ? (0.3 - relativo) * 150 : 0) -
            (luz < 80 ? (80 - luz) : 0))
        .clamp(0, 100)
        .round();

    if (aviso != null) {
      return LecturaRostro(tamano: tam, caja: caja, aviso: aviso, yaw: yaw, ojos: ojos, calidad: calidad);
    }

    final motor = _motor!;
    final (entrada, recorte) = cuadro.recortar(caja, motor.lado, conImagen: pedirRecorte);
    final v = motor.vector(entrada);
    return LecturaRostro(
      tamano: tam,
      caja: caja,
      vector: v,
      yaw: yaw,
      ojos: ojos,
      calidad: calidad,
      recorte: recorte,
    );
  }
}

/// Un cuadro de la cámara en NV21 (Android) o BGRA (iOS), con lo necesario
/// para ML Kit y para recortar la cara sin convertir el cuadro completo.
class _Cuadro {
  _Cuadro._(this.bytes, this.ancho, this.alto, this.paso, this.rotacion, this.bgra);

  final Uint8List bytes;
  final int ancho;
  final int alto;

  /// Bytes por renglón del plano Y (o del BGRA).
  final int paso;
  final int rotacion;
  final bool bgra;

  static _Cuadro? desde(CameraImage im, int rotacion) {
    if (Platform.isIOS) {
      final p = im.planes.first;
      return _Cuadro._(p.bytes, im.width, im.height, p.bytesPerRow, rotacion, true);
    }
    if (im.planes.length == 1) {
      final p = im.planes.first;
      final w = im.width, h = im.height;
      if (p.bytesPerRow == w && p.bytes.length >= w * h * 3 ~/ 2) {
        return _Cuadro._(p.bytes, w, h, w, rotacion, false);
      }
      // Renglones con relleno: ML Kit quiere el NV21 "apretado".
      final paso = p.bytesPerRow;
      final out = Uint8List(w * h + w * h ~/ 2);
      for (var r = 0; r < h * 3 ~/ 2; r++) {
        final ini = r * paso;
        if (ini + w > p.bytes.length) break;
        out.setRange(r * w, r * w + w, p.bytes, ini);
      }
      return _Cuadro._(out, w, h, w, rotacion, false);
    }
    if (im.planes.length == 3) {
      return _Cuadro._(_yuv420aNv21(im), im.width, im.height, im.width, rotacion, false);
    }
    if (im.planes.length == 2) {
      // Y + VU intercalado en dos planos: se pegan en un solo NV21.
      final y = im.planes[0], vu = im.planes[1];
      final w = im.width, h = im.height;
      final out = Uint8List(w * h + w * h ~/ 2);
      for (var r = 0; r < h; r++) {
        out.setRange(r * w, r * w + w, y.bytes, r * y.bytesPerRow);
      }
      for (var r = 0; r < h ~/ 2; r++) {
        final n = math.min(w, vu.bytes.length - r * vu.bytesPerRow);
        if (n <= 0) break;
        out.setRange(w * h + r * w, w * h + r * w + n, vu.bytes, r * vu.bytesPerRow);
      }
      return _Cuadro._(out, w, h, w, rotacion, false);
    }
    return null;
  }

  /// Algunos Android entregan YUV_420_888 en 3 planos aunque se pida NV21.
  static Uint8List _yuv420aNv21(CameraImage im) {
    final w = im.width, h = im.height;
    final out = Uint8List(w * h + (w * h ~/ 2));
    final y = im.planes[0], u = im.planes[1], v = im.planes[2];
    for (var r = 0; r < h; r++) {
      out.setRange(r * w, r * w + w, y.bytes, r * y.bytesPerRow);
    }
    final pxU = u.bytesPerPixel ?? 1, pxV = v.bytesPerPixel ?? 1;
    var o = w * h;
    for (var r = 0; r < h ~/ 2; r++) {
      for (var c = 0; c < w ~/ 2; c++) {
        out[o++] = v.bytes[r * v.bytesPerRow + c * pxV];
        out[o++] = u.bytes[r * u.bytesPerRow + c * pxU];
      }
    }
    return out;
  }

  InputImage get inputImage => InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(ancho.toDouble(), alto.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(rotacion) ?? InputImageRotation.rotation0deg,
          format: bgra ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
          bytesPerRow: paso,
        ),
      );

  Size get tamanoDerecho =>
      (rotacion == 90 || rotacion == 270) ? Size(alto.toDouble(), ancho.toDouble()) : Size(ancho.toDouble(), alto.toDouble());

  /// Punto de la imagen derecha (xu, yu) → punto del cuadro crudo.
  (int, int) _crudo(int xu, int yu) => switch (rotacion) {
        90 => (yu, alto - 1 - xu),
        180 => (ancho - 1 - xu, alto - 1 - yu),
        270 => (ancho - 1 - yu, xu),
        _ => (xu, yu),
      };

  /// RGB 0–255 del punto (xu, yu) de la imagen derecha.
  (int, int, int) _rgb(int xu, int yu) {
    final (x0, y0) = _crudo(xu, yu);
    final x = x0.clamp(0, ancho - 1);
    final y = y0.clamp(0, alto - 1);
    if (bgra) {
      final i = y * paso + x * 4;
      return (bytes[i + 2], bytes[i + 1], bytes[i]);
    }
    final yy = bytes[y * paso + x];
    final uv = paso * alto + (y >> 1) * paso + (x & ~1);
    final vv = (uv < bytes.length ? bytes[uv] : 128) - 128;
    final uu = (uv + 1 < bytes.length ? bytes[uv + 1] : 128) - 128;
    final r = (yy + 1.402 * vv).round().clamp(0, 255);
    final g = (yy - 0.344 * uu - 0.714 * vv).round().clamp(0, 255);
    final b = (yy + 1.772 * uu).round().clamp(0, 255);
    return (r, g, b);
  }

  /// Brillo medio (0–255) dentro de la caja, con una muestra rala.
  double brilloMedio(Rect caja) {
    var s = 0, n = 0;
    final x0 = caja.left.round(), y0 = caja.top.round();
    final w = caja.width.round(), h = caja.height.round();
    for (var j = 0; j < 8; j++) {
      for (var i = 0; i < 8; i++) {
        final (r, g, b) = _rgb(x0 + (w * (i + 0.5) / 8).round(), y0 + (h * (j + 0.5) / 8).round());
        s += (r * 3 + g * 6 + b) ~/ 10;
        n++;
      }
    }
    return n == 0 ? 0 : s / n;
  }

  /// Recorte cuadrado de la cara a lado×lado, normalizado a [-1, 1] para la
  /// red. Cada pixel de salida promedia 2×2 muestras (menos ruido).
  (Float32List, img.Image?) recortar(Rect caja, int lado, {bool conImagen = false}) {
    final cx = caja.center.dx, cy = caja.center.dy;
    final medio = math.max(caja.width, caja.height) * 0.55;
    final paso = (medio * 2) / lado;
    final out = Float32List(lado * lado * 3);
    final imagen = conImagen ? img.Image(width: lado, height: lado) : null;
    var k = 0;
    for (var v = 0; v < lado; v++) {
      for (var u = 0; u < lado; u++) {
        var r = 0, g = 0, b = 0;
        for (final dy in const [0.25, 0.75]) {
          for (final dx in const [0.25, 0.75]) {
            final (pr, pg, pb) = _rgb(
              (cx - medio + (u + dx) * paso).round(),
              (cy - medio + (v + dy) * paso).round(),
            );
            r += pr;
            g += pg;
            b += pb;
          }
        }
        r ~/= 4;
        g ~/= 4;
        b ~/= 4;
        out[k++] = (r - 127.5) / 128;
        out[k++] = (g - 127.5) / 128;
        out[k++] = (b - 127.5) / 128;
        imagen?.setPixelRgb(u, v, r, g, b);
      }
    }
    return (out, imagen);
  }
}
