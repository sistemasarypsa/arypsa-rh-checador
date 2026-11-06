import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Archivo JSON en la carpeta privada de la app. Escritura atómica (tmp +
/// rename) para que un apagón a media escritura no deje el archivo roto.
class ArchivoJson {
  ArchivoJson(this.nombre);

  final String nombre;
  File? _f;

  Future<File> _archivo() async {
    if (_f != null) return _f!;
    final dir = await getApplicationSupportDirectory();
    return _f = File('${dir.path}/$nombre');
  }

  Future<dynamic> leer() async {
    try {
      final f = await _archivo();
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _ultima = Future.value();

  /// Las escrituras se forman en fila: dos al mismo tiempo pisarían el .tmp.
  Future<void> escribir(Object? valor) {
    final texto = jsonEncode(valor);
    final siguiente = _ultima.then((_) async {
      final f = await _archivo();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(texto, flush: true);
      await tmp.rename(f.path);
    });
    _ultima = siguiente.catchError((_) {});
    return siguiente;
  }
}

/// Checadas que no alcanzaron a llegar al servidor. Se reintentan solas cada
/// 30 s y cada vez que se checa. Cada una lleva su `cliente_id`: si el
/// servidor ya la tenía, la reconoce y no la duplica.
class ColaChecadas extends ChangeNotifier {
  final _archivo = ArchivoJson('cola_checadas.json');
  final List<Map<String, dynamic>> _pendientes = [];
  Timer? _timer;
  bool _enviando = false;
  DateTime? ultimoEnvio;
  bool enLinea = true;

  int get pendientes => _pendientes.length;

  /// Resultados del servidor para checadas que salieron de la cola, por si la
  /// pantalla quiere actualizar lo que mostró como "pendiente".
  final _resultados = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get resultados => _resultados.stream;

  Future<void> iniciar() async {
    final r = await _archivo.leer();
    if (r is List) {
      _pendientes
        ..clear()
        ..addAll(r.map((e) => Map<String, dynamic>.from(e as Map)));
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => enviar());
    notifyListeners();
    unawaited(enviar());
  }

  Future<void> agregar(Map<String, dynamic> checada) async {
    _pendientes.add(checada);
    await _archivo.escribir(_pendientes);
    notifyListeners();
  }

  Future<void> enviar() async {
    if (_enviando || _pendientes.isEmpty) return;
    _enviando = true;
    var avanzo = false;
    try {
      // En lotes de 50 para no mandar un JSON enorme tras un día sin red.
      final lote = _pendientes.take(50).toList();
      final res = await Api.checar(lote, limite: const Duration(seconds: 30));
      final listos = <String>{};
      for (final r in res) {
        listos.add(r['cliente_id'] as String);
        _resultados.add(r);
      }
      // Las que el servidor rechazó por un error de datos (empleado dado de
      // baja, etc.) también salen: reintentarlas no las va a arreglar.
      final antes = _pendientes.length;
      _pendientes.removeWhere((c) => listos.contains(c['cliente_id']));
      avanzo = _pendientes.length < antes;
      await _archivo.escribir(_pendientes);
      enLinea = true;
      ultimoEnvio = DateTime.now();
    } catch (e) {
      if (esErrorDeRed(e)) enLinea = false;
    } finally {
      _enviando = false;
      notifyListeners();
    }
    if (avanzo && _pendientes.isNotEmpty) unawaited(enviar());
  }

  void marcarEnLinea(bool v) {
    if (enLinea == v) return;
    enLinea = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resultados.close();
    super.dispose();
  }
}

final cola = ColaChecadas();
