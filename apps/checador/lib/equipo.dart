import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kVersionApp = '1.0.0';

/// Identidad de este equipo ante el servidor. Se guarda en el llavero del
/// sistema (Keychain en iOS, Keystore en Android), nunca en texto plano.
class Equipo extends ChangeNotifier {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _key = 'arypsa_checador_equipo';

  bool cargando = true;
  String? id;
  String? secreto;

  /// 'kiosco' | 'movil'
  String? tipo;

  bool get activado => id != null && secreto != null && tipo != null;
  bool get esKiosco => tipo == 'kiosco';
  bool get esMovil => tipo == 'movil';

  Future<void> cargar() async {
    try {
      final raw = await _store.read(key: _key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        id = j['id'] as String?;
        secreto = j['secreto'] as String?;
        tipo = j['tipo'] as String?;
      }
    } catch (_) {
      // Llavero corrupto (pasa tras restaurar un respaldo en otro equipo):
      // se trata como equipo nuevo.
      id = secreto = tipo = null;
    }
    cargando = false;
    debugPrint('[Checador] Equipo: ${activado ? '$tipo ${id?.substring(0, 8)}' : 'sin activar'}');
    notifyListeners();
  }

  Future<void> guardar({required String id, required String secreto, required String tipo}) async {
    this.id = id;
    this.secreto = secreto;
    this.tipo = tipo;
    await _store.write(key: _key, value: jsonEncode({'id': id, 'secreto': secreto, 'tipo': tipo}));
    notifyListeners();
  }

  /// El servidor dijo que este equipo ya no vale (RH lo dio de baja).
  Future<void> olvidar() async {
    id = secreto = tipo = null;
    try {
      await _store.delete(key: _key);
    } catch (_) {}
    notifyListeners();
  }

  static Future<Map<String, String>> infoDispositivo() async {
    final info = DeviceInfoPlugin();
    var modelo = 'Desconocido';
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        modelo = '${a.manufacturer} ${a.model}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        modelo = '${i.name} (${i.utsname.machine})';
      }
    } catch (_) {}
    return {
      'plataforma': Platform.operatingSystem,
      'modelo': modelo,
      'version': kVersionApp,
    };
  }
}

final equipo = Equipo();
