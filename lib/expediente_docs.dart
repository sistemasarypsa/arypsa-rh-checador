import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'datos.dart';
import 'responsive.dart';
import 'theme.dart';
import 'ui.dart';

/// Colores e iconos de cada estado de un documento.
(Color, IconData, String) estiloDoc(BuildContext context, EstadoDoc e) {
  final c = context.c;
  return switch (e) {
    EstadoDoc.ok => (c.ok, Icons.check_circle, 'Entregado'),
    EstadoDoc.falta => (c.danger, Icons.error_outline, 'Falta'),
    EstadoDoc.vencido => (c.danger, Icons.event_busy, 'Vencido'),
    EstadoDoc.vencePronto => (c.warn, Icons.schedule, 'Vence pronto'),
    EstadoDoc.opcional => (c.muted, Icons.radio_button_unchecked, 'Opcional'),
  };
}

/// Pestaña "Expediente" de la ficha: checklist de documentos, subir con la
/// cámara o un PDF, ver, y vencimientos.
class ExpedienteDocs extends StatefulWidget {
  const ExpedienteDocs({required this.empleado, this.onCambio, super.key});

  final Empleado empleado;
  final VoidCallback? onCambio;

  @override
  State<ExpedienteDocs> createState() => _ExpedienteDocsState();
}

