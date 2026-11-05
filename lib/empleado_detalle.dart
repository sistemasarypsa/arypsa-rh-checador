import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'codigo_sheet.dart';
import 'datos.dart';
import 'empleado_form.dart';
import 'expediente_docs.dart';
import 'mx.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

class EmpleadoDetalle extends StatefulWidget {
  const EmpleadoDetalle({required this.empleadoId, this.recienCreado = false, super.key});

  final String empleadoId;
  final bool recienCreado;

  @override
  State<EmpleadoDetalle> createState() => _EmpleadoDetalleState();
}

class _EmpleadoDetalleState extends State<EmpleadoDetalle> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 5, vsync: this);

  Empleado? _e;
  Equipo? _celular;
  List<Checada> _checadas = const [];
  Map<String, String> _sedes = const {};
  Map<String, Turno> _turnos = const {};
  Map<String, String> _nombres = const {};
  List<Movimiento>? _historial;
  (int, int)? _expediente;
  String? _error;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait<Object?>([
        Repo.expediente(widget.empleadoId),
        Repo.celularDe(widget.empleadoId),
        Repo.checadasDe(widget.empleadoId, limite: 120),
        Repo.sedes(),
        Repo.turnos(),
        Repo.empleados(),
        Repo.historialDe(widget.empleadoId).then<List<Movimiento>?>((v) => v).catchError((_) => null),
        _avanceExpediente(),
      ]);
      if (!mounted) return;
      setState(() {
        _e = r[0] as Empleado;
        _celular = r[1] as Equipo?;
        _checadas = r[2] as List<Checada>;
        _sedes = {for (final s in r[3] as List<Sede>) s.id!: s.nombre};
        _turnos = {for (final t in r[4] as List<Turno>) t.id!: t};
        _nombres = {for (final e in r[5] as List<Empleado>) e.id!: e.nombre};
        _historial = r[6] as List<Movimiento>?;
        _expediente = r[7] as (int, int)?;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    }
  }

  /// (entregados, obligatorios) del expediente; null si falta el SQL 003.
  Future<(int, int)?> _avanceExpediente() async {
    try {
      final r = await Future.wait<Object>([Repo.tiposDocumento(), Repo.documentosDe(widget.empleadoId)]);
      final tipos = r[0] as List<TipoDocumento>;
      final est = Repo.estadoExpediente(tipos, r[1] as List<Documento>);
      final ob = tipos.where((t) => t.obligatorio).toList();
      final ok = ob.where((t) => est[t.id]!.$1 == EstadoDoc.ok || est[t.id]!.$1 == EstadoDoc.vencePronto).length;
      return (ok, ob.length);
    } catch (_) {
      return null;
    }
  }

  Future<void> _accion(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _codigoHuella() => _accion(() async {
        final e = _e!;
        final k = await Repo.generarCodigo('huella', empleado: e.id);
        if (!mounted) return;
        await mostrarCodigo(
          context,
          codigo: k,
          titulo: 'Registrar rostro y huella',
          para: e.nombre,
          pasos: [
            'Lleva al empleado al kiosco (la tablet de la entrada).',
            'En el kiosco, mantén presionado el logotipo (o el engrane de arriba a la derecha) un segundo y elige "Registrar rostro / huella".',
            'Escanea este QR o teclea el código.',
            'Rostro: que se pare de frente, con luz en la cara, sin lentes oscuros ni gorra; la tablet toma 5 fotos sola.',
            'Huella (si hay lector): el mismo dedo 3 veces; mejor dos dedos. Al final, Guardar.',
          ],
        );
        await _cargar();
      });

  Future<void> _codigoCelular() => _accion(() async {
        final e = _e!;
        if (_celular != null &&
            !await confirmar(
              context,
              titulo: 'Ya tiene un celular',
              mensaje: 'Si vincula otro teléfono, el actual (${_celular!.modelo ?? _celular!.nombre}) deja de poder checar.',
              si: 'Generar código',
            )) {
          return;
        }
        final k = await Repo.generarCodigo('movil', empleado: e.id);
        if (!mounted) return;
        await mostrarCodigo(
          context,
          codigo: k,
          titulo: 'Vincular celular',
          para: e.nombre,
          pasos: [
            'En el celular del empleado, instala y abre "Arypsa Checador".',
            'Elige "Mi celular" y escanea este QR (o teclea el código).',
            'Acepta el permiso de ubicación ("Mientras se usa la app") y confirma con la huella o Face ID del teléfono.',
            'Listo: solo podrá checar dentro de la geocerca de una sede.',
          ],
        );
        await _cargar();
      });

  Future<void> _borrarHuellas() async {
    if (!await confirmar(
      context,
      titulo: 'Borrar huellas',
      mensaje: 'El empleado no podrá checar en el kiosco hasta que vuelva a registrar su huella.',
      si: 'Borrar',
      peligro: true,
    )) {
      return;
    }
    await _accion(() async {
      await Repo.borrarHuellas(_e!.id!);
      await _cargar();
    });
  }

  Future<void> _borrarRostro() async {
    if (!await confirmar(
      context,
      titulo: 'Borrar rostro',
      mensaje: 'El empleado ya no podrá checar con la cara hasta que se registre de nuevo.',
      si: 'Borrar',
      peligro: true,
    )) {
      return;
    }
    await _accion(() async {
      await Repo.borrarRostros(_e!.id!);
      await _cargar();
    });
  }

  Future<void> _desvincular() async {
    if (!await confirmar(
      context,
      titulo: 'Desvincular celular',
      mensaje: 'Ese teléfono dejará de poder checar de inmediato.',
      si: 'Desvincular',
      peligro: true,
    )) {
      return;
    }
    await _accion(() async {
      await Repo.desactivarEquipo(_celular!.id);
      await _cargar();
    });
  }

  Future<void> _editar([String? seccion]) async {
    final r = await Navigator.of(context).push<Empleado>(
      MaterialPageRoute(builder: (_) => EmpleadoForm(empleado: _e, seccion: seccion), fullscreenDialog: true),
    );
    if (r != null) await _cargar();
  }

  Future<void> _baja() async {
    final datos = await showModalBottomSheet<({DateTime fecha, String tipo, String? motivo, bool recontratable})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _HojaBaja(nombre: _e!.nombre),
    );
    if (datos == null) return;
    await _accion(() async {
      try {
        await Repo.bajaEmpleado(_e!.id!,
            fecha: datos.fecha, tipo: datos.tipo, motivo: datos.motivo, recontratable: datos.recontratable);
      } catch (e) {
        // Sin el SQL 003 todavía: baja simple.
        if (!mensajeError(e).contains('003')) rethrow;
        await Repo.darBaja(_e!.id!);
      }
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _reactivar() async {
    if (!await confirmar(
      context,
      titulo: 'Reactivar (recontratar)',
      mensaje: 'Vuelve a la lista de activos. Tendrá que registrar de nuevo su rostro y huella en el kiosco. '
          'Revisa su fecha de ingreso, contrato y salario en Editar.',
      si: 'Reactivar',
    )) {
      return;
    }
    await _accion(() async {
      await Repo.reactivar(_e!.id!);
      await _cargar();
    });
  }

  Future<void> _revisar(Checada ch) async {
    final nota = TextEditingController(text: ch.nota);
    final estado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(context.resp.margen, 0, context.resp.margen, 20.r + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${ch.tipo == 'entrada' ? 'Entrada' : 'Salida'} · ${fechaCorta(ch.ts)} ${hhmm(ch.ts)}',
              style: TextStyle(fontFamily: AppFont.display, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6.r),
            Text(_detalleChecada(ch), style: TextStyle(color: ctx.c.muted, height: 1.4)),
            SizedBox(height: 16.r),
            TextField(controller: nota, decoration: InputDecoration(labelText: 'Nota (opcional)')),
            SizedBox(height: 16.r),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ctx.c.ok),
              onPressed: () => Navigator.pop(ctx, 'valida'),
              icon: Icon(Icons.check),
              label: Text('Aceptar como válida'),
            ),
            SizedBox(height: 8.r),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'anulada'),
              icon: Icon(Icons.block, color: ctx.c.danger),
              label: Text('Anular', style: TextStyle(color: ctx.c.danger)),
            ),
          ],
        ),
      ),
    );
    if (estado == null) return;
    await _accion(() async {
      await Repo.revisarChecada(ch.id, estado, nota.text.trim().isEmpty ? null : nota.text.trim());
      await _cargar();
    });
  }

  String _detalleChecada(Checada ch) {
    final partes = <String>[
      switch (ch.metodo) {
        'lector' => 'Kiosco · huella',
        'rostro' => 'Kiosco · reconocimiento facial',
        'rostro+huella' => 'Kiosco · rostro + huella',
        _ => 'Celular (biometría del teléfono)',
      },
      if (ch.sede != null) 'Sede más cercana: ${ch.sede} a ${metros(ch.distanciaM)}',
      if (ch.precisionM != null) 'Precisión del GPS: ±${metros(ch.precisionM)}',
      if (ch.gpsSimulado) '⚠ El teléfono reportó ubicación simulada',
      if (ch.lat == null) '⚠ Sin ubicación',
    ];
    return partes.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    return Scaffold(
        appBar: AppBar(
          title: e == null ? null : Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (e != null)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'editar') _editar();
                  if (v == 'baja') _baja();
                  if (v == 'reactivar') _reactivar();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'editar', child: Text('Editar expediente')),
                  if (e.activo)
                    PopupMenuItem(value: 'baja', child: Text('Dar de baja'))
                  else
                    PopupMenuItem(value: 'reactivar', child: Text('Reactivar (recontratar)')),
                ],
              ),
          ],
          bottom: e == null
              ? null
              : TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Resumen'),
                    Tab(text: 'Datos'),
                    Tab(text: 'Expediente'),
                    Tab(text: 'Asistencia'),
                    Tab(text: 'Historial'),
                  ],
                ),
        ),
        body: _error != null
            ? EmptyState(
                icon: Icons.cloud_off,
                title: 'No se pudo cargar',
                message: _error,
                action: OutlinedButton(onPressed: _cargar, child: Text('Reintentar')),
              )
            : e == null
                ? Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      TabBarView(
                        controller: _tabs,
                        children: [
                          RefreshIndicator(onRefresh: _cargar, child: _resumen(e)),
                          RefreshIndicator(onRefresh: _cargar, child: _datos(e)),
                          ExpedienteDocs(empleado: e, onCambio: _cargar),
                          RefreshIndicator(onRefresh: _cargar, child: _asistencia()),
                          RefreshIndicator(onRefresh: _cargar, child: _historialVista()),
                        ],
                      ),
                      if (_ocupado) Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
                    ],
                  ),
    );
  }

  EdgeInsets get _pad => EdgeInsets.fromLTRB(context.resp.margen, 12.r, context.resp.margen, 32.r);

  // ---------------------------------------------------------------------------
  // Resumen
  // ---------------------------------------------------------------------------

  Widget _resumen(Empleado e) {
    final c = context.c;
    final turno = _turnos[e.turnoId];
    final puedeBiometria = e.consentimientoAt != null && e.activo;
    final ingreso = e.fechaIngreso;
    final nac = e.fechaNacimiento;
    final hoy = DateTime.now();
    final fin = e.finContrato;
    final prueba = e.fecha('fin_periodo_prueba');
    final exp = _expediente;

    return ListView(
      padding: _pad,
      children: [
        Center(child: Avatar(nombre: e.nombre, foto: e.foto, size: 96.r)),
        SizedBox(height: 10.r),
        Text(
          e.nombre,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: AppFont.display, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        SizedBox(height: 4.r),
        Text(
          ['#${e.numero}', if ((e.puesto ?? '').isNotEmpty) e.puesto!, if ((e.departamento ?? '').isNotEmpty) e.departamento!]
              .join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted),
        ),
        SizedBox(height: 10.r),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6.r,
          runSpacing: 6.r,
          children: [
            if (!e.activo)
              StatusChip(
                label: 'Baja${e.fecha('fecha_baja') != null ? ' ${fechaCorta(e.fecha('fecha_baja')!)}' : ''}'
                    '${tiposBaja[e.txt('tipo_baja')] != null ? ' · ${tiposBaja[e.txt('tipo_baja')]}' : ''}',
                color: c.danger,
                icon: Icons.person_off_outlined,
              ),
            if (e.sedeId != null) StatusChip(label: _sedes[e.sedeId] ?? 'Sede', color: c.info, icon: Icons.place_outlined),
            if (turno != null)
              StatusChip(label: '${turno.nombre} ${turno.entrada}–${turno.salida}', color: c.muted, icon: Icons.schedule),
            if (e.txt('tipo_contrato') != null)
              StatusChip(label: tiposContrato[e.txt('tipo_contrato')] ?? '', color: c.muted, icon: Icons.description_outlined),
          ],
        ),

        // Avisos
        if (widget.recienCreado && !e.biometriaKiosco && puedeBiometria)
          _aviso(Icons.celebration_outlined, context.scheme.primary,
              'Alta lista. Siguiente: sube sus documentos (pestaña Expediente) y registra su rostro en el kiosco.'),
        if (e.consentimientoAt == null && e.activo)
          _aviso(Icons.policy_outlined, c.warn, 'Falta el consentimiento firmado. Sin él no se registra rostro, huella ni celular. Toca para editar.',
              onTap: () => _editar('consentimiento')),
        if (exp != null && exp.$1 < exp.$2 && e.activo)
          _aviso(Icons.folder_open_outlined, c.warn,
              'Expediente incompleto: ${exp.$1} de ${exp.$2} documentos obligatorios. Ve a la pestaña Expediente.',
              onTap: () => _tabs.animateTo(2)),
        if (fin != null && e.activo && fin.difference(hoy).inDays <= 30)
          _aviso(Icons.event_busy_outlined, fin.isBefore(hoy) ? c.danger : c.warn,
              fin.isBefore(hoy)
                  ? 'El contrato venció el ${fechaCorta(fin)}. Renueva o define su situación.'
                  : 'El contrato vence el ${fechaCorta(fin)} (en ${fin.difference(hoy).inDays + 1} días).',
              onTap: () => _editar('puesto')),
        if (prueba != null && e.activo && !prueba.isBefore(hoy) && prueba.difference(hoy).inDays <= 15)
          _aviso(Icons.hourglass_bottom, c.info, 'Su periodo de prueba termina el ${fechaCorta(prueba)}: toca evaluarlo.'),
        if (e.activo && (e.txt('curp') == null || e.txt('rfc') == null || e.txt('nss') == null))
          _aviso(Icons.badge_outlined, c.warn,
              'Faltan datos para el IMSS y la nómina: ${[if (e.txt('curp') == null) 'CURP', if (e.txt('rfc') == null) 'RFC', if (e.txt('nss') == null) 'NSS'].join(', ')}.',
              onTap: () => _editar('personal')),

        SectionTitle('De un vistazo'),
        _Rejilla(children: [
          _Dato('Antigüedad', ingreso == null ? 'Sin fecha de ingreso' : antiguedadTexto(ingreso), Icons.workspace_premium_outlined),
          _Dato(
            'Vacaciones de ley (año en curso)',
            ingreso == null ? '—' : '${diasVacaciones(aniosEntre(ingreso, hoy) + 1)} días',
            Icons.beach_access_outlined,
          ),
          _Dato('Edad', nac == null ? '—' : '${aniosEntre(nac, hoy)} años', Icons.cake_outlined),
          _Dato('Cumpleaños', nac == null ? '—' : _diaMes(nac), Icons.celebration_outlined),
          _Dato('Jefe directo', _nombres[e.jefeId] ?? '—', Icons.supervisor_account_outlined),
          _Dato('Celular', e.telefono ?? '—', Icons.smartphone, copiar: e.telefono),
        ]),

        SectionTitle('Formas de checar'),
        _Metodo(
          icon: Icons.face_retouching_natural,
          titulo: 'Kiosco: rostro y huella',
          estado: [
            e.rostros > 0 ? 'Rostro ✓' : 'Rostro sin registrar',
            e.huellas > 0 ? '${e.huellas} ${e.huellas == 1 ? 'dedo' : 'dedos'} ✓' : 'huella sin registrar',
          ].join(' · '),
          ok: e.biometriaKiosco,
          acciones: [
            FilledButton.tonalIcon(
              onPressed: puedeBiometria && !_ocupado ? _codigoHuella : null,
              icon: Icon(Icons.qr_code_2),
              label: Text(e.biometriaKiosco ? 'Agregar o rehacer' : 'Registrar rostro / huella'),
            ),
            if (e.rostros > 0)
              TextButton(onPressed: _ocupado ? null : _borrarRostro, child: Text('Borrar rostro', style: TextStyle(color: c.danger))),
            if (e.huellas > 0)
              TextButton(onPressed: _ocupado ? null : _borrarHuellas, child: Text('Borrar huellas', style: TextStyle(color: c.danger))),
          ],
        ),
        SizedBox(height: 10.r),
        _Metodo(
          icon: Icons.smartphone,
          titulo: 'Su celular',
          estado: !e.checaMovil
              ? 'No permitido para este empleado'
              : _celular != null
                  ? '${_celular!.modelo ?? 'Vinculado'} · ${haceCuanto(_celular!.ultimoContacto)}'
                  : 'Sin vincular',
          ok: _celular != null,
          acciones: e.checaMovil
              ? [
                  FilledButton.tonalIcon(
                    onPressed: puedeBiometria && !_ocupado ? _codigoCelular : null,
                    icon: Icon(Icons.qr_code_2),
                    label: Text(_celular != null ? 'Cambiar de celular' : 'Vincular celular'),
                  ),
                  if (_celular != null)
                    TextButton(onPressed: _ocupado ? null : _desvincular, child: Text('Desvincular', style: TextStyle(color: c.danger))),
                ]
              : [],
        ),
      ],
    );
  }

  static const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  String _diaMes(DateTime d) => '${d.day} de ${_meses[d.month - 1]}';

  Widget _aviso(IconData icono, Color color, String texto, {VoidCallback? onTap}) {
    return Padding(
      padding: EdgeInsets.only(top: 12.r),
      child: Panel(
        color: color.withValues(alpha: 0.10),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icono, color: color),
            SizedBox(width: 12.r),
            Expanded(child: Text(texto)),
            if (onTap != null) Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Datos (solo lectura, con lápiz por sección)
  // ---------------------------------------------------------------------------

  Widget _datos(Empleado e) {
    String? f(String col) => e.fecha(col) == null ? null : fechaCorta(e.fecha(col)!);
    String? m(String col) => e.num_(col) == null ? null : dineroMx(e.num_(col));
    final domicilio = [
      [e.txt('calle'), e.txt('num_ext'), if (e.txt('num_int') != null) 'int. ${e.txt('num_int')}'].whereType<String>().join(' '),
      e.txt('colonia'),
      [if (e.txt('cp') != null) 'CP ${e.txt('cp')}', e.txt('municipio'), e.txt('estado')].whereType<String>().join(', '),
    ].where((x) => x != null && x.trim().isNotEmpty).join('\n');
    final emergencia = e.lista('contactos_emergencia');
    final benef = e.lista('beneficiarios');

    Widget seccion(String titulo, String id, List<_Dato> datos) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(titulo,
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Editar',
                  icon: Icon(Icons.edit_outlined, size: 18.r),
                  onPressed: () => _editar(id),
                )),
            _Rejilla(children: datos),
          ],
        );

    return ListView(
      padding: _pad,
      children: [
        seccion('Personales', 'personal', [
          _Dato('CURP', e.txt('curp'), Icons.fingerprint, copiar: e.txt('curp')),
          _Dato('RFC', e.txt('rfc'), Icons.receipt_long_outlined, copiar: e.txt('rfc')),
          _Dato('NSS', e.txt('nss'), Icons.local_hospital_outlined, copiar: e.txt('nss')),
          _Dato('Nacimiento', f('fecha_nacimiento'), Icons.cake_outlined),
          _Dato('Sexo', switch (e.txt('sexo')) { 'H' => 'Hombre', 'M' => 'Mujer', 'X' => 'No binario', _ => null }, Icons.wc),
          _Dato('Estado civil', e.txt('estado_civil'), Icons.favorite_border),
          _Dato('Nacionalidad', e.txt('nacionalidad'), Icons.flag_outlined),
          _Dato('Lugar de nacimiento', e.txt('lugar_nacimiento'), Icons.map_outlined),
          _Dato('Escolaridad', e.txt('escolaridad'), Icons.school_outlined),
          _Dato('Tipo de sangre', e.txt('tipo_sangre'), Icons.bloodtype_outlined),
          _Dato('Alergias / condiciones', e.txt('alergias'), Icons.medical_information_outlined),
        ]),
        seccion('Contacto y domicilio', 'contacto', [
          _Dato('Celular', e.telefono, Icons.smartphone, copiar: e.telefono),
          _Dato('Teléfono de casa', e.txt('telefono_casa'), Icons.phone_outlined, copiar: e.txt('telefono_casa')),
          _Dato('Correo personal', e.correo, Icons.mail_outline, copiar: e.correo),
          _Dato('Correo de la empresa', e.txt('correo_empresa'), Icons.alternate_email, copiar: e.txt('correo_empresa')),
          _Dato('Domicilio', domicilio.isEmpty ? null : domicilio, Icons.home_outlined, ancho: true),
        ]),
        seccion('Puesto y contrato', 'puesto', [
          _Dato('Puesto', e.puesto, Icons.work_outline),
          _Dato('Departamento', e.departamento, Icons.apartment),
          _Dato('Jefe directo', _nombres[e.jefeId], Icons.supervisor_account_outlined),
          _Dato('Ingreso', f('fecha_ingreso'), Icons.login),
          _Dato('Contrato', tiposContrato[e.txt('tipo_contrato')], Icons.description_outlined),
          _Dato('Fin de contrato', f('fecha_fin_contrato'), Icons.event_busy_outlined),
          _Dato('Fin del periodo de prueba', f('fin_periodo_prueba'), Icons.hourglass_bottom),
          _Dato('Jornada', jornadas[e.txt('jornada')], Icons.wb_sunny_outlined),
        ]),
        seccion('Nómina y seguridad social', 'nomina', [
          _Dato('Salario diario', m('salario_diario'), Icons.attach_money),
          _Dato('SDI', m('sdi'), Icons.functions),
          _Dato('Periodicidad', periodicidades[e.txt('periodicidad_pago')], Icons.calendar_month_outlined),
          _Dato('Forma de pago', formasPago[e.txt('forma_pago')], Icons.payments_outlined),
          _Dato('Régimen fiscal', regimenesFiscales[e.txt('regimen_fiscal')] ?? e.txt('regimen_fiscal'), Icons.account_balance_wallet_outlined),
          _Dato('CP fiscal', e.txt('cp_fiscal'), Icons.markunread_mailbox_outlined),
          _Dato('Registro patronal', e.txt('registro_patronal'), Icons.business_outlined),
          _Dato('Alta en el IMSS', f('fecha_alta_imss'), Icons.local_hospital_outlined),
          _Dato('UMF', e.txt('umf'), Icons.medical_services_outlined),
          _Dato(
            'INFONAVIT',
            e.txt('infonavit_credito') == null
                ? 'Sin crédito'
                : '${e.txt('infonavit_credito')} · ${tiposInfonavit[e.txt('infonavit_tipo')] ?? ''} ${e.txt('infonavit_valor') ?? ''}',
            Icons.house_outlined,
          ),
          _Dato('FONACOT', e.txt('fonacot_credito') ?? 'Sin crédito', Icons.credit_card_outlined),
        ]),
        seccion('Banco', 'banco', [
          _Dato('CLABE', e.txt('clabe'), Icons.account_balance_outlined, copiar: e.txt('clabe')),
          _Dato('Banco', e.txt('banco'), Icons.account_balance),
          _Dato('Cuenta', e.txt('cuenta'), Icons.numbers, copiar: e.txt('cuenta')),
        ]),
        seccion('Contactos de emergencia', 'emergencia', [
          if (emergencia.isEmpty) _Dato('Contacto', null, Icons.emergency_outlined),
          for (final p in emergencia)
            _Dato(p['parentesco']?.toString() ?? 'Contacto', '${p['nombre'] ?? ''}\n${p['telefono'] ?? ''}'.trim(),
                Icons.emergency_outlined, copiar: p['telefono']?.toString()),
        ]),
        seccion('Beneficiarios', 'beneficiarios', [
          if (benef.isEmpty) _Dato('Beneficiario', null, Icons.family_restroom),
          for (final p in benef)
            _Dato('${p['parentesco'] ?? 'Beneficiario'} · ${p['porcentaje'] ?? 0} %', p['nombre']?.toString(), Icons.family_restroom),
        ]),
        seccion('Uniforme y EPP', 'uniforme', [
          _Dato('Camisa', e.txt('talla_camisa'), Icons.checkroom_outlined),
          _Dato('Pantalón', e.txt('talla_pantalon'), Icons.checkroom_outlined),
          _Dato('Calzado', e.txt('talla_calzado'), Icons.hiking),
          if (e.txt('notas') != null) _Dato('Notas', e.txt('notas'), Icons.sticky_note_2_outlined, ancho: true),
        ]),
        if (!e.activo)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('Baja'),
              _Rejilla(children: [
                _Dato('Fecha', f('fecha_baja') ?? (e.fecha('baja_at') == null ? null : fechaCorta(e.fecha('baja_at')!)), Icons.event_outlined),
                _Dato('Tipo', tiposBaja[e.txt('tipo_baja')], Icons.logout),
                _Dato('Recontratable', e.j['recontratable'] == null ? null : (e.j['recontratable'] == true ? 'Sí' : 'No'), Icons.replay),
                _Dato('Motivo', e.txt('motivo_baja'), Icons.notes, ancho: true),
              ]),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Asistencia
  // ---------------------------------------------------------------------------

  Widget _asistencia() {
    final c = context.c;
    // Resumen de los últimos 30 días a partir de las checadas cargadas.
    final desde = DateTime.now().subtract(Duration(days: 30));
    final recientes = _checadas.where((ch) => ch.ts.isAfter(desde) && ch.estado != 'anulada').toList();
    final dias = <String>{for (final ch in recientes.where((x) => x.tipo == 'entrada')) fechaCorta(ch.ts)};
    final retardos = recientes.where((ch) => ch.tipo == 'entrada' && (ch.minutosRetardo ?? 0) > 0).toList();
    final minutos = retardos.fold<int>(0, (a, ch) => a + (ch.minutosRetardo ?? 0));
    final revisar = recientes.where((ch) => ch.estado != 'valida').length;

    return ListView(
      padding: _pad,
      children: [
        _Rejilla(children: [
          _Dato('Días con entrada (30 días)', '${dias.length}', Icons.event_available_outlined),
          _Dato('Retardos (30 días)', retardos.isEmpty ? '0' : '${retardos.length} · $minutos min', Icons.timer_outlined),
          _Dato('Por revisar', '$revisar', Icons.rule_outlined),
        ]),
        SectionTitle('Checadas (${_checadas.length})'),
        if (_checadas.isEmpty)
          Panel(child: Text('Todavía no ha checado.', style: TextStyle(color: c.muted)))
        else
          Panel(
            padding: EdgeInsets.symmetric(vertical: 4.r),
            child: Column(
              children: [
                for (final (i, ch) in _checadas.indexed) ...[
                  if (i > 0 && !_mismoDia(_checadas[i - 1].ts, ch.ts)) Divider(height: 1, color: c.border),
                  _FilaChecada(
                    ch: ch,
                    mostrarFecha: i == 0 || !_mismoDia(_checadas[i - 1].ts, ch.ts),
                    onTap: () => _revisar(ch),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Historial
  // ---------------------------------------------------------------------------

  static const _campos = {
    'alta': 'Alta',
    'puesto': 'Puesto',
    'departamento': 'Departamento',
    'sede_id': 'Sede',
    'turno_id': 'Turno',
    'jefe_id': 'Jefe directo',
    'tipo': 'Dónde checa',
    'tipo_contrato': 'Contrato',
    'fecha_fin_contrato': 'Fin de contrato',
    'salario_diario': 'Salario diario',
    'sdi': 'SDI',
    'periodicidad_pago': 'Periodicidad de pago',
    'activo': 'Estatus',
    'checa_movil': 'Checa desde celular',
  };

  String _valor(String campo, String? v) {
    if (v == null || v.isEmpty) return '—';
    return switch (campo) {
      'sede_id' => _sedes[v] ?? 'Sede',
      'turno_id' => _turnos[v]?.nombre ?? 'Turno',
      'jefe_id' => _nombres[v] ?? 'Empleado',
      'tipo' => v == 'administrativo' ? 'Kiosco + celular' : 'Kiosco',
      'tipo_contrato' => tiposContrato[v] ?? v,
      'periodicidad_pago' => periodicidades[v] ?? v,
      'activo' => v == 'true' ? 'Activo' : 'Baja',
      'checa_movil' => v == 'true' ? 'Sí' : 'No',
      'salario_diario' || 'sdi' => dineroMx(double.tryParse(v)),
      'fecha_fin_contrato' => DateTime.tryParse(v) == null ? v : fechaCorta(DateTime.parse(v)),
      _ => v,
    };
  }

  Widget _historialVista() {
    final c = context.c;
    final h = _historial;
    if (h == null) {
      return ListView(padding: _pad, children: [
        Panel(child: Text('El historial empieza a registrarse al correr 003_expediente.sql en Supabase.', style: TextStyle(color: c.muted))),
      ]);
    }
    return ListView(
      padding: _pad,
      children: [
        if (h.isEmpty) Panel(child: Text('Sin movimientos todavía.', style: TextStyle(color: c.muted))),
        for (final m in h)
          Padding(
            padding: EdgeInsets.only(bottom: 8.r),
            child: Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38.r,
                    height: 38.r,
                    decoration: BoxDecoration(color: context.scheme.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
                    child: Icon(
                      switch (m.campo) {
                        'alta' => Icons.person_add_alt_1_outlined,
                        'salario_diario' || 'sdi' => Icons.trending_up,
                        'activo' => Icons.swap_horiz,
                        _ => Icons.edit_note,
                      },
                      size: 20.r,
                      color: context.scheme.primary,
                    ),
                  ),
                  SizedBox(width: 12.r),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_campos[m.campo] ?? m.campo, style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 2.r),
                        Text(
                          m.campo == 'alta'
                              ? 'Ingresó${(m.despues ?? '').isNotEmpty ? ' como ${m.despues}' : ''}'
                              : '${_valor(m.campo, m.antes)}  →  ${_valor(m.campo, m.despues)}',
                        ),
                        SizedBox(height: 2.r),
                        Text('${fechaCorta(m.at)} · ${hhmm(m.at)}', style: TextStyle(color: c.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static bool _mismoDia(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _Metodo extends StatelessWidget {
  const _Metodo({required this.icon, required this.titulo, required this.estado, required this.ok, required this.acciones});

  final IconData icon;
  final String titulo;
  final String estado;
  final bool ok;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = ok ? c.ok : c.muted;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44.r,
                height: 44.r,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14.r)),
                child: Icon(icon, color: color),
              ),
              SizedBox(width: 12.r),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(estado, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (ok) Icon(Icons.check_circle, color: c.ok),
            ],
          ),
          if (acciones.isNotEmpty) ...[
            SizedBox(height: 12.r),
            Wrap(spacing: 8.r, runSpacing: 4.r, crossAxisAlignment: WrapCrossAlignment.center, children: acciones),
          ],
        ],
      ),
    );
  }
}

class _FilaChecada extends StatelessWidget {
  const _FilaChecada({required this.ch, required this.mostrarFecha, required this.onTap});

  final Checada ch;
  final bool mostrarFecha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entrada = ch.tipo == 'entrada';
    final (Color colorEstado, String? textoEstado) = switch (ch.estado) {
      'fuera_geocerca' => (c.danger, 'Fuera de geocerca · ${metros(ch.distanciaM)}'),
      'revisar' => (c.info, ch.gpsSimulado ? 'GPS simulado' : 'Por revisar'),
      'anulada' => (c.muted, 'Anulada'),
      _ => (c.ok, null),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14.r, 10.r, 14.r, 10.r),
        child: Row(
          children: [
            SizedBox(
              width: 64.r,
              child: mostrarFecha
                  ? Text(fechaCorta(ch.ts).replaceFirst(RegExp(r' \d{4}$'), ''),
                      style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700))
                  : null,
            ),
            Icon(entrada ? Icons.login : Icons.logout, size: 18.r, color: entrada ? c.ok : c.info),
            SizedBox(width: 8.r),
            Text(
              hhmm(ch.ts),
              style: TextStyle(
                fontFamily: AppFont.display,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                decoration: ch.estado == 'anulada' ? TextDecoration.lineThrough : null,
              ),
            ),
            SizedBox(width: 8.r),
            Icon(
              switch (ch.metodo) {
                'lector' => Icons.fingerprint,
                'rostro' || 'rostro+huella' => Icons.face,
                _ => Icons.smartphone,
              },
              size: 15.r,
              color: c.muted,
            ),
            Spacer(),
            if (textoEstado != null)
              Flexible(child: StatusChip(label: textoEstado, color: colorEstado))
            else if ((ch.minutosRetardo ?? 0) > 0)
              StatusChip(label: '+${ch.minutosRetardo} min', color: c.warn)
            else if (ch.sede != null)
              Flexible(
                child: Text(ch.sede!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rejilla de datos: 1 columna en teléfono angosto, 2 en teléfono normal,
/// 3 en tablet. Los marcados como `ancho` ocupan el renglón completo.
class _Rejilla extends StatelessWidget {
  const _Rejilla({required this.children});

  final List<_Dato> children;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: LayoutBuilder(builder: (context, cs) {
        final cols = cs.maxWidth >= 720 ? 3 : (cs.maxWidth >= 330 ? 2 : 1);
        final gap = 14.r;
        final w = (cs.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 14.r,
          children: [for (final d in children) SizedBox(width: d.ancho ? cs.maxWidth : w, child: d)],
        );
      }),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor, this.icono, {this.copiar, this.ancho = false});

  final String etiqueta;
  final String? valor;
  final IconData icono;
  final String? copiar;
  final bool ancho;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final vacio = valor == null || valor!.trim().isEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(10.r),
      onLongPress: copiar == null
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: copiar!));
              avisar(context, '$etiqueta copiado');
            },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18.r, color: c.muted),
          SizedBox(width: 8.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: TextStyle(color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                SizedBox(height: 2.r),
                Text(
                  vacio ? '—' : valor!,
                  style: TextStyle(fontWeight: FontWeight.w600, color: vacio ? c.muted : null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja para dar de baja: fecha, tipo, motivo y si es recontratable.
class _HojaBaja extends StatefulWidget {
  const _HojaBaja({required this.nombre});

  final String nombre;

  @override
  State<_HojaBaja> createState() => _HojaBajaState();
}

class _HojaBajaState extends State<_HojaBaja> {
  DateTime _fecha = DateTime.now();
  String? _tipo;
  bool _recontratable = true;
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.r, 0, 20.r, 20.r + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Dar de baja', style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 19)),
            Text(widget.nombre, style: TextStyle(color: c.muted)),
            SizedBox(height: 16.r),
            OutlinedButton.icon(
              onPressed: () async {
                final r = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(Duration(days: 60)),
                );
                if (r != null) setState(() => _fecha = r);
              },
              icon: Icon(Icons.event_outlined),
              label: Text('Último día laborado: ${fechaCorta(_fecha)}'),
            ),
            SizedBox(height: 12.r),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Tipo de baja'),
              items: [for (final t in tiposBaja.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: (v) => setState(() => _tipo = v),
            ),
            SizedBox(height: 12.r),
            TextField(
              controller: _motivo,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Motivo / comentarios'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _recontratable,
              onChanged: (v) => setState(() => _recontratable = v),
              title: Text('Recontratable'),
            ),
            Text(
              'Se borran su rostro y huellas, y se desvinculan sus equipos. Su expediente y checadas se conservan '
              '(LFT art. 804: al menos un año después de la baja). Recuerda el aviso de baja ante el IMSS (5 días hábiles).',
              style: TextStyle(color: c.muted, fontSize: 12.5),
            ),
            SizedBox(height: 16.r),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.danger),
              onPressed: _tipo == null
                  ? null
                  : () => Navigator.pop(context, (
                        fecha: _fecha,
                        tipo: _tipo!,
                        motivo: _motivo.text.trim().isEmpty ? null : _motivo.text.trim(),
                        recontratable: _recontratable,
                      )),
              icon: Icon(Icons.person_off_outlined),
              label: Text('Dar de baja'),
            ),
          ],
        ),
      ),
    );
  }
}
