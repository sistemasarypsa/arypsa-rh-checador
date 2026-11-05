import 'package:flutter/material.dart';

import 'codigo_sheet.dart';
import 'datos.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

/// Kioscos y celulares que pueden checar. Aquí se da de alta un kiosco nuevo
/// y se corta cualquier equipo perdido o robado.
class EquiposScreen extends StatefulWidget {
  const EquiposScreen({super.key});

  @override
  State<EquiposScreen> createState() => _EquiposScreenState();
}

class _EquiposScreenState extends State<EquiposScreen> {
  List<Equipo>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Repo.equipos();
      if (mounted) {
        setState(() {
          _lista = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    }
  }

  Future<void> _nuevoKiosco() async {
    List<Sede> sedes;
    try {
      sedes = (await Repo.sedes()).where((s) => s.activa).toList();
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
      return;
    }
    if (!mounted) return;
    if (sedes.isEmpty) {
      avisar(context, 'Primero da de alta una sede.', error: true);
      return;
    }
    final datos = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NuevoKiosco(sedes: sedes),
    );
    if (datos == null || !mounted) return;
    try {
      final k = await Repo.generarCodigo('kiosco', sede: datos.$1, nombre: datos.$2);
      if (!mounted) return;
      await mostrarCodigo(
        context,
        codigo: k,
        titulo: 'Activar kiosco',
        para: datos.$2,
        pasos: [
          'En la tablet o handheld, instala y abre "Arypsa Checador".',
          'Elige "Kiosco de la empresa" y escanea este QR (o teclea el código).',
          'Conecta el lector de huella por USB-OTG y acepta el permiso que pide Android.',
          'Deja la tablet en su base, conectada a la corriente.',
        ],
      );
      _cargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    }
  }

  Future<void> _desactivar(Equipo e) async {
    if (!await confirmar(
      context,
      titulo: 'Dar de baja el equipo',
      mensaje: '"${e.nombre}" dejará de poder checar de inmediato. Para volver a usarlo hay que activarlo con un código nuevo.',
      si: 'Dar de baja',
      peligro: true,
    )) {
      return;
    }
    try {
      await Repo.desactivarEquipo(e.id);
      _cargar();
    } catch (err) {
      if (mounted) avisar(context, mensajeError(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    final activos = lista?.where((e) => e.activo).toList() ?? <Equipo>[];
    final inactivos = lista?.where((e) => !e.activo).toList() ?? <Equipo>[];

    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: Text('Equipos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoKiosco,
        icon: Icon(Icons.tablet_android),
        label: Text('Nuevo kiosco'),
      ),
      body: _error != null
          ? EmptyState(
              icon: Icons.cloud_off,
              title: 'No se pudo cargar',
              message: _error,
              action: OutlinedButton(onPressed: _cargar, child: Text('Reintentar')),
            )
          : lista == null
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: lista.isEmpty
                      ? ListView(children: [
                          SizedBox(height: 60.r),
                          EmptyState(
                            icon: Icons.devices_other,
                            title: 'Sin equipos todavía',
                            message: 'Activa el primer kiosco con el botón de abajo. '
                                'Los celulares se vinculan desde la ficha de cada empleado.',
                          ),
                        ])
                      : ListView(
                          padding: EdgeInsets.fromLTRB(context.resp.margen, 0, context.resp.margen, 96.r),
                          children: [
                            SectionTitle('Activos (${activos.length})'),
                            for (final e in activos) ...[
                              _TarjetaEquipo(e: e, onBaja: () => _desactivar(e)),
                              SizedBox(height: 8.r),
                            ],
                            if (inactivos.isNotEmpty) ...[
                              SectionTitle('Dados de baja (${inactivos.length})'),
                              for (final e in inactivos) ...[
                                _TarjetaEquipo(e: e),
                                SizedBox(height: 8.r),
                              ],
                            ],
                          ],
                        ),
                ),
    );
  }
}

class _TarjetaEquipo extends StatelessWidget {
  const _TarjetaEquipo({required this.e, this.onBaja});

  final Equipo e;
  final VoidCallback? onBaja;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ult = e.ultimoContacto;
    // Un kiosco sincroniza cada 5 min: si lleva más de 30 sin aparecer, algo pasa.
    final dormido = e.activo && e.esKiosco && (ult == null || DateTime.now().difference(ult.toLocal()).inMinutes > 30);
    final color = !e.activo ? c.muted : (dormido ? c.warn : c.ok);

    return Panel(
      padding: EdgeInsets.fromLTRB(14.r, 12.r, 6.r, 12.r),
      child: Row(
        children: [
          Container(
            width: 46.r,
            height: 46.r,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14.r)),
            child: Icon(e.esKiosco ? Icons.tablet_android : Icons.smartphone, color: color),
          ),
          SizedBox(width: 12.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    e.esKiosco ? 'Kiosco · ${e.sede ?? ''}' : 'Celular · ${e.empleado ?? ''}',
                    if (e.modelo != null) e.modelo!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
                SizedBox(height: 4.r),
                Row(
                  children: [
                    Container(width: 7.r, height: 7.r, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    SizedBox(width: 6.r),
                    Text(
                      e.activo ? 'Visto ${haceCuanto(ult)}' : 'Dado de baja',
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onBaja != null)
            IconButton(
              tooltip: 'Dar de baja',
              onPressed: onBaja,
              icon: Icon(Icons.link_off, color: c.danger),
            ),
        ],
      ),
    );
  }
}

class _NuevoKiosco extends StatefulWidget {
  const _NuevoKiosco({required this.sedes});

  final List<Sede> sedes;

  @override
  State<_NuevoKiosco> createState() => _NuevoKioscoState();
}

class _NuevoKioscoState extends State<_NuevoKiosco> {
  late String _sede = widget.sedes.first.id!;
  final _nombre = TextEditingController(text: 'Kiosco entrada');

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.resp.margen, 0, context.resp.margen, 20.r + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nuevo kiosco', style: TextStyle(fontFamily: AppFont.display, fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 14.r),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Nombre del equipo', hintText: 'Kiosco entrada principal'),
          ),
          SizedBox(height: 12.r),
          DropdownButtonFormField<String>(
            initialValue: _sede,
            decoration: InputDecoration(labelText: 'Sede donde se instala'),
            items: [for (final s in widget.sedes) DropdownMenuItem(value: s.id, child: Text(s.nombre))],
            onChanged: (v) => setState(() => _sede = v ?? _sede),
          ),
          SizedBox(height: 18.r),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, (_sede, _nombre.text.trim().isEmpty ? 'Kiosco' : _nombre.text.trim())),
            icon: Icon(Icons.qr_code_2),
            label: Text('Generar código de activación'),
          ),
        ],
      ),
    );
  }
}
