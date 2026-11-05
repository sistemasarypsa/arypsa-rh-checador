import 'dart:async';

import 'package:flutter/material.dart';

import 'alertas_rh.dart';
import 'datos.dart';
import 'empleado_detalle.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

enum _Filtro { todos, presentes, retardos, faltan, alertas }

class HoyScreen extends StatefulWidget {
  const HoyScreen({super.key});

  @override
  State<HoyScreen> createState() => _HoyScreenState();
}

class _HoyScreenState extends State<HoyScreen> {
  DateTime _dia = DateTime.now();
  List<ResumenDia>? _filas;
  String? _error;
  _Filtro _filtro = _Filtro.todos;
  Timer? _auto;
  final _alertas = GlobalKey<AlertasRhState>();

  bool get _esHoy {
    final n = DateTime.now();
    return _dia.year == n.year && _dia.month == n.month && _dia.day == n.day;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    // El tablero de hoy se refresca solo cada minuto.
    _auto = Timer.periodic(Duration(minutes: 1), (_) {
      if (_esHoy && mounted) _cargar(silencioso: true);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _error = null);
    try {
      final r = await Repo.resumenDia(_dia);
      if (mounted) setState(() => _filas = r);
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = mensajeError(e));
    }
  }

  void _moverDia(int delta) {
    final nuevo = _dia.add(Duration(days: delta));
    if (nuevo.isAfter(DateTime.now())) return;
    setState(() {
      _dia = nuevo;
      _filas = null;
    });
    _cargar();
  }

