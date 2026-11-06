import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'datos.dart';
import 'mx.dart';
import 'responsive.dart';
import 'theme.dart';
import 'ui.dart';

/// Alta y edición del expediente completo. Devuelve el [Empleado] guardado
/// con `Navigator.pop`. Para editar, pásale la ficha completa
/// (`Repo.expediente`), no la de la lista.
class EmpleadoForm extends StatefulWidget {
  const EmpleadoForm({this.empleado, this.seccion, super.key});

  final Empleado? empleado;

  /// Sección a la que se brinca al abrir (p. ej. 'banco').
  final String? seccion;

  @override
  State<EmpleadoForm> createState() => _EmpleadoFormState();
}

class _Seccion {
  const _Seccion(this.id, this.titulo, this.icono);
  final String id;
  final String titulo;
  final IconData icono;
}

const _secciones = [
  _Seccion('personal', 'Personales', Icons.badge_outlined),
  _Seccion('contacto', 'Contacto', Icons.home_outlined),
  _Seccion('puesto', 'Puesto', Icons.work_outline),
  _Seccion('nomina', 'Nómina e IMSS', Icons.payments_outlined),
  _Seccion('banco', 'Banco', Icons.account_balance_outlined),
  _Seccion('emergencia', 'Emergencia', Icons.emergency_outlined),
  _Seccion('beneficiarios', 'Beneficiarios', Icons.family_restroom),
  _Seccion('uniforme', 'Uniforme', Icons.checkroom_outlined),
  _Seccion('consentimiento', 'Consentimiento', Icons.policy_outlined),
];

