import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui.dart';
import 'camara_rostro.dart';
import '../responsive.dart';

enum EstadoRostro { buscando, aviso, reconociendo, vida, huella, listo, error }

/// Vista previa de la cámara frontal dentro de un círculo, con un anillo que
/// cambia de color según lo que está pasando.
class VistaCamara extends StatelessWidget {
  const VistaCamara({required this.camara, required this.lado, required this.color, this.anillo, super.key});

  final CamaraRostro camara;
  final double lado;
  final Color color;
  /// null = 6 escalado.
  final double? anillo;

  @override
  Widget build(BuildContext context) {
    final c = camara.controlador;
    Widget vista;
    if (c == null || !c.value.isInitialized) {
      vista = const ColoredBox(color: Brand.ink800);
    } else {
      final ps = c.value.previewSize ?? Size(640, 480);
      final vertical = MediaQuery.orientationOf(context) == Orientation.portrait;
      // previewSize viene en horizontal; en pantalla vertical se voltea.
      final w = vertical ? ps.height : ps.width;
      final h = vertical ? ps.width : ps.height;
      vista = FittedBox(fit: BoxFit.cover, child: SizedBox(width: w, height: h, child: CameraPreview(c)));
    }
    return AnimatedContainer(
      duration: Duration(milliseconds: 220),
      width: lado,
      height: lado,
      padding: EdgeInsets.all(anillo ?? 6.r),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 40.r, spreadRadius: 2.r)],
      ),
      child: ClipOval(child: vista),
    );
  }
}

/// El panel principal del kiosco cuando el reconocimiento facial está activo.
class PanelRostro extends StatelessWidget {
  const PanelRostro({
    required this.camara,
    required this.lado,
    required this.estado,
    required this.mensaje,
    required this.procesando,
    this.pieHuella,
    this.onTapHuella,
    this.error,
    super.key,
  });

  final CamaraRostro camara;
  final double lado;
  final EstadoRostro estado;
  final String mensaje;
  final bool procesando;
  final String? pieHuella;
  final VoidCallback? onTapHuella;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (estado) {
      EstadoRostro.buscando => Brand.ink600,
      EstadoRostro.aviso => c.warn,
      EstadoRostro.reconociendo => c.info,
      EstadoRostro.vida => c.ok,
      EstadoRostro.huella => Brand.c500,
      EstadoRostro.listo => c.ok,
      EstadoRostro.error => c.danger,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            VistaCamara(camara: camara, lado: lado, color: color),
            if (procesando)
              Container(
                width: lado,
                height: lado,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.45)),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            if (estado == EstadoRostro.huella && !procesando)
              Container(
                width: lado,
                height: lado,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.c500.withValues(alpha: 0.35)),
                child: Icon(Icons.fingerprint, size: lado * 0.4, color: Colors.white),
              ),
          ],
        ),
        SizedBox(height: 18.r),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 180),
          child: Text(
            mensaje,
            key: ValueKey(mensaje),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFont.display, fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        if (pieHuella != null) ...[
          SizedBox(height: 10.r),
          InkWell(
            onTap: onTapHuella,
            borderRadius: BorderRadius.circular(AppRadius.pill.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.r, vertical: 8.r),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, color: c.muted, size: 20.r),
                  SizedBox(width: 8.r),
                  Text(pieHuella!, style: TextStyle(color: c.muted, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: 8.r),
            // Texto completo (no una pastilla de un renglón): sirve para diagnosticar.
            child: Text(
              error!,
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.danger, fontSize: 11.5),
            ),
          ),
      ],
    );
  }
}
