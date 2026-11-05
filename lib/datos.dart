import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;

double _d(dynamic v) => (v as num).toDouble();
int? _i(dynamic v) => v == null ? null : (v as num).toInt();

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

class Sede {
  Sede({
    this.id,
    required this.nombre,
    this.direccion,
    required this.lat,
    required this.lng,
    this.radioM = 150,
    this.activa = true,
    this.modo = 'respaldo',
    this.umbral = 0.85,
  });

  final String? id;
  final String nombre;
  final String? direccion;
  final double lat;
  final double lng;
  final int radioM;
  final bool activa;

  /// 'cualquiera' | 'respaldo' | 'doble'
  final String modo;

  /// Distancia máxima aceptada por el reconocimiento facial (menor = más estricto).
  final double umbral;

  static const modos = {
    'cualquiera': 'Rostro o huella',
    'respaldo': 'Rostro, huella de respaldo',
    'doble': 'Rostro y huella',
  };

  factory Sede.fromJson(Map<String, dynamic> j) => Sede(
        id: j['id'] as String?,
        nombre: j['nombre'] as String,
        direccion: j['direccion'] as String?,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        radioM: _i(j['radio_m']) ?? 150,
        activa: j['activa'] as bool? ?? true,
        modo: j['modo_biometrico'] as String? ?? 'respaldo',
        umbral: (j['umbral_rostro'] as num?)?.toDouble() ?? 0.85,
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'direccion': direccion,
        'lat': lat,
        'lng': lng,
        'radio_m': radioM,
        'activa': activa,
        'modo_biometrico': modo,
        'umbral_rostro': umbral,
      };
}

class Turno {
  Turno({
    this.id,
    required this.nombre,
    required this.entrada,
    required this.salida,
    this.tolerancia = 10,
    this.dias = const [1, 2, 3, 4, 5],
    this.activo = true,
  });

  final String? id;
  final String nombre;

  /// 'HH:MM'
  final String entrada;
  final String salida;
  final int tolerancia;

  /// ISO: 1 = lunes … 7 = domingo
  final List<int> dias;
  final bool activo;