class _EmpleadoFormState extends State<EmpleadoForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _anclas = {for (final s in _secciones) s.id: GlobalKey()};
  final _ctl = <String, TextEditingController>{};
  final _focos = <String, FocusNode>{};

  Empleado? get _e => widget.empleado;
  bool get _editando => _e != null;

  /// Controlador de texto ligado a una columna de rh_empleados.
  TextEditingController _t(String col) => _ctl.putIfAbsent(col, () => TextEditingController(text: _e?.txt(col) ?? ''));

  late String? _foto = _e?.foto;
  late String? _sedeId = _e?.sedeId;
  late String? _turnoId = _e?.turnoId;
  late String? _jefeId = _e?.jefeId;
  late String _tipo = _e?.tipo ?? 'planta';
  late bool _checaMovil = _e?.checaMovil ?? false;
  late bool _consentimiento = _e?.consentimientoAt != null;

  late final Map<String, DateTime?> _fechas = {
    for (final c in ['fecha_nacimiento', 'fecha_ingreso', 'fecha_fin_contrato', 'fin_periodo_prueba', 'fecha_alta_imss'])
      c: _e?.fecha(c),
  };
  late final Map<String, String?> _opciones = {
    'sexo': _e?.txt('sexo'),
    'estado_civil': _e?.txt('estado_civil'),
    'escolaridad': _e?.txt('escolaridad'),
    'tipo_sangre': _e?.txt('tipo_sangre'),
    'lugar_nacimiento': _e?.txt('lugar_nacimiento'),
    'estado': _e?.txt('estado'),
    'tipo_contrato': _e?.txt('tipo_contrato') ?? 'indeterminado',
    'jornada': _e?.txt('jornada') ?? 'diurna',
    'periodicidad_pago': _e?.txt('periodicidad_pago') ?? 'semanal',
    'forma_pago': _e?.txt('forma_pago') ?? 'transferencia',
    'regimen_fiscal': _e?.txt('regimen_fiscal') ?? '605',
    'infonavit_tipo': _e?.txt('infonavit_tipo'),
  };

  late List<Map<String, dynamic>> _emergencia = _e?.lista('contactos_emergencia') ?? [];
  late final List<Map<String, dynamic>> _beneficiarios = _e?.lista('beneficiarios') ?? [];

  List<Sede> _sedes = const [];
  List<Turno> _turnos = const [];
  List<Empleado> _jefes = const [];
  List<String> _puestos = const [];
  List<String> _deptos = const [];
  bool _cargando = true;
  bool _guardando = false;
  String _activa = 'personal';

  @override
  void initState() {
    super.initState();
    // Registros viejos solo tienen "apellidos": se parten en paterno/materno.
    if (_e != null && _e!.txt('apellido_paterno') == null && _e!.apellidos.isNotEmpty) {
      final p = _e!.apellidos.split(RegExp(r'\s+'));
      _t('apellido_paterno').text = p.first;
      _t('apellido_materno').text = p.skip(1).join(' ');
    }
    if (_emergencia.isEmpty) _emergencia = [{}];
    _scroll.addListener(_seccionVisible);
    _catalogos();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _catalogos() async {
    try {
      final r = await Future.wait<Object>([
        Repo.sedes(),
        Repo.turnos(),
        Repo.empleados(),
        Repo.sugerencias('puesto'),
        Repo.sugerencias('departamento'),
      ]);
      if (!mounted) return;
      setState(() {
        _sedes = (r[0] as List<Sede>).where((s) => s.activa || s.id == _sedeId).toList();
        _turnos = (r[1] as List<Turno>).where((t) => t.activo || t.id == _turnoId).toList();
        _jefes = (r[2] as List<Empleado>).where((e) => e.id != _e?.id).toList();
        _puestos = r[3] as List<String>;
        _deptos = r[4] as List<String>;
        if (_sedeId == null && _sedes.length == 1) _sedeId = _sedes.first.id;
        _cargando = false;
      });
      if (widget.seccion != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _ir(widget.seccion!));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      avisar(context, mensajeError(e), error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Navegación entre secciones
  // ---------------------------------------------------------------------------

  void _ir(String id) {
    final ctx = _anclas[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0.02);
  }

  void _seccionVisible() {
    String? actual;
    for (final s in _secciones) {
      final box = _anclas[s.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y < 220) actual = s.id;
    }
    actual ??= _secciones.first.id;
    if (actual != _activa) setState(() => _activa = actual!);
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  Future<void> _tomarFoto(ImageSource fuente) async {
    try {
      final x = await ImagePicker().pickImage(
        source: fuente,
        maxWidth: 480,
        maxHeight: 480,
        imageQuality: 72,
        preferredCameraDevice: CameraDevice.front,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _foto = base64Encode(bytes));
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo abrir la cámara: ${mensajeError(e)}', error: true);
    }
  }

  void _menuFoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined),
              title: Text('Tomar foto'),
              onTap: () {
                Navigator.pop(ctx);
                _tomarFoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Elegir de la galería'),
              onTap: () {
                Navigator.pop(ctx);
                _tomarFoto(ImageSource.gallery);
              },
            ),
            if (_foto != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: ctx.c.danger),
                title: Text('Quitar foto', style: TextStyle(color: ctx.c.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _foto = null);
                },
              ),
            SizedBox(height: 8.r),
          ],
        ),
      ),
    );
  }

  /// Al capturar una CURP válida se llenan nacimiento, sexo y entidad, y se
  /// propone el RFC (los primeros 10 caracteres son iguales).
  void _curpCambio(String v) {
    final s = v.trim().toUpperCase();
    if (s.length != 18 || validarCurp(s) != null) {
      setState(() {});
      return;
    }
    final d = datosDeCurp(s)!;
    final yaLleno = _fechas['fecha_nacimiento'] != null && _opciones['sexo'] != null;
    setState(() {
      _fechas['fecha_nacimiento'] ??= d.nacimiento;
      _opciones['sexo'] ??= d.sexo;
      if (_opciones['lugar_nacimiento'] == null && d.entidad != null) _opciones['lugar_nacimiento'] = d.entidad;
      final rfc = _t('rfc');
      if (rfc.text.trim().isEmpty) rfc.text = s.substring(0, 10);
    });
    if (!yaLleno) avisar(context, 'CURP válida: se llenaron nacimiento, sexo y lugar. Completa la homoclave del RFC.');
  }

  void _calcularSdi() {
    final sd = double.tryParse(_t('salario_diario').text.replaceAll(',', ''));
    if (sd == null || sd <= 0) {
      avisar(context, 'Primero captura el salario diario.', error: true);
      return;
    }
    final f = factorIntegracion(_fechas['fecha_ingreso']);
    _t('sdi').text = (sd * f).toStringAsFixed(2);
    avisar(context, 'SDI con factor de ley ${f.toStringAsFixed(4)} (15 días de aguinaldo, 25 % de prima vacacional). '
        'Si hay prestaciones superiores o variables, ajústalo.');
  }

  void _verAviso() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aviso de privacidad — datos biométricos'),
        content: SingleChildScrollView(
          child: Text(
            'ARYPSA Manufacturas usará el rostro, la huella dactilar y la ubicación del empleado únicamente para '
            'registrar su asistencia (entradas y salidas).\n\n'
            '• El rostro y la huella se guardan como plantillas numéricas, no como fotos, y no se comparten con terceros. '
            'El reconocimiento se hace dentro del reloj checador, sin servicios externos.\n'
            '• La ubicación se toma solo en el momento de checar, para confirmar que se hace desde una sede de la empresa.\n'
            '• Al causar baja, las plantillas de rostro y huella se borran; las checadas se conservan como registro laboral.\n'
            '• El empleado puede ejercer sus derechos ARCO con Recursos Humanos.\n\n'
            'El rostro, la huella, el tipo de sangre, las alergias y el examen médico son datos personales sensibles '
            '(LFPDPPP 2025): el aviso debe señalarlos y se requiere consentimiento expreso y por escrito. '
            'Marca la casilla solo cuando el empleado haya firmado el formato impreso, y sube el formato firmado '
            'a su expediente.',
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text('Entendido'))],
      ),
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;

  String _f(DateTime d) => '${d.year}-${dos(d.month)}-${dos(d.day)}';

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) {
      avisar(context, 'Hay datos por corregir (marcados en rojo).', error: true);
      return;
    }
    if (_sedeId == null) {
      avisar(context, 'Elige la sede del empleado (sección Puesto).', error: true);
      _ir('puesto');
      return;
    }
    final benef = _beneficiarios.where((b) => (b['nombre'] ?? '').toString().trim().isNotEmpty).toList();
    final suma = benef.fold<double>(0, (a, b) => a + (double.tryParse('${b['porcentaje'] ?? ''}') ?? 0));
    if (benef.isNotEmpty && (suma - 100).abs() > 0.01) {
      avisar(context, 'Los porcentajes de los beneficiarios deben sumar 100 % (suman ${suma.toStringAsFixed(0)} %).', error: true);
      _ir('beneficiarios');
      return;
    }

    setState(() => _guardando = true);
    final eraConsentido = _e?.consentimientoAt != null;
    String? txt(String col, {bool mayus = false, bool digitos = false}) {
      var v = _t(col).text.trim();
      if (digitos) v = v.replaceAll(RegExp(r'\D'), '');
      if (mayus) v = v.toUpperCase();
      return v.isEmpty ? null : v;
    }

    double? numero(String col) => double.tryParse(_t(col).text.replaceAll(',', '').trim());

    final paterno = txt('apellido_paterno') ?? '';
    final materno = txt('apellido_materno') ?? '';
    final datos = <String, dynamic>{
      'numero': txt('numero', mayus: true),
      'nombres': txt('nombres'),
      'apellido_paterno': paterno.isEmpty ? null : paterno,
      'apellido_materno': materno.isEmpty ? null : materno,
      'apellidos': '$paterno $materno'.trim(),
      // Personales
      'curp': txt('curp', mayus: true),
      'rfc': txt('rfc', mayus: true),
      'nss': txt('nss', digitos: true),
      'nacionalidad': txt('nacionalidad'),
      'alergias': txt('alergias'),
      // Contacto
      'telefono': txt('telefono'),
      'telefono_casa': txt('telefono_casa'),
      'correo': txt('correo'),
      'correo_empresa': txt('correo_empresa'),
      'calle': txt('calle'),
      'num_ext': txt('num_ext'),
      'num_int': txt('num_int'),
      'colonia': txt('colonia'),
      'municipio': txt('municipio'),
      'cp': txt('cp', digitos: true),
      // Puesto
      'puesto': txt('puesto'),
      'departamento': txt('departamento'),
      'jefe_id': _jefeId,
      'sede_id': _sedeId,
      'turno_id': _turnoId,
      'tipo': _tipo,
      'checa_movil': _checaMovil,
      // Nómina e IMSS
      'salario_diario': numero('salario_diario'),
      'sdi': numero('sdi'),
      'cp_fiscal': txt('cp_fiscal', digitos: true),
      'registro_patronal': txt('registro_patronal', mayus: true),
      'umf': txt('umf'),
      'infonavit_credito': txt('infonavit_credito'),
      'infonavit_valor': numero('infonavit_valor'),
      'fonacot_credito': txt('fonacot_credito'),
      // Banco
      'clabe': txt('clabe', digitos: true),
      'banco': txt('banco'),
      'cuenta': txt('cuenta', digitos: true),
      // Uniforme
      'talla_camisa': txt('talla_camisa', mayus: true),
      'talla_pantalon': txt('talla_pantalon', mayus: true),
      'talla_calzado': txt('talla_calzado'),
      'notas': txt('notas'),
      'contactos_emergencia': _emergencia.where((c) => (c['nombre'] ?? '').toString().trim().isNotEmpty).toList(),
      'beneficiarios': benef
          .map((b) => {...b, 'porcentaje': double.tryParse('${b['porcentaje'] ?? ''}') ?? 0})
          .toList(),
      for (final f in _fechas.entries) f.key: f.value == null ? null : _f(f.value!),
      ..._opciones,
      'foto': _foto,
      if (_consentimiento && !eraConsentido) ...{
        'consentimiento_at': DateTime.now().toUtc().toIso8601String(),
        'consentimiento_por': sb.auth.currentUser?.id,
      },
      if (!_consentimiento && eraConsentido) ...{
        'consentimiento_at': null,
        'consentimiento_por': null,
      },
    };
    if (!_contratoConFin) datos['fecha_fin_contrato'] = null;
    if ((datos['infonavit_credito'] as String?) == null) {
      datos['infonavit_tipo'] = null;
      datos['infonavit_valor'] = null;
    }
    try {
      final e = await Repo.guardarEmpleado(_e?.id, datos);
      if (mounted) Navigator.pop(context, e);
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  bool get _contratoConFin => const {'determinado', 'obra', 'temporada', 'prueba', 'capacitacion'}
      .contains(_opciones['tipo_contrato']);

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final resp = context.resp;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar expediente' : 'Alta de empleado'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12.r),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: Size(96.r, 40.r)),
              onPressed: _guardando || _cargando ? null : _guardar,
              child: _guardando
                  ? SizedBox(width: 18.r, height: 18.r, child: CircularProgressIndicator(strokeWidth: 2.r, color: Colors.white))
                  : Text('Guardar'),
            ),
          ),
        ],
        bottom: _cargando
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(52.r),
                child: SizedBox(
                  height: 52.r,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: resp.margen, vertical: 8.r),
                    children: [
                      for (final s in _secciones)
                        Padding(
                          padding: EdgeInsets.only(right: 6.r),
                          child: ChoiceChip(
                            avatar: Icon(s.icono, size: 16.r),
                            label: Text(s.titulo),
                            selected: _activa == s.id,
                            showCheckmark: false,
                            onSelected: (_) => _ir(s.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              // Todo el formulario se construye completo (Column, no ListView)
              // para que la validación revise también lo que no está a la vista.
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(resp.margen, 8.r, resp.margen, 120.r),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 860.r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _encabezado(),
                        _personales(),
                        _contacto(),
                        _puesto(),
                        _nomina(),
                        _banco(),
                        _emergenciaSec(),
                        _beneficiariosSec(),
                        _uniforme(),
                        _consentimientoSec(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // --- piezas reutilizables --------------------------------------------------

  Widget _titulo(String id) {
    final s = _secciones.firstWhere((x) => x.id == id);
    return KeyedSubtree(key: _anclas[id], child: SectionTitle(s.titulo));
  }

  /// Acomoda campos en 1, 2 o 3 columnas según el ancho.
  Widget _rejilla(List<Widget> campos) {
    return LayoutBuilder(builder: (context, cs) {
      final cols = cs.maxWidth >= 720 ? 3 : (cs.maxWidth >= 460 ? 2 : 1);
      final gap = 12.r;
      final w = (cs.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 12.r,
        children: [for (final c in campos) SizedBox(width: c is _Ancho ? cs.maxWidth : w, child: c)],
      );
    });
  }

  Widget _campo(
    String col,
    String label, {
    String? Function(String?)? validator,
    TextInputType? teclado,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? formato,
    IconData? icono,
    String? ayuda,
    Widget? sufijo,
    int? max,
    ValueChanged<String>? onChanged,
    int lineas = 1,
  }) {
    return TextFormField(
      controller: _t(col),
      validator: validator,
      keyboardType: teclado,
      textCapitalization: caps,
      inputFormatters: [...?formato, if (max != null) LengthLimitingTextInputFormatter(max)],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: onChanged,
      minLines: lineas,
      maxLines: lineas == 1 ? 1 : lineas + 2,
      decoration: InputDecoration(
        labelText: label,
        helperText: ayuda,
        helperMaxLines: 2,
        prefixIcon: icono == null ? null : Icon(icono),
        suffixIcon: sufijo,
      ),
    );
  }

  Widget _fecha(String col, String label, {DateTime? desde, DateTime? hasta, IconData icono = Icons.event_outlined}) {
    final v = _fechas[col];
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.field.r),
      onTap: () async {
        final r = await showDatePicker(
          context: context,
          initialDate: v ?? (col == 'fecha_nacimiento' ? DateTime(1995) : DateTime.now()),
          firstDate: desde ?? DateTime(1940),
          lastDate: hasta ?? DateTime.now().add(Duration(days: 3650)),
        );
        if (r != null) setState(() => _fechas[col] = r);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icono),
          suffixIcon: v == null
              ? null
              : IconButton(icon: Icon(Icons.close, size: 18.r), onPressed: () => setState(() => _fechas[col] = null)),
        ),
        child: Text(v == null ? 'Sin capturar' : fechaCorta(v), style: TextStyle(color: v == null ? context.c.muted : null)),
      ),
    );
  }

  Widget _menu(String col, String label, Map<String, String> opciones, {IconData? icono, bool vacio = true}) {
    final v = _opciones[col];
    return DropdownButtonFormField<String?>(
      initialValue: opciones.containsKey(v) ? v : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: icono == null ? null : Icon(icono)),
      items: [
        if (vacio) DropdownMenuItem<String?>(value: null, child: Text('—', style: TextStyle(color: context.c.muted))),
        for (final o in opciones.entries)
          DropdownMenuItem<String?>(value: o.key, child: Text(o.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (x) => setState(() => _opciones[col] = x),
    );
  }

  Map<String, String> _lista(List<String> l) => {for (final x in l) x: x};

  Widget _sugerido(String col, String label, List<String> opciones, {IconData? icono}) {
    final ctl = _t(col);
    return RawAutocomplete<String>(
      textEditingController: ctl,
      focusNode: _focos.putIfAbsent(col, FocusNode.new),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return opciones;
        return opciones.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q);
      },
      fieldViewBuilder: (context, c, foco, enviar) => TextFormField(
        controller: c,
        focusNode: foco,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, prefixIcon: icono == null ? null : Icon(icono)),
      ),
      optionsViewBuilder: (context, elegir, opciones) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14.r),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 240.r, maxWidth: 360.r),
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 6.r),
              shrinkWrap: true,
              children: [for (final o in opciones) ListTile(dense: true, title: Text(o), onTap: () => elegir(o))],
            ),
          ),
        ),
      ),
    );
  }

  static final _soloDigitos = FilteringTextInputFormatter.digitsOnly;
  static final _mayus = _Mayusculas();

  // --- secciones -------------------------------------------------------------

  Widget _encabezado() {
    final nombre = '${_t('nombres').text} ${_t('apellido_paterno').text}'.trim();
    return Padding(
      padding: EdgeInsets.only(top: 8.r),
      child: Column(
        children: [
          GestureDetector(
            onTap: _menuFoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Avatar(nombre: nombre.isEmpty ? '+' : nombre, foto: _foto, size: 112.r, ring: context.scheme.primary.withValues(alpha: 0.25)),
                Positioned(
                  right: 2.r,
                  bottom: 2.r,
                  child: Container(
                    padding: EdgeInsets.all(9.r),
                    decoration: BoxDecoration(
                      color: context.scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3.r),
                    ),
                    child: Icon(Icons.photo_camera, size: 18.r, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 6.r),
          Text('Foto de credencial: sale en el kiosco al checar', style: TextStyle(color: context.c.muted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _personales() {
    final curpOk = _t('curp').text.trim().length == 18 && validarCurp(_t('curp').text) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('personal'),
        Panel(
          child: _rejilla([
            _campo('numero', 'Número de empleado', validator: _req, caps: TextCapitalization.characters, icono: Icons.tag),
            _campo('nombres', 'Nombre(s)', validator: _req, caps: TextCapitalization.words, onChanged: (_) => setState(() {})),
            _campo('apellido_paterno', 'Apellido paterno', validator: _req, caps: TextCapitalization.words,
                onChanged: (_) => setState(() {})),
            _campo('apellido_materno', 'Apellido materno', caps: TextCapitalization.words),
            _campo('curp', 'CURP',
                validator: (v) => validarCurp(v),
                caps: TextCapitalization.characters,
                formato: [_mayus],
                max: 18,
                icono: Icons.fingerprint,
                ayuda: 'Llena sola nacimiento, sexo y lugar',
                sufijo: curpOk ? Icon(Icons.verified, color: context.c.ok) : null,
                onChanged: _curpCambio),
            _campo('rfc', 'RFC (con homoclave)',
                validator: (v) => validarRfc(v, curp: _t('curp').text),
                caps: TextCapitalization.characters,
                formato: [_mayus],
                max: 13,
                ayuda: 'Como aparece en la Constancia de Situación Fiscal'),
            _campo('nss', 'Número de Seguridad Social (NSS)',
                validator: validarNss, teclado: TextInputType.number, formato: [_soloDigitos], max: 11, icono: Icons.local_hospital_outlined),
            _fecha('fecha_nacimiento', 'Fecha de nacimiento', hasta: DateTime.now(), icono: Icons.cake_outlined),
            _menu('sexo', 'Sexo', {'H': 'Hombre', 'M': 'Mujer', 'X': 'No binario'}),
            _menu('estado_civil', 'Estado civil', _lista(estadosCiviles)),
            _campo('nacionalidad', 'Nacionalidad', caps: TextCapitalization.words),
            _menu('lugar_nacimiento', 'Lugar de nacimiento', _lista([...entidades, 'Nacido en el extranjero'])),
            _menu('escolaridad', 'Escolaridad', _lista(escolaridades), icono: Icons.school_outlined),
            _menu('tipo_sangre', 'Tipo de sangre', _lista(tiposSangre), icono: Icons.bloodtype_outlined),
            _Ancho(_campo('alergias', 'Alergias o condiciones médicas a considerar en una emergencia',
                caps: TextCapitalization.sentences, ayuda: 'Dato sensible: solo lo ve RH. Opcional.')),
          ]),
        ),
      ],
    );
  }

  Widget _contacto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('contacto'),
        Panel(
          child: _rejilla([
            _campo('telefono', 'Celular', validator: validarTelefono, teclado: TextInputType.phone, icono: Icons.smartphone),
            _campo('telefono_casa', 'Teléfono de casa', validator: validarTelefono, teclado: TextInputType.phone, icono: Icons.phone_outlined),
            _campo('correo', 'Correo personal', validator: validarCorreo, teclado: TextInputType.emailAddress, icono: Icons.mail_outline),
            _campo('correo_empresa', 'Correo de la empresa', validator: validarCorreo, teclado: TextInputType.emailAddress, icono: Icons.alternate_email),
            _Ancho(_campo('calle', 'Calle', caps: TextCapitalization.words, icono: Icons.signpost_outlined)),
            _campo('num_ext', 'Número exterior'),
            _campo('num_int', 'Número interior'),
            _campo('colonia', 'Colonia', caps: TextCapitalization.words),
            _campo('cp', 'Código postal', validator: validarCp, teclado: TextInputType.number, formato: [_soloDigitos], max: 5),
            _campo('municipio', 'Municipio', caps: TextCapitalization.words),
            _menu('estado', 'Estado', _lista(entidades)),
          ]),
        ),
      ],
    );
  }

  Widget _puesto() {
    final c = context.c;
    final ingreso = _fechas['fecha_ingreso'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('puesto'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rejilla([
                _sugerido('puesto', 'Puesto', _puestos, icono: Icons.work_outline),
                _sugerido('departamento', 'Departamento', _deptos, icono: Icons.apartment),
                DropdownButtonFormField<String?>(
                  initialValue: _jefes.any((j) => j.id == _jefeId) ? _jefeId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Jefe directo', prefixIcon: Icon(Icons.supervisor_account_outlined)),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text('—', style: TextStyle(color: c.muted))),
                    for (final j in _jefes)
                      DropdownMenuItem<String?>(
                        value: j.id,
                        child: Text('${j.nombre}${j.puesto != null ? ' · ${j.puesto}' : ''}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _jefeId = v),
                ),
                _fecha('fecha_ingreso', 'Fecha de ingreso', icono: Icons.login),
                _menu('tipo_contrato', 'Tipo de contrato', tiposContrato, vacio: false, icono: Icons.description_outlined),
                if (_contratoConFin) _fecha('fecha_fin_contrato', 'Fin del contrato', icono: Icons.event_busy_outlined),
                _fecha('fin_periodo_prueba', 'Fin del periodo de prueba', icono: Icons.hourglass_bottom),
                _menu('jornada', 'Jornada', jornadas, vacio: false, icono: Icons.wb_sunny_outlined),
              ]),
              if (ingreso != null) ...[
                SizedBox(height: 10.r),
                Text(
                  'Antigüedad: ${antiguedadTexto(ingreso)} · vacaciones de ley este año: '
                  '${diasVacaciones(aniosEntre(ingreso, DateTime.now()) + 1)} días',
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ],
              SizedBox(height: 18.r),
              Text('Asistencia', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 10.r),
              _rejilla([
                if (_sedes.isEmpty)
                  StatusChip(label: 'Primero da de alta una sede en la pestaña Sedes', color: c.warn, icon: Icons.place_outlined)
                else
                  DropdownButtonFormField<String>(
                    initialValue: _sedeId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Sede', prefixIcon: Icon(Icons.place_outlined)),
                    items: [for (final s in _sedes) DropdownMenuItem(value: s.id, child: Text(s.nombre))],
                    onChanged: (v) => setState(() => _sedeId = v),
                  ),
                DropdownButtonFormField<String?>(
                  initialValue: _turnoId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Turno', prefixIcon: Icon(Icons.schedule)),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text('Sin turno (no calcula retardos)')),
                    for (final t in _turnos)
                      DropdownMenuItem<String?>(value: t.id, child: Text('${t.nombre} · ${t.entrada}–${t.salida}')),
                  ],
                  onChanged: (v) => setState(() => _turnoId = v),
                ),
              ]),
              SizedBox(height: 14.r),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'planta', icon: Icon(Icons.face), label: Text('Kiosco')),
                  ButtonSegment(value: 'administrativo', icon: Icon(Icons.smartphone), label: Text('Kiosco + celular')),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() {
                  _tipo = s.first;
                  _checaMovil = _tipo == 'administrativo';
                }),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _checaMovil,
                onChanged: (v) => setState(() => _checaMovil = v),
                title: Text('Checa desde su celular', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Con la biometría de su teléfono y su ubicación, solo dentro de la geocerca de una sede.',
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nomina() {
    final tieneInfonavit = _t('infonavit_credito').text.trim().isNotEmpty;
    final dinero = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('nomina'),
        Panel(
          child: _rejilla([
            _campo('salario_diario', 'Salario diario', teclado: TextInputType.numberWithOptions(decimal: true),
                formato: dinero, icono: Icons.attach_money),
            _campo('sdi', 'Salario diario integrado (SDI)',
                teclado: TextInputType.numberWithOptions(decimal: true),
                formato: dinero,
                icono: Icons.functions,
                sufijo: IconButton(tooltip: 'Calcular con el factor de ley', icon: Icon(Icons.calculate_outlined), onPressed: _calcularSdi)),
            _menu('periodicidad_pago', 'Periodicidad de pago', periodicidades, vacio: false),
            _menu('forma_pago', 'Forma de pago', formasPago, vacio: false),
            _menu('regimen_fiscal', 'Régimen fiscal (CFDI)', regimenesFiscales, vacio: false),
            _campo('cp_fiscal', 'CP fiscal (de la constancia del SAT)',
                validator: validarCp,
                teclado: TextInputType.number,
                formato: [_soloDigitos],
                max: 5,
                sufijo: IconButton(
                  tooltip: 'Igual al del domicilio',
                  icon: Icon(Icons.content_copy, size: 18.r),
                  onPressed: () => setState(() => _t('cp_fiscal').text = _t('cp').text),
                )),
            _campo('registro_patronal', 'Registro patronal IMSS', caps: TextCapitalization.characters, max: 11),
            _fecha('fecha_alta_imss', 'Fecha de alta en el IMSS', icono: Icons.local_hospital_outlined),
            _campo('umf', 'Unidad de Medicina Familiar (UMF)', teclado: TextInputType.number),
            _campo('infonavit_credito', 'Crédito INFONAVIT (número)', teclado: TextInputType.number,
                formato: [_soloDigitos], icono: Icons.house_outlined, onChanged: (_) => setState(() {})),
            if (tieneInfonavit) _menu('infonavit_tipo', 'Tipo de descuento', tiposInfonavit),
            if (tieneInfonavit)
              _campo('infonavit_valor', 'Valor del descuento',
                  teclado: TextInputType.numberWithOptions(decimal: true), formato: dinero),
            _campo('fonacot_credito', 'Crédito FONACOT (número)', teclado: TextInputType.number),
          ]),
        ),
      ],
    );
  }

  Widget _banco() {
    final clabe = _t('clabe').text;
    final detectado = bancoDeClabe(clabe);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('banco'),
        Panel(
          child: _rejilla([
            _campo('clabe', 'CLABE interbancaria',
                validator: validarClabe,
                teclado: TextInputType.number,
                formato: [_soloDigitos],
                max: 18,
                icono: Icons.account_balance_outlined,
                ayuda: detectado != null ? 'Banco: $detectado' : '18 dígitos; el banco se detecta solo',
                onChanged: (v) {
                  final b = bancoDeClabe(v);
                  if (b != null && v.length >= 3) _t('banco').text = b;
                  setState(() {});
                }),
            _campo('banco', 'Banco', caps: TextCapitalization.words),
            _campo('cuenta', 'Número de cuenta o tarjeta', teclado: TextInputType.number, formato: [_soloDigitos], max: 20),
          ]),
        ),
      ],
    );
  }

  Widget _emergenciaSec() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('emergencia'),
        _ListaPersonas(
          filas: _emergencia,
          tercero: 'telefono',
          terceroLabel: 'Teléfono',
          vacio: 'A quién llamar si le pasa algo en planta.',
          agregar: 'Agregar contacto',
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  Widget _beneficiariosSec() {
    final suma = _beneficiarios.fold<double>(0, (a, b) => a + (double.tryParse('${b['porcentaje'] ?? ''}') ?? 0));
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('beneficiarios'),
        _ListaPersonas(
          filas: _beneficiarios,
          tercero: 'porcentaje',
          terceroLabel: '%',
          vacio: 'LFT art. 25 fr. X: el contrato debe designar beneficiarios para salarios y prestaciones pendientes '
              'en caso de fallecimiento.',
          agregar: 'Agregar beneficiario',
          onChanged: () => setState(() {}),
        ),
        if (_beneficiarios.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 6.r, left: 4.r),
            child: Text(
              'Suma: ${suma.toStringAsFixed(0)} %${(suma - 100).abs() > 0.01 ? ' (debe ser 100 %)' : ' ✓'}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: (suma - 100).abs() > 0.01 ? c.warn : c.ok,
              ),
            ),
          ),
      ],
    );
  }

  Widget _uniforme() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('uniforme'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rejilla([
                _campo('talla_camisa', 'Talla de camisa', caps: TextCapitalization.characters, icono: Icons.checkroom_outlined),
                _campo('talla_pantalon', 'Talla de pantalón', caps: TextCapitalization.characters),
                _campo('talla_calzado', 'Talla de calzado (mx)', teclado: TextInputType.numberWithOptions(decimal: true)),
              ]),
              SizedBox(height: 12.r),
              _campo('notas', 'Notas de RH', caps: TextCapitalization.sentences, lineas: 3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _consentimientoSec() {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('consentimiento'),
        Panel(
          color: _consentimiento ? null : c.warn.withValues(alpha: context.isDark ? 0.14 : 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _consentimiento,
                onChanged: (v) => setState(() => _consentimiento = v ?? false),
                title: Text(
                  'El empleado firmó el aviso de privacidad y autoriza el uso de su rostro, huella y ubicación para checar',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              TextButton.icon(onPressed: _verAviso, icon: Icon(Icons.policy_outlined, size: 18.r), label: Text('Leer el aviso')),
              if (!_consentimiento)
                Text('Sin esto no se puede registrar su rostro ni su huella, ni vincular su celular.',
                    style: TextStyle(color: c.warn, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Marca un campo para que ocupe todo el renglón en la rejilla.
class _Ancho extends StatelessWidget {
  const _Ancho(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _Mayusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Lista editable de personas: nombre, parentesco y un tercer dato
/// (teléfono o porcentaje). Modifica [filas] en su lugar.
class _ListaPersonas extends StatefulWidget {
  const _ListaPersonas({
    required this.filas,
    required this.tercero,
    required this.terceroLabel,
    required this.vacio,
    required this.agregar,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> filas;
  final String tercero;
  final String terceroLabel;
  final String vacio;
  final String agregar;
  final VoidCallback onChanged;

  @override
  State<_ListaPersonas> createState() => _ListaPersonasState();
}

class _ListaPersonasState extends State<_ListaPersonas> {
  // Una llave estable por fila para que los campos no se revuelvan al borrar.
  final _llaves = <Map<String, dynamic>, Key>{};

  Key _llave(Map<String, dynamic> f) => _llaves.putIfAbsent(f, UniqueKey.new);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final esPorcentaje = widget.tercero == 'porcentaje';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.vacio, style: TextStyle(color: c.muted, fontSize: 12.5)),
          for (final (i, f) in widget.filas.indexed)
            Padding(
              key: _llave(f),
              padding: EdgeInsets.only(top: 12.r),
              child: LayoutBuilder(builder: (context, cs) {
                final ancho = cs.maxWidth >= 560;
                final nombre = TextFormField(
                  initialValue: f['nombre'] as String?,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline)),
                  onChanged: (v) {
                    f['nombre'] = v;
                    widget.onChanged();
                  },
                );
                final parentesco = DropdownButtonFormField<String?>(
                  initialValue: parentescos.contains(f['parentesco']) ? f['parentesco'] as String : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Parentesco'),
                  items: [for (final p in parentescos) DropdownMenuItem<String?>(value: p, child: Text(p))],
                  onChanged: (v) => f['parentesco'] = v,
                );
                final tercero = TextFormField(
                  initialValue: f[widget.tercero]?.toString(),
                  keyboardType: esPorcentaje ? TextInputType.numberWithOptions(decimal: true) : TextInputType.phone,
                  validator: esPorcentaje ? null : validarTelefono,
                  decoration: InputDecoration(labelText: widget.terceroLabel, suffixText: esPorcentaje ? '%' : null),
                  onChanged: (v) {
                    f[widget.tercero] = v;
                    widget.onChanged();
                  },
                );
                final quitar = IconButton(
                  tooltip: 'Quitar',
                  icon: Icon(Icons.remove_circle_outline, color: c.danger),
                  onPressed: () {
                    setState(() => widget.filas.removeAt(i));
                    widget.onChanged();
                  },
                );
                if (ancho) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: nombre),
                      SizedBox(width: 10.r),
                      Expanded(flex: 3, child: parentesco),
                      SizedBox(width: 10.r),
                      Expanded(flex: 3, child: tercero),
                      quitar,
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(children: [Expanded(child: nombre), quitar]),
                    SizedBox(height: 8.r),
                    Row(children: [Expanded(child: parentesco), SizedBox(width: 10.r), Expanded(child: tercero)]),
                    if (i < widget.filas.length - 1) Divider(height: 24.r),
                  ],
                );
              }),
            ),
          SizedBox(height: 8.r),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => widget.filas.add({}));
                widget.onChanged();
              },
              icon: Icon(Icons.add),
              label: Text(widget.agregar),
            ),
          ),
        ],
      ),
    );
  }
}
