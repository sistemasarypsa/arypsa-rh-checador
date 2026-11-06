import 'package:flutter/material.dart';

import 'datos.dart';
import 'empleado_detalle.dart';
import 'empleado_form.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

class EmpleadosScreen extends StatefulWidget {
  const EmpleadosScreen({super.key});

  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen> {
  final _buscar = TextEditingController();
  List<Empleado>? _lista;
  String? _error;
  bool _bajas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _buscar.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final r = await Repo.empleados(activos: !_bajas);
      if (mounted) setState(() => _lista = r);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    }
  }

  List<Empleado> get _filtrados {
    final q = _quitarAcentos(_buscar.text.trim().toLowerCase());
    final l = _lista ?? <Empleado>[];
    if (q.isEmpty) return l;
    return l.where((e) {
      final t = _quitarAcentos([
        e.numero, e.nombre, e.puesto, e.departamento, e.txt('curp'), e.txt('rfc'), e.txt('nss'), e.telefono,
      ].whereType<String>().join(' ').toLowerCase());
      return q.split(' ').every(t.contains);
    }).toList();
  }

  static String _quitarAcentos(String s) => s
      .replaceAll(RegExp('[áä]'), 'a')
      .replaceAll(RegExp('[éë]'), 'e')
      .replaceAll(RegExp('[íï]'), 'i')
      .replaceAll(RegExp('[óö]'), 'o')
      .replaceAll(RegExp('[úü]'), 'u');

  Future<void> _abrir(Empleado e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmpleadoDetalle(empleadoId: e.id!)));
    _cargar();
  }

  Future<void> _nuevo() async {
    final creado = await Navigator.of(context).push<Empleado>(
      MaterialPageRoute(builder: (_) => EmpleadoForm(), fullscreenDialog: true),
    );
    if (creado == null || !mounted) return;
    await _cargar();
    if (!mounted) return;
    // Recién dado de alta: directo a su ficha para registrar la huella.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EmpleadoDetalle(empleadoId: creado.id!, recienCreado: true)),
    );
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lista = _lista;
    final f = _filtrados;
    final sinHuella = (lista ?? <Empleado>[]).where((e) => !e.biometriaKiosco).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('Personal'),
        actions: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text('Activos')),
              ButtonSegment(value: true, label: Text('Bajas')),
            ],
            selected: {_bajas},
            onSelectionChanged: (s) {
              setState(() {
                _bajas = s.first;
                _lista = null;
              });
              _cargar();
            },
          ),
          SizedBox(width: 12.r),
        ],
      ),
      floatingActionButton: _bajas
          ? null
          : FloatingActionButton.extended(
              onPressed: _nuevo,
              icon: Icon(Icons.person_add_alt_1),
              label: Text('Alta'),
            ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(context.resp.margen, 4.r, context.resp.margen, 8.r),
            child: TextField(
              controller: _buscar,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, número, puesto, CURP o NSS',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _buscar.text.isEmpty
                    ? null
                    : IconButton(onPressed: _buscar.clear, icon: Icon(Icons.close)),
              ),
            ),
          ),
          if (!_bajas && sinHuella > 0 && _buscar.text.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(context.resp.margen, 0, context.resp.margen, 8.r),
              child: StatusChip(
                label: '$sinHuella sin rostro ni huella registrados',
                color: c.warn,
                icon: Icons.face_retouching_natural,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _cargar,
              child: _error != null
                  ? ListView(children: [
                      SizedBox(height: 60.r),
                      EmptyState(
                        icon: Icons.cloud_off,
                        title: 'No se pudo cargar',
                        message: _error,
                        action: OutlinedButton(onPressed: _cargar, child: Text('Reintentar')),
                      ),
                    ])
                  : lista == null
                      ? Center(child: CircularProgressIndicator())
                      : f.isEmpty
                          ? ListView(children: [
                              SizedBox(height: 60.r),
                              EmptyState(
                                icon: _bajas ? Icons.person_off_outlined : Icons.badge_outlined,
                                title: lista.isEmpty
                                    ? (_bajas ? 'No hay bajas' : 'Da de alta al primer empleado')
                                    : 'Sin resultados',
                                message: lista.isEmpty && !_bajas
                                    ? 'Captura sus datos y su foto; el rostro y la huella se registran después en el kiosco.'
                                    : null,
                              ),
                            ])
                          : context.resp.columnas == 1
                              ? ListView.separated(
                                  padding: EdgeInsets.fromLTRB(context.resp.margen, 4.r, context.resp.margen, 96.r),
                                  itemCount: f.length,
                                  separatorBuilder: (_, _) => SizedBox(height: 8.r),
                                  itemBuilder: (_, i) => _Tarjeta(e: f[i], onTap: () => _abrir(f[i])),
                                )
                              // Tablet: tarjetas en 2–3 columnas.
                              : GridView.builder(
                                  padding: EdgeInsets.fromLTRB(16.r, 4.r, 16.r, 96.r),
                                  itemCount: f.length,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: context.resp.columnas,
                                    mainAxisExtent: 74.r,
                                    crossAxisSpacing: 10.r,
                                    mainAxisSpacing: 10.r,
                                  ),
                                  itemBuilder: (_, i) => _Tarjeta(e: f[i], onTap: () => _abrir(f[i])),
                                ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.e, required this.onTap});

  final Empleado e;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Panel(
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(12.r, 10.r, 14.r, 10.r),
      child: Row(
        children: [
          Avatar(nombre: e.nombre, foto: e.foto, size: 50.r),
          SizedBox(width: 12.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 2),
                Text(
                  ['#${e.numero}', if ((e.puesto ?? '').isNotEmpty) e.puesto!].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.r),
          _Indicador(
            icon: Icons.face,
            ok: e.rostros > 0,
            tooltip: e.rostros > 0 ? 'Rostro registrado' : 'Sin rostro',
          ),
          SizedBox(width: 6.r),
          _Indicador(
            icon: Icons.fingerprint,
            ok: e.huellas > 0,
            tooltip: e.huellas > 0 ? 'Huella registrada' : 'Sin huella',
          ),
          if (e.checaMovil) ...[
            SizedBox(width: 6.r),
            _Indicador(
              icon: Icons.smartphone,
              ok: e.movilVinculado,
              tooltip: e.movilVinculado ? 'Celular vinculado' : 'Celular sin vincular',
            ),
          ],
        ],
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.icon, required this.ok, required this.tooltip});

  final IconData icon;
  final bool ok;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final color = ok ? context.c.ok : context.c.muted.withValues(alpha: 0.55);
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 34.r,
        height: 34.r,
        decoration: BoxDecoration(
          color: color.withValues(alpha: ok ? 0.14 : 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19.r, color: color),
      ),
    );
  }
}
