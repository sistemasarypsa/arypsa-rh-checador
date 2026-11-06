import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'datos.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

/// Muestra un código de un solo uso como QR grande + letras, con la cuenta
/// regresiva de vigencia y los pasos a seguir en el otro equipo.
Future<void> mostrarCodigo(
  BuildContext context, {
  required Codigo codigo,
  required String titulo,
  required String para,
  required List<String> pasos,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CodigoSheet(codigo: codigo, titulo: titulo, para: para, pasos: pasos),
  );
}

class _CodigoSheet extends StatefulWidget {
  const _CodigoSheet({required this.codigo, required this.titulo, required this.para, required this.pasos});

  final Codigo codigo;
  final String titulo;
  final String para;
  final List<String> pasos;

  @override
  State<_CodigoSheet> createState() => _CodigoSheetState();
}

class _CodigoSheetState extends State<_CodigoSheet> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  String get _restante {
    final d = widget.codigo.expira.difference(DateTime.now());
    if (d.isNegative) return 'vencido';
    if (d.inHours >= 1) return 'vence en ${d.inHours} h ${d.inMinutes % 60} min';
    return 'vence en ${d.inMinutes}:${dos(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final vencido = widget.codigo.expira.isBefore(DateTime.now());
    final cod = widget.codigo.codigo;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24.r, 0, 24.r, 28.r),
      child: Column(
        children: [
          Text(
            widget.titulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFont.display, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4.r),
          Text(widget.para, textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
          SizedBox(height: 20.r),
          AnimatedOpacity(
            duration: Duration(milliseconds: 300),
            opacity: vencido ? 0.15 : 1,
            child: Container(
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card.r),
                border: Border.all(color: c.border),
              ),
              child: QrImageView(
                data: widget.codigo.qr,
                size: 220.r,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: Brand.c600),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Brand.slate900,
                ),
              ),
            ),
          ),
          SizedBox(height: 18.r),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: cod));
              avisar(context, 'Código copiado');
            },
            child: Text(
              '${cod.substring(0, 4)} ${cod.substring(4)}',
              style: TextStyle(
                fontFamily: AppFont.display,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
          ),
          SizedBox(height: 6.r),
          StatusChip(
            label: vencido ? 'Código vencido — genera otro' : 'Un solo uso · $_restante',
            color: vencido ? c.danger : c.ok,
            icon: vencido ? Icons.timer_off_outlined : Icons.timer_outlined,
          ),
          SizedBox(height: 22.r),
          Panel(
            color: c.field,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, p) in widget.pasos.indexed)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 5.r),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24.r,
                          height: 24.r,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                        SizedBox(width: 12.r),
                        Expanded(child: Text(p, style: TextStyle(height: 1.4))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16.r),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text('Listo')),
          ),
        ],
      ),
    );
  }
}
