import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'datos.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

/// Sedes (geocercas) y turnos: los dos catálogos que necesita el checador.
class SedesScreen extends StatefulWidget {
  const SedesScreen({super.key});

  @override
  State<SedesScreen> createState() => _SedesScreenState();
}

class _SedesScreenState extends State<SedesScreen> {
  List<Sede>? _sedes;
  List<Turno>? _turnos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait<Object>([Repo.sedes(), Repo.turnos()]);
      if (!mounted) return;
      setState(() {
        _sedes = r[0] as List<Sede>;
        _turnos = r[1] as List<Turno>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    }
  }

  Future<void> _editarSede([Sede? s]) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _SedeForm(sede: s), fullscreenDialog: true),
    );
    if (ok == true) _cargar();
  }

  Future<void> _editarTurno([Turno? t]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TurnoForm(turno: t),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sedes = _sedes;
    final turnos = _turnos;

    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: Text('Sedes y turnos')),
      body: _error != null
          ? EmptyState(
              icon: Icons.cloud_off,
              title: 'No se pudo cargar',
              message: _error,
              action: OutlinedButton(onPressed: _cargar, child: Text('Reintentar')),
            )
          : sedes == null || turnos == null
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(context.resp.margen, 0, context.resp.margen, 32.r),
                    children: [
                      SectionTitle(
                        'Sedes · geocercas',
                        trailing: TextButton.icon(
                          onPressed: _editarSede,
                          icon: Icon(Icons.add, size: 18.r),
                          label: Text('Nueva'),
                        ),
                      ),
                      if (sedes.isEmpty)
                        Panel(
                          onTap: _editarSede,
                          child: Row(
                            children: [
                              Icon(Icons.add_location_alt_outlined, color: context.scheme.primary, size: 30.r),
                              SizedBox(width: 14.r),
                              Expanded(
                                child: Text(
                                  'Da de alta la planta. Párate en la entrada con este teléfono y toca '
                                  '"Usar mi ubicación": ese punto y un radio forman la geocerca.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final s in sedes) ...[
                        Panel(
                          onTap: () => _editarSede(s),
                          child: Row(
                            children: [
                              _Radar(activa: s.activa),
                              SizedBox(width: 14.r),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.nombre, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                    if ((s.direccion ?? '').isNotEmpty)
                                      Text(s.direccion!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 12.5)),
                                    SizedBox(height: 4.r),
                                    Text(
                                      'Radio ${metros(s.radioM)} · ${s.lat.toStringAsFixed(5)}, ${s.lng.toStringAsFixed(5)}',
                                      style: TextStyle(color: c.muted, fontSize: 12),
                                    ),
                                    Text(
                                      Sede.modos[s.modo] ?? s.modo,
                                      style: TextStyle(color: context.scheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              if (!s.activa) StatusChip(label: 'Inactiva', color: c.muted),
                            ],
                          ),
                        ),
                        SizedBox(height: 10.r),
                      ],
                      SectionTitle(
                        'Turnos',
                        trailing: TextButton.icon(
                          onPressed: _editarTurno,
                          icon: Icon(Icons.add, size: 18.r),
                          label: Text('Nuevo'),
                        ),
                      ),
                      if (turnos.isEmpty)
                        Panel(
                          onTap: _editarTurno,
                          child: Text(
                            'Sin turnos no se calculan retardos. Crea al menos uno (p. ej. Matutino 07:00–17:00, tolerancia 10 min).',
                            style: TextStyle(color: c.muted),
                          ),
                        ),
                      for (final t in turnos) ...[
                        Panel(
                          onTap: () => _editarTurno(t),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${t.entrada} – ${t.salida}',
                                    style: TextStyle(
                                      fontFamily: AppFont.display,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                      color: t.activo ? null : c.muted,
                                    ),
                                  ),
                                  Text('${t.nombre} · ${t.diasTexto}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                                ],
                              ),
                              Spacer(),
                              StatusChip(label: '±${t.tolerancia} min', color: c.warn, icon: Icons.timer_outlined),
                            ],
                          ),
                        ),
                        SizedBox(height: 10.r),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _Radar extends StatelessWidget {
  const _Radar({required this.activa});

  final bool activa;

  @override
  Widget build(BuildContext context) {
    final color = activa ? context.scheme.primary : context.c.muted;
    return Container(
      width: 52.r,
      height: 52.r,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.08)),
      child: Center(
        child: Container(
          width: 32.r,
          height: 32.r,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.16)),
          child: Icon(Icons.location_on, size: 20.r, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sede
// ---------------------------------------------------------------------------

class _SedeForm extends StatefulWidget {
  const _SedeForm({this.sede});

  final Sede? sede;

  @override
  State<_SedeForm> createState() => _SedeFormState();
}

class _SedeFormState extends State<_SedeForm> {
  late final _nombre = TextEditingController(text: widget.sede?.nombre);
  late final _dir = TextEditingController(text: widget.sede?.direccion);
  late final _lat = TextEditingController(text: widget.sede?.lat.toStringAsFixed(6));
  late final _lng = TextEditingController(text: widget.sede?.lng.toStringAsFixed(6));
  late double _radio = (widget.sede?.radioM ?? 150).toDouble();
  late bool _activa = widget.sede?.activa ?? true;
  late String _modo = widget.sede?.modo ?? 'respaldo';
  late double _umbral = widget.sede?.umbral ?? 0.85;
  bool _ubicando = false;
  bool _guardando = false;
  double? _precision;

  @override
  void dispose() {
    for (final c in [_nombre, _dir, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _miUbicacion() async {
    setState(() => _ubicando = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Activa la ubicación (GPS) del teléfono.');
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        throw Exception('Sin permiso de ubicación. Actívalo en Ajustes › Arypsa RH.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 25),
        ),
      );
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lng.text = pos.longitude.toStringAsFixed(6);
        _precision = pos.accuracy;
      });
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  Future<void> _guardar() async {
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    if (_nombre.text.trim().isEmpty) {
      avisar(context, 'Ponle nombre a la sede.', error: true);
      return;
    }
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      avisar(context, 'Falta la ubicación. Toca "Usar mi ubicación" o pega las coordenadas.', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      await Repo.guardarSede(
        widget.sede?.id,
        Sede(
          nombre: _nombre.text.trim(),
          direccion: _dir.text.trim().isEmpty ? null : _dir.text.trim(),
          lat: lat,
          lng: lng,
          radioM: _radio.round(),
          activa: _activa,
          modo: _modo,
          umbral: double.parse(_umbral.toStringAsFixed(2)),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Acepta lo que se copia de Google Maps: "21.123456, -101.654321".
  Future<void> _pegar() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final m = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)').firstMatch(d?.text ?? '');
    if (m == null) {
      if (mounted) avisar(context, 'En el portapapeles no hay coordenadas tipo "21.12, -101.65".', error: true);
      return;
    }
    setState(() {
      _lat.text = m.group(1)!;
      _lng.text = m.group(2)!;
      _precision = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sede == null ? 'Nueva sede' : 'Editar sede'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12.r),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: Size(96.r, 40.r)),
              onPressed: _guardando ? null : _guardar,
              child: Text('Guardar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(context.resp.margen, 8.r, context.resp.margen, 32.r),
        children: [
          Panel(
            child: Column(
              children: [
                TextField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: 'Nombre', hintText: 'Planta León'),
                ),
                SizedBox(height: 12.r),
                TextField(
                  controller: _dir,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: 'Dirección (opcional)'),
                ),
              ],
            ),
          ),
          SectionTitle('Centro de la geocerca'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _ubicando ? null : _miUbicacion,
                  icon: _ubicando
                      ? SizedBox(width: 18.r, height: 18.r, child: CircularProgressIndicator(strokeWidth: 2.r))
                      : Icon(Icons.my_location),
                  label: Text(_ubicando ? 'Buscando satélites…' : 'Usar mi ubicación'),
                ),
                if (_precision != null) ...[
                  SizedBox(height: 8.r),
                  StatusChip(
                    label: 'Precisión ±${metros(_precision)}${_precision! > 30 ? ' · sal al aire libre y repite' : ''}',
                    color: _precision! > 30 ? c.warn : c.ok,
                    icon: Icons.gps_fixed,
                  ),
                ],
                SizedBox(height: 14.r),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lat,
                        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(labelText: 'Latitud'),
                      ),
                    ),
                    SizedBox(width: 10.r),
                    Expanded(
                      child: TextField(
                        controller: _lng,
                        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(labelText: 'Longitud'),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pegar,
                    icon: Icon(Icons.content_paste, size: 18.r),
                    label: Text('Pegar coordenadas de Google Maps'),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle('Radio permitido'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      metros(_radio),
                      style: TextStyle(fontFamily: AppFont.display, fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(width: 10.r),
                    Expanded(
                      child: Text(
                        'alrededor del centro',
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _radio.clamp(30.0, 1000.0),
                  min: 30,
                  max: 1000,
                  divisions: 97,
                  label: metros(_radio),
                  onChanged: (v) => setState(() => _radio = (v / 10).round() * 10.0),
                ),
                Text(
                  'Cubre todo el terreno (estacionamiento incluido) con un poco de margen. '
                  'Un celular adentro de una nave puede marcar 20–50 m de error; el servidor perdona hasta 50 m de imprecisión.',
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          SectionTitle('Cómo se checa en el kiosco'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in Sede.modos.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => setState(() => _modo = m.key),
                    leading: Icon(
                      _modo == m.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _modo == m.key ? context.scheme.primary : c.muted,
                    ),
                    title: Text(m.value, style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      switch (m.key) {
                        'cualquiera' => 'Lo que pase primero. La fila avanza más rápido.',
                        'respaldo' => 'La cámara reconoce; si no puede (cubrebocas, casco, poca luz), se usa el dedo.',
                        _ => 'Cara y dedo de la misma persona. Nadie checa por otro.',
                      },
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  ),
                Divider(height: 24.r),
                Text('Exigencia del reconocimiento facial', style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
                Slider(
                  value: _umbral.clamp(0.6, 1.1),
                  min: 0.6,
                  max: 1.1,
                  divisions: 10,
                  label: _umbral <= 0.75 ? 'Estricto' : (_umbral >= 0.95 ? 'Flexible' : 'Normal'),
                  onChanged: (v) => setState(() => _umbral = v),
                ),
                Text(
                  'Estricto: casi nunca confunde a dos personas, pero a veces pide la huella. '
                  'Flexible: reconoce más rápido, con más riesgo de confusión. Normal es 0.85.',
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.r),
          Panel(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _activa,
              onChanged: (v) => setState(() => _activa = v),
              title: Text('Sede activa', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Si se apaga, ya no cuenta como lugar válido para checar.', style: TextStyle(color: c.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Turno
// ---------------------------------------------------------------------------

class _TurnoForm extends StatefulWidget {
  const _TurnoForm({this.turno});

  final Turno? turno;

  @override
  State<_TurnoForm> createState() => _TurnoFormState();
}

class _TurnoFormState extends State<_TurnoForm> {
  late final _nombre = TextEditingController(text: widget.turno?.nombre);
  late String _entrada = widget.turno?.entrada ?? '07:00';
  late String _salida = widget.turno?.salida ?? '17:00';
  late double _tol = (widget.turno?.tolerancia ?? 10).toDouble();
  late final Set<int> _dias = {...(widget.turno?.dias ?? [1, 2, 3, 4, 5])};
  late bool _activo = widget.turno?.activo ?? true;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _hora(bool entrada) async {
    final actual = (entrada ? _entrada : _salida).split(':');
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(actual[0]), minute: int.parse(actual[1])),
    );
    if (r == null) return;
    final s = '${dos(r.hour)}:${dos(r.minute)}';
    setState(() {
      if (entrada) {
        _entrada = s;
      } else {
        _salida = s;
      }
    });
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty || _dias.isEmpty) {
      avisar(context, 'Falta el nombre o los días.', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      await Repo.guardarTurno(
        widget.turno?.id,
        Turno(
          nombre: _nombre.text.trim(),
          entrada: _entrada,
          salida: _salida,
          tolerancia: _tol.round(),
          dias: (_dias.toList()..sort()),
          activo: _activo,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const letras = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    Widget hora(String label, String valor, bool entrada) => Expanded(
          child: Panel(
            color: c.field,
            onTap: () => _hora(entrada),
            child: Column(
              children: [
                Text(label, style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                SizedBox(height: 4.r),
                Text(valor, style: TextStyle(fontFamily: AppFont.display, fontSize: 28, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(context.resp.margen, 0, context.resp.margen, 20.r + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.turno == null ? 'Nuevo turno' : 'Editar turno',
              style: TextStyle(fontFamily: AppFont.display, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 14.r),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Nombre', hintText: 'Matutino'),
            ),
            SizedBox(height: 12.r),
            Row(children: [hora('Entrada', _entrada, true), SizedBox(width: 10.r), hora('Salida', _salida, false)]),
            SizedBox(height: 16.r),
            Text('Tolerancia: ${_tol.round()} min', style: TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: _tol,
              min: 0,
              max: 60,
              divisions: 12,
              label: '${_tol.round()} min',
              onChanged: (v) => setState(() => _tol = v),
            ),
            SizedBox(height: 4.r),
            Text('Días que se labora', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8.r),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  _DiaChip(
                    letra: letras[d - 1],
                    activo: _dias.contains(d),
                    onTap: () => setState(() => _dias.contains(d) ? _dias.remove(d) : _dias.add(d)),
                  ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
              title: Text('Turno activo'),
            ),
            SizedBox(height: 8.r),
            FilledButton(onPressed: _guardando ? null : _guardar, child: Text('Guardar turno')),
          ],
        ),
      ),
    );
  }
}

class _DiaChip extends StatelessWidget {
  const _DiaChip({required this.letra, required this.activo, required this.onTap});

  final String letra;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.scheme.primary;
    return InkWell(
      onTap: onTap,
      customBorder: CircleBorder(),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        width: 40.r,
        height: 40.r,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activo ? p : context.c.field,
        ),
        child: Text(
          letra,
          style: TextStyle(fontWeight: FontWeight.w800, color: activo ? Colors.white : context.c.muted),
        ),
      ),
    );
  }
}
