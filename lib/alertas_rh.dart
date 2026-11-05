import 'package:flutter/material.dart';

import 'datos.dart';
import 'empleado_detalle.dart';
import 'mx.dart';
import 'responsive.dart';
import 'theme.dart';
import 'ui.dart';

/// Un pendiente del tablero: qué es, a quién afecta y por qué.
class _Pendiente {
  _Pendiente(this.titulo, this.icono, this.color, this.filas);
  final String titulo;
  final IconData icono;
  final Color color;

  /// (empleado, detalle)
  final List<(Empleado, String)> filas;
}

/// "Pendientes de RH" en el tablero: expedientes incompletos, documentos y
/// contratos por vencer, periodos de prueba, cumpleaños y aniversarios.
class AlertasRh extends StatefulWidget {
  const AlertasRh({super.key});

  @override
  State<AlertasRh> createState() => AlertasRhState();
}

class AlertasRhState extends State<AlertasRh> {
  List<Empleado>? _emps;
  List<TipoDocumento> _tipos = const [];
  List<Documento> _docs = const [];
  bool _sinSql = false;

  @override
  void initState() {
    super.initState();
    recargar();
  }

  Future<void> recargar() async {
    try {
      final r = await Future.wait<Object>([Repo.empleados(), Repo.tiposDocumento(), Repo.documentosTodos()]);
      if (!mounted) return;
      setState(() {
        _emps = r[0] as List<Empleado>;
        _tipos = r[1] as List<TipoDocumento>;
        _docs = r[2] as List<Documento>;
        _sinSql = false;
      });
    } catch (e) {
      // Sin el SQL 003 todavía, o sin red: el tablero sigue funcionando.
      if (mounted) setState(() => _sinSql = mensajeError(e).contains('003'));
    }
  }

  List<_Pendiente> _calcular(BuildContext context) {
    final c = context.c;
    final emps = _emps ?? const <Empleado>[];
    final hoy = DateTime.now();
    final h0 = DateTime(hoy.year, hoy.month, hoy.day);
    int dias(DateTime d) => DateTime(d.year, d.month, d.day).difference(h0).inDays;

    final porEmp = <String, List<Documento>>{};
    for (final d in _docs) {
      porEmp.putIfAbsent(d.empleadoId, () => []).add(d);
    }
    final nombresTipo = {for (final t in _tipos) t.id: t.nombre};

    final incompletos = <(Empleado, String)>[];
    final vencen = <(Empleado, String)>[];
    final contratos = <(Empleado, String)>[];
    final prueba = <(Empleado, String)>[];
    final cumple = <(Empleado, String)>[];
    final aniversario = <(Empleado, String)>[];
    final datos = <(Empleado, String)>[];
    final biometria = <(Empleado, String)>[];

    for (final e in emps) {
      // Expediente
      if (_tipos.isNotEmpty) {
        final est = Repo.estadoExpediente(_tipos, porEmp[e.id] ?? const []);
        final faltan = _tipos.where((t) => t.obligatorio && est[t.id]!.$1 == EstadoDoc.falta).toList();
        if (faltan.isNotEmpty) {
          incompletos.add((e, faltan.length <= 2 ? 'Falta: ${faltan.map((t) => t.nombre).join(', ')}' : 'Faltan ${faltan.length} documentos'));
        }
        for (final x in est.entries) {
          final (estado, doc) = x.value;
          if ((estado == EstadoDoc.vencido || estado == EstadoDoc.vencePronto) && doc?.vence != null) {
            vencen.add((
              e,
              '${nombresTipo[x.key]}: ${estado == EstadoDoc.vencido ? 'venció' : 'vence'} ${fechaCorta(doc!.vence!)}',
            ));
          }
        }
      }
      // Contrato y periodo de prueba
      final fin = e.finContrato;
      if (fin != null && dias(fin) <= 30) {
        contratos.add((e, dias(fin) < 0 ? 'Venció el ${fechaCorta(fin)}' : 'Vence el ${fechaCorta(fin)} (${dias(fin)} días)'));
      }
      final p = e.fecha('fin_periodo_prueba');
      if (p != null && dias(p) >= 0 && dias(p) <= 15) prueba.add((e, 'Termina el ${fechaCorta(p)}'));
      // Cumpleaños y aniversarios en los próximos 7 días
      final nac = e.fechaNacimiento;
      if (nac != null) {
        final d = _proximo(nac, h0);
        if (dias(d) <= 7) cumple.add((e, dias(d) == 0 ? '¡Hoy! Cumple ${d.year - nac.year}' : '${fechaCorta(d)} · cumple ${d.year - nac.year}'));
      }
      final ing = e.fechaIngreso;
      if (ing != null && ing.isBefore(h0)) {
        final d = _proximo(ing, h0);
        final anios = d.year - ing.year;
        if (anios > 0 && dias(d) <= 7) {
          aniversario.add((e, '${dias(d) == 0 ? 'Hoy' : fechaCorta(d)} · $anios ${anios == 1 ? 'año' : 'años'} → ${diasVacaciones(anios)} días de vacaciones'));
        }
      }
      // Datos para IMSS y nómina
      final falt = [if (e.txt('curp') == null) 'CURP', if (e.txt('rfc') == null) 'RFC', if (e.txt('nss') == null) 'NSS'];
      if (falt.isNotEmpty) datos.add((e, 'Sin ${falt.join(', ')}'));
      if (e.consentimientoAt == null) {
        biometria.add((e, 'Falta el consentimiento firmado'));
      } else if (!e.biometriaKiosco) {
        biometria.add((e, 'Sin rostro ni huella en el kiosco'));
      }
    }

    return [
      if (contratos.isNotEmpty) _Pendiente('Contratos por vencer', Icons.event_busy_outlined, c.danger, contratos),
      if (vencen.isNotEmpty) _Pendiente('Documentos por vencer', Icons.description_outlined, c.warn, vencen),
      if (incompletos.isNotEmpty) _Pendiente('Expedientes incompletos', Icons.folder_open_outlined, c.warn, incompletos),
      if (datos.isNotEmpty) _Pendiente('Sin CURP, RFC o NSS', Icons.badge_outlined, c.warn, datos),
      if (prueba.isNotEmpty) _Pendiente('Fin de periodo de prueba', Icons.hourglass_bottom, c.info, prueba),
      if (biometria.isNotEmpty) _Pendiente('Sin checar con rostro', Icons.face_retouching_off, c.info, biometria),
      if (cumple.isNotEmpty) _Pendiente('Cumpleaños esta semana', Icons.cake_outlined, context.scheme.primary, cumple),
      if (aniversario.isNotEmpty) _Pendiente('Aniversarios esta semana', Icons.workspace_premium_outlined, c.ok, aniversario),
    ];
  }