class _ExpedienteDocsState extends State<ExpedienteDocs> {
  List<TipoDocumento>? _tipos;
  List<Documento> _docs = const [];
  String? _error;
  bool _subiendo = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait<Object>([Repo.tiposDocumento(), Repo.documentosDe(widget.empleado.id!)]);
      if (!mounted) return;
      setState(() {
        _tipos = r[0] as List<TipoDocumento>;
        _docs = r[1] as List<Documento>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Subir
  // ---------------------------------------------------------------------------

  Future<void> _subir(TipoDocumento t) async {
    final fuente = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.r, 4.r, 20.r, 8.r),
              child: Text(t.nombre, style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            ListTile(
              leading: Icon(Icons.document_scanner_outlined),
              title: Text('Tomar foto del documento'),
              subtitle: Text('Sobre una mesa, con buena luz y sin sombras'),
              onTap: () => Navigator.pop(ctx, 'camara'),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Elegir foto de la galería'),
              onTap: () => Navigator.pop(ctx, 'galeria'),
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined),
              title: Text('Elegir archivo (PDF o imagen)'),
              onTap: () => Navigator.pop(ctx, 'archivo'),
            ),
            SizedBox(height: 8.r),
          ],
        ),
      ),
    );
    if (fuente == null || !mounted) return;

    Uint8List? bytes;
    String? nombre;
    String? mime;
    try {
      if (fuente == 'archivo') {
        final r = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
          withData: true,
        );
        final f = r?.files.single;
        if (f == null || f.bytes == null) return;
        bytes = f.bytes!;
        nombre = f.name;
        mime = _mimeDe(f.name);
      } else {
        final x = await ImagePicker().pickImage(
          source: fuente == 'camara' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2200,
          maxHeight: 2200,
          imageQuality: 82,
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        nombre = '${t.id}.jpg';
        mime = 'image/jpeg';
      }
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo abrir: ${mensajeError(e)}', error: true);
      return;
    }
    if (!mounted) return;
    if (bytes.length > 15 * 1024 * 1024) {
      avisar(context, 'El archivo pesa más de 15 MB.', error: true);
      return;
    }

    // Datos del documento: vencimiento y fecha de emisión cuando aplica.
    final datos = await _pedirDatos(t);
    if (datos == null || !mounted) return;

    setState(() => _subiendo = true);
    try {
      await Repo.subirDocumento(
        empleadoId: widget.empleado.id!,
        tipoId: t.id,
        bytes: bytes,
        nombre: nombre,
        mime: mime,
        vence: datos.vence,
        fechaDocumento: datos.fecha,
        notas: datos.notas,
      );
      await _cargar();
      widget.onCambio?.call();
      if (mounted) avisar(context, '${t.nombre}: guardado en el expediente');
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  static String _mimeDe(String nombre) {
    final n = nombre.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<({DateTime? vence, DateTime? fecha, String? notas})?> _pedirDatos(TipoDocumento t) async {
    DateTime? vence;
    DateTime? fecha;
    final notas = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> elegir(bool esVence) async {
            final r = await showDatePicker(
              context: ctx,
              initialDate: DateTime.now(),
              firstDate: DateTime(1990),
              lastDate: DateTime.now().add(Duration(days: 3650 * 2)),
            );
            if (r == null) return;
            set(() {
              if (esVence) {
                vence = r;
              } else {
                fecha = r;
              }
            });
          }

          final viejo = t.vigenciaDias != null &&
              fecha != null &&
              DateTime.now().difference(fecha!).inDays > t.vigenciaDias!;
          return Padding(
            padding: EdgeInsets.fromLTRB(20.r, 0, 20.r, 20.r + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.nombre, style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 18)),
                if (t.descripcion != null) ...[
                  SizedBox(height: 4.r),
                  Text(t.descripcion!, style: TextStyle(color: ctx.c.muted)),
                ],
                SizedBox(height: 16.r),
                if (t.vence)
                  OutlinedButton.icon(
                    onPressed: () => elegir(true),
                    icon: Icon(Icons.event_busy_outlined),
                    label: Text(vence == null ? 'Fecha de vencimiento (obligatoria)' : 'Vence: ${fechaCorta(vence!)}'),
                  ),
                if (t.vigenciaDias != null) ...[
                  SizedBox(height: 8.r),
                  OutlinedButton.icon(
                    onPressed: () => elegir(false),
                    icon: Icon(Icons.event_outlined),
                    label: Text(fecha == null ? 'Fecha del documento' : 'Fecha: ${fechaCorta(fecha!)}'),
                  ),
                  if (viejo)
                    Padding(
                      padding: EdgeInsets.only(top: 6.r),
                      child: Text('Tiene más de ${t.vigenciaDias} días: pide uno más reciente.',
                          style: TextStyle(color: ctx.c.warn, fontWeight: FontWeight.w600)),
                    ),
                ],
                SizedBox(height: 12.r),
                TextField(controller: notas, decoration: InputDecoration(labelText: 'Notas (opcional)')),
                SizedBox(height: 16.r),
                FilledButton.icon(
                  onPressed: t.vence && vence == null ? null : () => Navigator.pop(ctx, true),
                  icon: Icon(Icons.cloud_upload_outlined),
                  label: Text('Guardar en el expediente'),
                ),
              ],
            ),
          );
        },
      ),
    );
    final n = notas.text.trim();
    notas.dispose();
    if (ok != true) return null;
    return (vence: vence, fecha: fecha, notas: n.isEmpty ? null : n);
  }

  // ---------------------------------------------------------------------------
  // Ver
  // ---------------------------------------------------------------------------

  Future<void> _ver(Documento d) async {
    try {
      if (d.esImagen) {
        final bytes = await Repo.bajarDocumento(d);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(bytes))),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton.filled(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final url = await Repo.ligaDocumento(d);
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo abrir: ${mensajeError(e)}', error: true);
    }
  }

  Future<void> _detalle(TipoDocumento t) async {
    final versiones = _docs.where((d) => d.tipoId == t.id).toList();
    if (versiones.isEmpty) return _subir(t);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20.r, 4.r, 20.r, 4.r),
                  child: Text(t.nombre, style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                for (final (i, d) in versiones.indexed)
                  ListTile(
                    leading: Icon(d.esPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                    title: Text(i == 0 ? 'Vigente · ${fechaCorta(d.creado)}' : 'Anterior · ${fechaCorta(d.creado)}'),
                    subtitle: Text([
                      if (d.vence != null) '${d.vencido ? 'Venció' : 'Vence'} ${fechaCorta(d.vence!)}',
                      if (d.fechaDocumento != null) 'Fecha ${fechaCorta(d.fechaDocumento!)}',
                      if (d.notas != null) d.notas!,
                    ].join(' · ')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _ver(d);
                    },
                    trailing: IconButton(
                      tooltip: 'Quitar del expediente',
                      icon: Icon(Icons.delete_outline, color: ctx.c.danger),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (!await confirmar(
                          context,
                          titulo: 'Quitar documento',
                          mensaje: 'Se borra este archivo del expediente. Úsalo solo si se subió por error.',
                          si: 'Quitar',
                          peligro: true,
                        )) {
                          return;
                        }
                        try {
                          await Repo.quitarDocumento(d);
                          await _cargar();
                          widget.onCambio?.call();
                        } catch (e) {
                          if (mounted) avisar(context, mensajeError(e), error: true);
                        }
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20.r, 8.r, 20.r, 16.r),
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _subir(t);
                    },
                    icon: Icon(Icons.upload_file),
                    label: Text(t.vence ? 'Subir uno renovado' : 'Subir otra versión'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tipos = _tipos;
    if (_error != null) {
      return EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'No se pudo cargar el expediente',
        message: _error,
        action: OutlinedButton(onPressed: _cargar, child: Text('Reintentar')),
      );
    }
    if (tipos == null) return Center(child: CircularProgressIndicator());

    final estado = Repo.estadoExpediente(tipos, _docs);
    final obligatorios = tipos.where((t) => t.obligatorio).toList();
    final listos = obligatorios.where((t) => estado[t.id]!.$1 == EstadoDoc.ok || estado[t.id]!.$1 == EstadoDoc.vencePronto).length;
    final avance = obligatorios.isEmpty ? 1.0 : listos / obligatorios.length;
    final porCategoria = <String, List<TipoDocumento>>{};
    for (final t in tipos) {
      porCategoria.putIfAbsent(t.categoria, () => []).add(t);
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.resp.margen, 12.r, context.resp.margen, 32.r),
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            avance >= 1 ? 'Expediente completo' : 'Expediente al ${(avance * 100).round()} %',
                            style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                        ),
                        Text('$listos de ${obligatorios.length}', style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    SizedBox(height: 10.r),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: LinearProgressIndicator(
                        value: avance,
                        minHeight: 10.r,
                        color: avance >= 1 ? c.ok : (avance >= 0.6 ? c.warn : c.danger),
                        backgroundColor: c.border,
                      ),
                    ),
                    SizedBox(height: 8.r),
                    Text('Documentos obligatorios entregados. Toca uno para subirlo o verlo.',
                        style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              for (final cat in porCategoria.entries) ...[
                SectionTitle(TipoDocumento.categorias[cat.key] ?? cat.key),
                Panel(
                  padding: EdgeInsets.symmetric(vertical: 4.r),
                  child: Column(
                    children: [
                      for (final (i, t) in cat.value.indexed) ...[
                        if (i > 0) Divider(height: 1, color: c.border, indent: 56.r),
                        _FilaDoc(
                          tipo: t,
                          estado: estado[t.id]!.$1,
                          doc: estado[t.id]!.$2,
                          versiones: _docs.where((d) => d.tipoId == t.id).length,
                          onTap: _subiendo ? null : () => _detalle(t),
                          onSubir: _subiendo ? null : () => _subir(t),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              SizedBox(height: 12.r),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CatalogoDocumentos()));
                    await _cargar();
                  },
                  icon: Icon(Icons.tune),
                  label: Text('Configurar qué documentos se piden'),
                ),
              ),
            ],
          ),
        ),
        if (_subiendo)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.25),
              child: Center(
                child: Panel(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 22.r, height: 22.r, child: CircularProgressIndicator(strokeWidth: 2.5.r)),
                      SizedBox(width: 14.r),
                      Text('Subiendo al expediente…', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FilaDoc extends StatelessWidget {
  const _FilaDoc({
    required this.tipo,
    required this.estado,
    required this.doc,
    required this.versiones,
    required this.onTap,
    required this.onSubir,
  });

  final TipoDocumento tipo;
  final EstadoDoc estado;
  final Documento? doc;
  final int versiones;
  final VoidCallback? onTap;
  final VoidCallback? onSubir;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (color, icono, etiqueta) = estiloDoc(context, estado);
    final d = doc;
    final sub = d == null
        ? (tipo.obligatorio ? 'Obligatorio · falta' : 'Opcional')
        : [
            'Subido ${fechaCorta(d.creado)}',
            if (d.vence != null) '${d.vencido ? 'venció' : 'vence'} ${fechaCorta(d.vence!)}',
            if (versiones > 1) '$versiones versiones',
          ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14.r, 10.r, 6.r, 10.r),
        child: Row(
          children: [
            Icon(icono, color: color, size: 26.r),
            SizedBox(width: 14.r),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tipo.nombre, style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 2.r),
                  Text(sub, style: TextStyle(color: estado == EstadoDoc.ok || estado == EstadoDoc.opcional ? c.muted : color, fontSize: 12.5)),
                ],
              ),
            ),
            if (d == null)
              IconButton(tooltip: 'Subir', onPressed: onSubir, icon: Icon(Icons.add_a_photo_outlined, color: context.scheme.primary))
            else
              Padding(
                padding: EdgeInsets.only(right: 8.r),
                child: StatusChip(label: etiqueta, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Catálogo de documentos: qué se pide, qué es obligatorio y qué vence.
class CatalogoDocumentos extends StatefulWidget {
  const CatalogoDocumentos({super.key});

  @override
  State<CatalogoDocumentos> createState() => _CatalogoDocumentosState();
}

class _CatalogoDocumentosState extends State<CatalogoDocumentos> {
  List<TipoDocumento>? _tipos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final t = await Repo.tiposDocumento(soloActivos: false);
      if (mounted) setState(() => _tipos = t);
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    }
  }

  Future<void> _cambiar(TipoDocumento t, String campo, bool v) async {
    try {
      await Repo.guardarTipoDocumento({...t.j, campo: v});
      await _cargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    }
  }

  Future<void> _nuevo() async {
    final nombre = TextEditingController();
    String categoria = 'personal';
    bool obligatorio = false, vence = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Nuevo documento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nombre, autofocus: true, decoration: InputDecoration(labelText: 'Nombre')),
                SizedBox(height: 12.r),
                DropdownButtonFormField<String>(
                  initialValue: categoria,
                  decoration: InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final e in TipoDocumento.categorias.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => set(() => categoria = v ?? categoria),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Obligatorio'),
                  value: obligatorio,
                  onChanged: (v) => set(() => obligatorio = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Tiene vencimiento'),
                  value: vence,
                  onChanged: (v) => set(() => vence = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Agregar')),
          ],
        ),
      ),
    );
    final n = nombre.text.trim();
    nombre.dispose();
    if (ok != true || n.isEmpty) return;
    final id = n
        .toLowerCase()
        .replaceAll(RegExp('[áà]'), 'a')
        .replaceAll(RegExp('[éè]'), 'e')
        .replaceAll(RegExp('[íì]'), 'i')
        .replaceAll(RegExp('[óò]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    try {
      await Repo.guardarTipoDocumento({
        'id': id,
        'nombre': n,
        'categoria': categoria,
        'obligatorio': obligatorio,
        'vence': vence,
        'orden': 500 + (_tipos?.length ?? 0),
      });
      await _cargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tipos = _tipos;
    return Scaffold(
      appBar: AppBar(title: Text('Documentos del expediente')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _nuevo, icon: Icon(Icons.add), label: Text('Agregar')),
      body: tipos == null
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(context.resp.margen, 8.r, context.resp.margen, 96.r),
              children: [
                Text(
                  'Los obligatorios cuentan para el % del expediente. Apaga "Se pide" para dejar de pedir uno '
                  'sin perder los archivos que ya se subieron.',
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
                SizedBox(height: 10.r),
                for (final t in tipos)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8.r),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.nombre,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: t.activo ? null : c.muted,
                                decoration: t.activo ? null : TextDecoration.lineThrough,
                              )),
                          Text(TipoDocumento.categorias[t.categoria] ?? t.categoria, style: TextStyle(color: c.muted, fontSize: 12.5)),
                          Wrap(
                            spacing: 6.r,
                            children: [
                              FilterChip(label: Text('Se pide'), selected: t.activo, onSelected: (v) => _cambiar(t, 'activo', v)),
                              FilterChip(label: Text('Obligatorio'), selected: t.obligatorio, onSelected: (v) => _cambiar(t, 'obligatorio', v)),
                              FilterChip(label: Text('Vence'), selected: t.vence, onSelected: (v) => _cambiar(t, 'vence', v)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