  Future<void> _elegirDia() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2026),
      lastDate: DateTime.now(),
    );
    if (r == null) return;
    setState(() {
      _dia = r;
      _filas = null;
    });
    _cargar();
  }

  List<ResumenDia> get _visibles {
    final f = _filas ?? <ResumenDia>[];
    return switch (_filtro) {
      _Filtro.todos => f,
      _Filtro.presentes => f.where((r) => r.presente).toList(),
      _Filtro.retardos => f.where((r) => r.retardo).toList(),
      _Filtro.faltan => f.where((r) => r.falta).toList(),
      _Filtro.alertas => f.where((r) => r.alertas > 0).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: BrandLogo(height: 24.r),
        actions: [
          ThemeToggleButton(),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'salir' &&
                  await confirmar(context, titulo: 'Cerrar sesión', mensaje: '¿Salir de la app de RH?', si: 'Salir')) {
                await sb.auth.signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(sb.auth.currentUser?.email ?? '', style: TextStyle(fontSize: 13)),
              ),
              PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
          SizedBox(width: 6.r),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_cargar(), if (_alertas.currentState != null) _alertas.currentState!.recargar()]);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.resp.margen, 4.r, context.resp.margen, 24.r),
          children: [
            // Selector de día
            Row(
              children: [
                IconButton.filledTonal(onPressed: () => _moverDia(-1), icon: Icon(Icons.chevron_left)),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.field.r),
                    onTap: _elegirDia,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.r),
                      child: Column(
                        children: [
                          Text(
                            _esHoy ? 'Hoy' : fechaCorta(_dia),
                            style: TextStyle(
                              fontFamily: AppFont.display,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(fechaLarga(_dia), style: TextStyle(color: c.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _esHoy ? null : () => _moverDia(1),
                  icon: Icon(Icons.chevron_right),
                ),
              ],
            ),
            SizedBox(height: 14.r),
            if (_error != null)
              Panel(
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, color: c.danger),
                    SizedBox(width: 12.r),
                    Expanded(child: Text(_error!)),
                    TextButton(onPressed: _cargar, child: Text('Reintentar')),
                  ],
                ),
              )
            else if (filas == null)
              Padding(
                padding: EdgeInsets.only(top: 80.r),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _Kpis(
                filas: filas,
                filtro: _filtro,
                onFiltro: (f) => setState(() => _filtro = _filtro == f ? _Filtro.todos : f),
              ),
              if (_esHoy) AlertasRh(key: _alertas),
              SectionTitle(
                switch (_filtro) {
                  _Filtro.todos => 'Personal (${filas.length})',
                  _Filtro.presentes => 'Presentes',
                  _Filtro.retardos => 'Con retardo',
                  _Filtro.faltan => 'Sin checar',
                  _Filtro.alertas => 'Con alertas por revisar',
                },
                trailing: _filtro == _Filtro.todos
                    ? null
                    : TextButton(
                        onPressed: () => setState(() => _filtro = _Filtro.todos),
                        child: Text('Ver todos'),
                      ),
              ),
              if (filas.isEmpty)
                EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'Aún no hay personal',
                  message: 'Da de alta empleados en la pestaña Personal.',
                )
              else if (_visibles.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24.r),
                  child: Center(child: Text('Nadie en este filtro.', style: TextStyle(color: c.muted))),
                )
              else
                Panel(
                  padding: EdgeInsets.symmetric(vertical: 6.r),
                  child: Column(
                    children: [
                      for (final (i, r) in _visibles.indexed) ...[
                        if (i > 0) Divider(height: 1, indent: 72.r, color: c.border),
                        _FilaDia(
                          r: r,
                          esHoy: _esHoy,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => EmpleadoDetalle(empleadoId: r.empleadoId)),
                            );
                            _cargar(silencioso: true);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.filas, required this.filtro, required this.onFiltro});

  final List<ResumenDia> filas;
  final _Filtro filtro;
  final ValueChanged<_Filtro> onFiltro;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final laboran = filas.where((r) => r.laboraHoy).length;
    final presentes = filas.where((r) => r.presente).length;
    final pct = laboran == 0 ? 0.0 : presentes / laboran;

    Widget tile(_Filtro f, String label, int n, Color color, IconData icon) {
      final activo = filtro == f;
      return Expanded(
        child: Panel(
          padding: EdgeInsets.fromLTRB(12.r, 12.r, 12.r, 12.r),
          color: activo ? color.withValues(alpha: context.isDark ? 0.22 : 0.10) : null,
          onTap: () => onFiltro(f),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18.r, color: color),
              SizedBox(height: 8.r),
              Text(
                '$n',
                style: TextStyle(
                  fontFamily: AppFont.display,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: n == 0 ? c.muted : null,
                ),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Panel(
          onTap: () => onFiltro(_Filtro.presentes),
          child: Row(
            children: [
              SizedBox(
                width: 64.r,
                height: 64.r,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: pct,
                      strokeWidth: 7.r,
                      strokeCap: StrokeCap.round,
                      backgroundColor: c.field,
                      color: c.ok,
                    ),
                    Center(
                      child: Text(
                        '${(pct * 100).round()}%',
                        style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16.r),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$presentes',
                            style: TextStyle(fontFamily: AppFont.display, fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: ' de $laboran', style: TextStyle(fontSize: 16, color: c.muted)),
                        ],
                      ),
                    ),
                    Text('checaron entrada', style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10.r),
        Row(
          children: [
            tile(_Filtro.retardos, 'Retardos', filas.where((r) => r.retardo).length, c.warn, Icons.schedule),
            SizedBox(width: 10.r),
            tile(_Filtro.faltan, 'Sin checar', filas.where((r) => r.falta).length, c.danger, Icons.person_off_outlined),
            SizedBox(width: 10.r),
            tile(_Filtro.alertas, 'Alertas', filas.where((r) => r.alertas > 0).length, c.info, Icons.gpp_maybe_outlined),
          ],
        ),
      ],
    );
  }
}

class _FilaDia extends StatelessWidget {
  const _FilaDia({required this.r, required this.esHoy, required this.onTap});

  final ResumenDia r;
  final bool esHoy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final Color anillo;
    if (r.retardo) {
      anillo = c.warn;
    } else if (r.presente) {
      anillo = c.ok;
    } else if (r.falta) {
      anillo = c.danger.withValues(alpha: esHoy ? 0.35 : 1);
    } else {
      anillo = c.border;
    }

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: 14.r, vertical: 2.r),
      leading: Avatar(nombre: r.nombre, foto: r.foto, size: 46.r, ring: anillo),
      title: Text(r.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [
          '#${r.numero}',
          if (r.puesto != null && r.puesto!.isNotEmpty) r.puesto!,
          if (r.tipo == 'administrativo') 'celular',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.muted, fontSize: 12.5),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (r.presente)
            Text(
              '${hhmm(r.entrada!)}  →  ${r.salida != null ? hhmm(r.salida!) : '··:··'}',
              style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w700, fontSize: 14),
            )
          else
            Text(
              r.laboraHoy ? 'Sin entrada' : 'Descanso',
              style: TextStyle(color: r.laboraHoy ? c.danger : c.muted, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          if (r.retardo || r.alertas > 0) SizedBox(height: 3.r),
          if (r.retardo)
            Text('+${r.minutosRetardo} min', style: TextStyle(color: c.warn, fontWeight: FontWeight.w700, fontSize: 12))
          else if (r.alertas > 0)
            Text('${r.alertas} por revisar', style: TextStyle(color: c.info, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}