  static String _hm(dynamic v) {
    final s = (v ?? '00:00').toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  factory Turno.fromJson(Map<String, dynamic> j) => Turno(
        id: j['id'] as String?,
        nombre: j['nombre'] as String,
        entrada: _hm(j['hora_entrada']),
        salida: _hm(j['hora_salida']),
        tolerancia: _i(j['tolerancia_min']) ?? 10,
        dias: ((j['dias'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        activo: j['activo'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'hora_entrada': entrada,
        'hora_salida': salida,
        'tolerancia_min': tolerancia,
        'dias': dias,
        'activo': activo,
      };

  String get diasTexto {
    const l = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    if (dias.length == 7) return 'Toda la semana';
    if (dias.length == 5 && !dias.contains(6) && !dias.contains(7)) return 'Lunes a viernes';
    if (dias.length == 6 && !dias.contains(7)) return 'Lunes a sábado';
    final o = [...dias]..sort();
    return o.map((d) => l[d - 1]).join(' ');
  }
}

class Empleado {
  Empleado(this.j);

  /// La fila completa de rh_empleados (los campos del expediente se leen de
  /// aquí con [txt], [fecha], [num_]).
  final Map<String, dynamic> j;

  String? get id => j['id'] as String?;
  String get numero => j['numero'] as String;
  String get nombres => j['nombres'] as String;
  String get apellidos => (j['apellidos'] as String?) ?? '';
  String? get puesto => j['puesto'] as String?;
  String? get departamento => j['departamento'] as String?;
  String? get sedeId => j['sede_id'] as String?;
  String? get turnoId => j['turno_id'] as String?;
  String? get jefeId => j['jefe_id'] as String?;
  String get tipo => (j['tipo'] as String?) ?? 'planta';
  bool get checaMovil => j['checa_movil'] as bool? ?? false;
  String? get telefono => j['telefono'] as String?;
  String? get correo => j['correo'] as String?;
  DateTime? get fechaIngreso => fecha('fecha_ingreso');
  DateTime? get fechaNacimiento => fecha('fecha_nacimiento');
  DateTime? get finContrato => fecha('fecha_fin_contrato');
  String? get foto => j['foto'] as String?;
  DateTime? get consentimientoAt => fecha('consentimiento_at');
  int get huellas => _i(j['huellas']) ?? 0;
  int get rostros => _i(j['rostros']) ?? 0;
  bool get movilVinculado => j['movil_vinculado'] as bool? ?? false;
  bool get activo => j['activo'] as bool? ?? true;

  bool get biometriaKiosco => huellas > 0 || rostros > 0;
  String get nombre => '$nombres $apellidos'.trim();
  bool get administrativo => tipo == 'administrativo';

  /// Texto de una columna (null si está vacía).
  String? txt(String col) {
    final v = j[col];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  DateTime? fecha(String col) {
    final v = j[col];
    return v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  }

  double? num_(String col) => (j[col] as num?)?.toDouble();

  List<Map<String, dynamic>> lista(String col) =>
      ((j[col] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Lo que la lista de empleados y el tablero necesitan (sin el expediente).
  static const columnas =
      'id,numero,nombres,apellidos,puesto,departamento,sede_id,turno_id,jefe_id,tipo,checa_movil,'
      'telefono,correo,fecha_ingreso,fecha_nacimiento,fecha_fin_contrato,tipo_contrato,fin_periodo_prueba,'
      'curp,rfc,nss,foto,consentimiento_at,huellas,rostros,movil_vinculado,activo,fecha_baja,tipo_baja';

  factory Empleado.fromJson(Map<String, dynamic> j) => Empleado(j);
}

/// Un tipo de documento del expediente (catálogo rh_tipos_documento).
class TipoDocumento {
  TipoDocumento(this.j);
  final Map<String, dynamic> j;

  String get id => j['id'] as String;
  String get nombre => j['nombre'] as String;
  String? get descripcion => j['descripcion'] as String?;
  String get categoria => j['categoria'] as String? ?? 'personal';
  bool get obligatorio => j['obligatorio'] as bool? ?? false;
  bool get vence => j['vence'] as bool? ?? false;
  int? get vigenciaDias => _i(j['vigencia_dias']);
  bool get activo => j['activo'] as bool? ?? true;

  static const categorias = {
    'personal': 'Personales',
    'fiscal': 'Fiscales',
    'imss': 'Seguridad social',
    'laboral': 'Contratación',
    'salud': 'Salud',
    'capacitacion': 'Capacitación',
    'baja': 'Baja',
  };
}

class Documento {
  Documento(this.j);
  final Map<String, dynamic> j;

  String get id => j['id'] as String;
  String get empleadoId => j['empleado_id'] as String;
  String get tipoId => j['tipo_id'] as String;
  String get archivo => j['archivo'] as String;
  String? get nombreArchivo => j['nombre_archivo'] as String?;
  String? get mime => j['mime'] as String?;
  int? get tamano => _i(j['tamano']);
  DateTime? get vence => j['vence'] == null ? null : DateTime.tryParse(j['vence'] as String);
  DateTime? get fechaDocumento => j['fecha_documento'] == null ? null : DateTime.tryParse(j['fecha_documento'] as String);
  String? get notas => j['notas'] as String?;
  DateTime get creado => DateTime.parse(j['creado_at'] as String).toLocal();

  bool get esImagen => (mime ?? '').startsWith('image/');
  bool get esPdf => mime == 'application/pdf' || archivo.toLowerCase().endsWith('.pdf');
  bool get vencido => vence != null && vence!.isBefore(DateTime.now());
  bool vencePronto([int dias = 30]) =>
      vence != null && !vencido && vence!.isBefore(DateTime.now().add(Duration(days: dias)));
}

/// Estado de un tipo de documento para un empleado.
enum EstadoDoc { falta, ok, vencePronto, vencido, opcional }

class Movimiento {
  Movimiento(this.j);
  final Map<String, dynamic> j;

  String get campo => j['campo'] as String;
  String? get antes => j['antes'] as String?;
  String? get despues => j['despues'] as String?;
  DateTime get at => DateTime.parse(j['at'] as String).toLocal();
}

class Checada {
  Checada({
    required this.id,
    required this.tipo,
    required this.ts,
    required this.estado,
    required this.metodo,
    this.sede,
    this.distanciaM,
    this.minutosRetardo,
    this.precisionM,
    this.gpsSimulado = false,
    this.nota,
    this.lat,
    this.lng,
  });

  final String id;
  final String tipo;
  final DateTime ts;
  final String estado;
  final String metodo;
  final String? sede;
  final int? distanciaM;
  final int? minutosRetardo;
  final double? precisionM;
  final bool gpsSimulado;
  final String? nota;
  final double? lat;
  final double? lng;

  factory Checada.fromJson(Map<String, dynamic> j) => Checada(
        id: j['id'] as String,
        tipo: j['tipo'] as String,
        ts: DateTime.parse(j['ts'] as String),
        estado: j['estado'] as String,
        metodo: (j['metodo'] as String?) ?? 'lector',
        sede: (j['sede'] as Map?)?['nombre'] as String?,
        distanciaM: _i(j['distancia_m']),
        minutosRetardo: _i(j['minutos_retardo']),
        precisionM: (j['precision_m'] as num?)?.toDouble(),
        gpsSimulado: j['gps_simulado'] as bool? ?? false,
        nota: j['nota'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

class Equipo {
  Equipo({
    required this.id,
    required this.tipo,
    required this.nombre,
    this.empleado,
    this.sede,
    this.modelo,
    this.plataforma,
    this.activo = true,
    this.ultimoContacto,
    this.creadoAt,
  });

  final String id;
  final String tipo;
  final String nombre;
  final String? empleado;
  final String? sede;
  final String? modelo;
  final String? plataforma;
  final bool activo;
  final DateTime? ultimoContacto;
  final DateTime? creadoAt;

  bool get esKiosco => tipo == 'kiosco';

  static const columnas =
      'id,tipo,nombre,modelo,plataforma,activo,ultimo_contacto,creado_at,empleado_id,'
      'empleado:rh_empleados(nombres,apellidos),sede:rh_sedes(nombre)';

  factory Equipo.fromJson(Map<String, dynamic> j) {
    final e = j['empleado'] as Map?;
    return Equipo(
      id: j['id'] as String,
      tipo: j['tipo'] as String,
      nombre: j['nombre'] as String,
      empleado: e == null ? null : '${e['nombres']} ${e['apellidos'] ?? ''}'.trim(),
      sede: (j['sede'] as Map?)?['nombre'] as String?,
      modelo: j['modelo'] as String?,
      plataforma: j['plataforma'] as String?,
      activo: j['activo'] as bool? ?? true,
      ultimoContacto: j['ultimo_contacto'] == null ? null : DateTime.tryParse(j['ultimo_contacto'] as String),
      creadoAt: j['creado_at'] == null ? null : DateTime.tryParse(j['creado_at'] as String),
    );
  }
}

class ResumenDia {
  ResumenDia({
    required this.empleadoId,
    required this.numero,
    required this.nombre,
    this.puesto,
    required this.tipo,
    this.foto,
    this.entrada,
    this.salida,
    this.minutosRetardo,
    this.checadas = 0,
    this.alertas = 0,
    this.ultimaSede,
    this.laboraHoy = true,
  });

  final String empleadoId;
  final String numero;
  final String nombre;
  final String? puesto;
  final String tipo;
  final String? foto;
  final DateTime? entrada;
  final DateTime? salida;
  final int? minutosRetardo;
  final int checadas;
  final int alertas;
  final String? ultimaSede;
  final bool laboraHoy;

  bool get presente => entrada != null;
  bool get retardo => (minutosRetardo ?? 0) > 0;
  bool get falta => laboraHoy && entrada == null;

  factory ResumenDia.fromJson(Map<String, dynamic> j) => ResumenDia(
        empleadoId: j['empleado_id'] as String,
        numero: j['numero'] as String,
        nombre: j['nombre'] as String,
        puesto: j['puesto'] as String?,
        tipo: j['tipo'] as String,
        foto: j['foto'] as String?,
        entrada: j['entrada'] == null ? null : DateTime.parse(j['entrada'] as String),
        salida: j['salida'] == null ? null : DateTime.parse(j['salida'] as String),
        minutosRetardo: _i(j['minutos_retardo']),
        checadas: _i(j['checadas']) ?? 0,
        alertas: _i(j['alertas']) ?? 0,
        ultimaSede: j['ultima_sede'] as String?,
        laboraHoy: j['labora_hoy'] as bool? ?? true,
      );
}

class Codigo {
  Codigo(this.codigo, this.expira, this.proposito);

  final String codigo;
  final DateTime expira;
  final String proposito;

  /// Lo que lee la cámara del kiosco o del celular.
  String get qr => 'ARYPSA-RH:$codigo';
}

// ---------------------------------------------------------------------------
// Acceso a datos
// ---------------------------------------------------------------------------

class Repo {
  static String _fecha(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Empleados ---------------------------------------------------------------

  static Future<List<Empleado>> empleados({bool activos = true}) async {
    final r = await sb
        .from('rh_empleados')
        .select(Empleado.columnas)
        .eq('activo', activos)
        .order('nombres')
        .order('apellidos');
    return r.map(Empleado.fromJson).toList();
  }

  static Future<Empleado> empleado(String id) async {
    final r = await sb.from('rh_empleados').select(Empleado.columnas).eq('id', id).single();
    return Empleado.fromJson(r);
  }

  static Future<Empleado> guardarEmpleado(String? id, Map<String, dynamic> datos) async {
    final Map<String, dynamic> r;
    if (id == null) {
      r = await sb.from('rh_empleados').insert(datos).select(Empleado.columnas).single();
    } else {
      r = await sb.from('rh_empleados').update(datos).eq('id', id).select(Empleado.columnas).single();
    }
    return Empleado.fromJson(r);
  }

  /// La ficha completa (todas las columnas del expediente).
  static Future<Empleado> expediente(String id) async {
    final r = await sb.from('rh_empleados').select('*').eq('id', id).single();
    return Empleado.fromJson(r);
  }

  static Future<void> darBaja(String id) => sb.rpc('rh_dar_baja', params: {'p_empleado': id});

  static Future<void> bajaEmpleado(String id,
          {required DateTime fecha, required String tipo, String? motivo, bool recontratable = true}) =>
      sb.rpc('rh_baja_empleado', params: {
        'p_empleado': id,
        'p_fecha': _fecha(fecha),
        'p_tipo': tipo,
        'p_motivo': motivo,
        'p_recontratable': recontratable,
      });

  static Future<void> reactivar(String id, {DateTime? ingreso}) => sb.rpc('rh_reactivar_empleado', params: {
        'p_empleado': id,
        'p_fecha_ingreso': ingreso == null ? null : _fecha(ingreso),
      });

  /// Valores ya usados en una columna (para sugerir puestos y departamentos).
  static Future<List<String>> sugerencias(String columna) async {
    final r = await sb.from('rh_empleados').select(columna).not(columna, 'is', null);
    final s = <String>{for (final f in r) (f[columna] as String).trim()}..removeWhere((e) => e.isEmpty);
    return s.toList()..sort();
  }

  // Expediente ----------------------------------------------------------------

  static const bucket = 'rh-expedientes';

  static Future<List<TipoDocumento>> tiposDocumento({bool soloActivos = true}) async {
    var q = sb.from('rh_tipos_documento').select();
    if (soloActivos) q = q.eq('activo', true);
    final r = await q.order('orden');
    return r.map(TipoDocumento.new).toList();
  }

  static Future<void> guardarTipoDocumento(Map<String, dynamic> datos) =>
      sb.from('rh_tipos_documento').upsert(datos);

  static Future<List<Documento>> documentosDe(String empleadoId) async {
    final r = await sb
        .from('rh_documentos')
        .select()
        .eq('empleado_id', empleadoId)
        .order('creado_at', ascending: false);
    return r.map(Documento.new).toList();
  }

  /// Todos los documentos (sin archivo) para el tablero: faltantes y vencimientos.
  static Future<List<Documento>> documentosTodos() async {
    final r = await sb.from('rh_documentos').select('id,empleado_id,tipo_id,archivo,vence,creado_at');
    return r.map(Documento.new).toList();
  }

  static Future<Documento> subirDocumento({
    required String empleadoId,
    required String tipoId,
    required Uint8List bytes,
    required String nombre,
    required String mime,
    DateTime? vence,
    DateTime? fechaDocumento,
    String? notas,
  }) async {
    final limpio = nombre.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final ruta = '$empleadoId/$tipoId/${DateTime.now().millisecondsSinceEpoch}_$limpio';
    await sb.storage.from(bucket).uploadBinary(ruta, bytes, fileOptions: FileOptions(contentType: mime));
    final r = await sb
        .from('rh_documentos')
        .insert({
          'empleado_id': empleadoId,
          'tipo_id': tipoId,
          'archivo': ruta,
          'nombre_archivo': nombre,
          'mime': mime,
          'tamano': bytes.length,
          'vence': vence == null ? null : _fecha(vence),
          'fecha_documento': fechaDocumento == null ? null : _fecha(fechaDocumento),
          'notas': notas,
        })
        .select()
        .single();
    return Documento(r);
  }

  static Future<Uint8List> bajarDocumento(Documento d) => sb.storage.from(bucket).download(d.archivo);

  /// Liga temporal (10 min) para abrir el archivo fuera de la app.
  static Future<String> ligaDocumento(Documento d) =>
      sb.storage.from(bucket).createSignedUrl(d.archivo, 600);

  static Future<void> quitarDocumento(Documento d) async {
    await sb.from('rh_documentos').delete().eq('id', d.id);
    try {
      await sb.storage.from(bucket).remove([d.archivo]);
    } catch (_) {}
  }

  static Future<List<Movimiento>> historialDe(String empleadoId) async {
    final r = await sb
        .from('rh_historial')
        .select()
        .eq('empleado_id', empleadoId)
        .order('at', ascending: false)
        .limit(100);
    return r.map(Movimiento.new).toList();
  }

  /// Estado de cada tipo de documento para un empleado (el más reciente manda).
  static Map<String, (EstadoDoc, Documento?)> estadoExpediente(
      List<TipoDocumento> tipos, Iterable<Documento> docs) {
    final ultimo = <String, Documento>{};
    for (final d in docs) {
      final u = ultimo[d.tipoId];
      if (u == null || d.creado.isAfter(u.creado)) ultimo[d.tipoId] = d;
    }
    return {for (final t in tipos) t.id: _estadoDe(t, ultimo[t.id])};
  }

  static (EstadoDoc, Documento?) _estadoDe(TipoDocumento t, Documento? d) {
    if (d == null) return (t.obligatorio ? EstadoDoc.falta : EstadoDoc.opcional, null);
    if (d.vencido) return (EstadoDoc.vencido, d);
    if (d.vencePronto()) return (EstadoDoc.vencePronto, d);
    return (EstadoDoc.ok, d);
  }

  static Future<void> borrarHuellas(String id) => sb.rpc('rh_borrar_huellas', params: {'p_empleado': id});

  static Future<void> borrarRostros(String id) => sb.rpc('rh_borrar_rostros', params: {'p_empleado': id});

  // Códigos -----------------------------------------------------------------

  static Future<Codigo> generarCodigo(String proposito, {String? empleado, String? sede, String? nombre}) async {
    final r = await sb.rpc('rh_generar_codigo', params: {
      'p_proposito': proposito,
      'p_empleado': empleado,
      'p_sede': sede,
      'p_nombre': nombre,
    }) as Map<String, dynamic>;
    return Codigo(
      r['codigo'] as String,
      DateTime.parse(r['expira_at'] as String),
      r['proposito'] as String,
    );
  }

  // Sedes y turnos ----------------------------------------------------------

  static Future<List<Sede>> sedes() async {
    final r = await sb.from('rh_sedes').select().order('nombre');
    return r.map(Sede.fromJson).toList();
  }

  static Future<void> guardarSede(String? id, Sede s) async {
    if (id == null) {
      await sb.from('rh_sedes').insert(s.toJson());
    } else {
      await sb.from('rh_sedes').update(s.toJson()).eq('id', id);
    }
  }

  static Future<List<Turno>> turnos() async {
    final r = await sb.from('rh_turnos').select().order('hora_entrada');
    return r.map(Turno.fromJson).toList();
  }

  static Future<void> guardarTurno(String? id, Turno t) async {
    if (id == null) {
      await sb.from('rh_turnos').insert(t.toJson());
    } else {
      await sb.from('rh_turnos').update(t.toJson()).eq('id', id);
    }
  }

  // Equipos -----------------------------------------------------------------

  static Future<List<Equipo>> equipos() async {
    final r = await sb
        .from('rh_dispositivos')
        .select(Equipo.columnas)
        .order('activo', ascending: false)
        .order('creado_at', ascending: false);
    return r.map(Equipo.fromJson).toList();
  }

  static Future<Equipo?> celularDe(String empleadoId) async {
    final r = await sb
        .from('rh_dispositivos')
        .select(Equipo.columnas)
        .eq('empleado_id', empleadoId)
        .eq('tipo', 'movil')
        .eq('activo', true)
        .maybeSingle();
    return r == null ? null : Equipo.fromJson(r);
  }

  static Future<void> desactivarEquipo(String id) => sb.rpc('rh_desactivar_equipo', params: {'p_equipo': id});

  // Checadas ----------------------------------------------------------------

  static Future<List<ResumenDia>> resumenDia(DateTime dia) async {
    final r = await sb.rpc('rh_resumen_dia', params: {'p_fecha': _fecha(dia)}) as List;
    return r.map((e) => ResumenDia.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Checada>> checadasDe(String empleadoId, {int limite = 40}) async {
    final r = await sb
        .from('rh_checadas')
        .select('*, sede:rh_sedes(nombre)')
        .eq('empleado_id', empleadoId)
        .order('ts', ascending: false)
        .limit(limite);
    return r.map(Checada.fromJson).toList();
  }

  static Future<void> revisarChecada(String id, String estado, String? nota) =>
      sb.from('rh_checadas').update({'estado': estado, 'nota': nota}).eq('id', id);
}