  /// Próxima vez (hoy o después) que cae el día/mes de [f].
  static DateTime _proximo(DateTime f, DateTime h0) {
    var d = DateTime(h0.year, f.month, f.day);
    if (d.isBefore(h0)) d = DateTime(h0.year + 1, f.month, f.day);
    return d;
  }

  Future<void> _abrir(_Pendiente p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20.r, 4.r, 20.r, 8.r),
                child: Row(
                  children: [
                    Icon(p.icono, color: p.color),
                    SizedBox(width: 10.r),
                    Expanded(
                      child: Text('${p.titulo} (${p.filas.length})',
                          style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (e, detalle) in p.filas)
                      ListTile(
                        leading: Avatar(nombre: e.nombre, foto: e.foto, size: 40.r),
                        title: Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(detalle),
                        trailing: Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => EmpleadoDetalle(empleadoId: e.id!)),
                          );
                          recargar();
                        },
                      ),
                  ],
                ),
              ),
              SizedBox(height: 8.r),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_sinSql) {
      return Panel(
        color: c.warn.withValues(alpha: 0.10),
        child: Text('Corre 003_expediente.sql en Supabase para ver los pendientes de RH (expedientes, contratos, '
            'cumpleaños…).'),
      );
    }
    if (_emps == null) return SizedBox.shrink();
    final pendientes = _calcular(context);
    if (pendientes.isEmpty) return SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Pendientes de RH'),
        LayoutBuilder(builder: (context, cs) {
          final cols = cs.maxWidth >= 720 ? 3 : 2;
          final gap = 10.r;
          final w = (cs.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final p in pendientes)
                SizedBox(
                  width: w,
                  child: Panel(
                    onTap: () => _abrir(p),
                    padding: EdgeInsets.all(12.r),
                    child: Row(
                      children: [
                        Container(
                          width: 40.r,
                          height: 40.r,
                          decoration: BoxDecoration(color: p.color.withValues(alpha: 0.13), shape: BoxShape.circle),
                          child: Icon(p.icono, color: p.color, size: 21.r),
                        ),
                        SizedBox(width: 10.r),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${p.filas.length}',
                                  style: TextStyle(fontFamily: AppFont.display, fontWeight: FontWeight.w800, fontSize: 20, height: 1.1)),
                              Text(p.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
