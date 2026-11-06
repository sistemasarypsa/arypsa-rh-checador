import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

/// Lo que se le muestra a la persona después de poner el dedo.
class Resultado {
  Resultado({
    required this.nombre,
    this.foto,
    required this.tipo,
    required this.hora,
    this.estado = 'valida',
    this.minutosRetardo,
    this.sede,
    this.distanciaM,
    this.pendiente = false,
    this.repetida = false,
  });

  final String nombre;
  final String? foto;

  /// 'entrada' | 'salida'
  final String tipo;
  final DateTime hora;
  final String estado;
  final int? minutosRetardo;
  final String? sede;
  final num? distanciaM;

  /// Sin red: quedó guardada en el equipo y se enviará sola.
  final bool pendiente;

  /// Ya había checado hace menos de un minuto.
  final bool repetida;

  bool get entrada => tipo == 'entrada';
  bool get valida => estado == 'valida';
}

/// Tarjeta grande de confirmación. Se usa en pantalla completa en el kiosco
/// y dentro de un sheet en el celular.
class TarjetaResultado extends StatelessWidget {
  const TarjetaResultado({required this.r, this.grande = false, super.key});

  final Resultado r;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // k: tamaño de kiosco para el texto (la pantalla ya la escala el
    // TextScaler); kr: lo mismo × pantalla, para cajas e íconos.
    final k = grande ? 1.5 : 1.0;
    final kr = k * Responsive.actual.k;

    final Color color;
    final IconData icono;
    final String titulo;
    final String? detalle;

    if (!r.valida) {
      color = r.estado == 'fuera_geocerca' ? c.danger : c.info;
      icono = r.estado == 'fuera_geocerca' ? Icons.wrong_location_outlined : Icons.gpp_maybe_outlined;
      titulo = r.estado == 'fuera_geocerca' ? 'Fuera de la sede' : 'Registrada para revisión';
      detalle = r.estado == 'fuera_geocerca'
          ? 'Estás a ${metros(r.distanciaM)} de ${r.sede ?? 'la sede'}. No cuenta como ${r.tipo}.'
          : 'RH la revisará antes de contarla.';
    } else if (r.repetida) {
      color = c.info;
      icono = Icons.done_all;
      titulo = 'Ya habías checado';
      detalle = '${r.entrada ? 'Entrada' : 'Salida'} a las ${hhmm(r.hora)}';
    } else {
      color = r.entrada ? c.ok : Color(0xFF6366F1);
      icono = r.entrada ? Icons.login_rounded : Icons.logout_rounded;
      titulo = r.entrada ? 'ENTRADA' : 'SALIDA';
      if ((r.minutosRetardo ?? 0) > 0) {
        detalle = 'Retardo de ${r.minutosRetardo} min';
      } else if (r.entrada) {
        detalle = r.pendiente ? null : 'A tiempo';
      } else {
        detalle = '¡Buen descanso!';
      }
    }

    final retardo = r.valida && !r.repetida && (r.minutosRetardo ?? 0) > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Avatar(nombre: r.nombre, foto: r.foto, size: 132 * kr, ring: color),
            Positioned(
              bottom: -6 * kr,
              right: -6 * kr,
              child: Container(
                padding: EdgeInsets.all(8 * kr),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 4.r),
                ),
                child: Icon(icono, color: Colors.white, size: 26 * kr),
              ),
            ),
          ],
        ),
        SizedBox(height: 20 * kr),
        Text(
          r.nombre,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(fontFamily: AppFont.display, fontSize: 24 * k, fontWeight: FontWeight.w700, letterSpacing: -0.4),
        ),
        SizedBox(height: 10 * kr),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFont.display,
            fontSize: (r.valida && !r.repetida ? 40 : 26) * k,
            fontWeight: FontWeight.w800,
            letterSpacing: r.valida && !r.repetida ? 3 : -0.3,
            color: color,
          ),
        ),
        Text(
          hhmmss(r.hora),
          style: TextStyle(
            fontFamily: AppFont.display,
            fontSize: 30 * k,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (detalle != null) ...[
          SizedBox(height: 10 * kr),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * kr, vertical: 8 * kr),
            decoration: BoxDecoration(
              color: (retardo ? c.warn : color).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill.r),
            ),
            child: Text(
              detalle,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15 * k, color: retardo ? c.warn : color),
            ),
          ),
        ],
        if (r.pendiente) ...[
          SizedBox(height: 10 * kr),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 16 * kr, color: c.muted),
              SizedBox(width: 6.r),
              Text('Guardada sin internet · se envía sola', style: TextStyle(color: c.muted, fontSize: 13 * k)),
            ],
          ),
        ] else if (r.sede != null && r.valida) ...[
          SizedBox(height: 10 * kr),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place_outlined, size: 16 * kr, color: c.muted),
              SizedBox(width: 4.r),
              Text(r.sede!, style: TextStyle(color: c.muted, fontSize: 13 * k)),
            ],
          ),
        ],
      ],
    );
  }
}
