import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Escala de la interfaz según la pantalla real (MediaQuery).
///
/// Regla de la casa: **ningún tamaño se escribe fijo**. Todo espacio, alto,
/// ancho, radio o ícono se escribe como `16.r`, y el texto lo escala el
/// `TextScaler` que pone `Responsive.envolver` en el `MaterialApp.builder`.
///
/// La base es un teléfono de 390 dp de lado corto (iPhone 13/14, Pixel 7).
/// En una TC51 (360 dp) todo encoge un poco; en una tablet (600–900 dp)
/// crece, con tope para que no se vea caricaturesco.
class Responsive {
  Responsive._(this.size);

  final Size size;

  static const base = 390.0;
  static const _min = 0.80;
  static const _max = 1.45;

  /// Último valor calculado; lo usa la extensión `num.r`.
  static Responsive actual = Responsive._(const Size(base, 844));

  static Responsive de(BuildContext context) => Responsive._(MediaQuery.sizeOf(context));

  double get lado => math.min(size.width, size.height);

  /// Factor general (1.0 en un teléfono de 390 dp).
  double get k => (lado / base).clamp(_min, _max);

  /// Teléfono angosto, teléfono, tablet, pantalla grande.
  bool get compacto => size.width < 600;
  bool get mediano => size.width >= 600 && size.width < 1024;
  bool get expandido => size.width >= 1024;
  bool get horizontal => size.width > size.height;

  /// Ancho máximo del contenido para que en tablet no quede estirado.
  double get anchoContenido => math.min(size.width, 760 * k);

  /// Margen lateral de una lista: 16 en teléfono; en tablet crece para que el
  /// contenido quede centrado con [anchoContenido] como máximo.
  double get margen => math.max(16.0 * k, (size.width - 760 * k) / 2);

  /// Columnas para listas de tarjetas.
  int get columnas => size.width >= 1024 ? 3 : (size.width >= 680 ? 2 : 1);

  /// Pone el factor a toda la app: texto escalado y `actual` al día.
  /// El ajuste de texto del sistema se respeta hasta 1.3× para no romper
  /// el acomodo.
  static Widget envolver(BuildContext context, Widget? child) {
    final mq = MediaQuery.of(context);
    final r = Responsive._(mq.size);
    actual = r;
    final sistema = mq.textScaler.scale(1).clamp(1.0, 1.3);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(r.k * sistema)),
      child: child ?? const SizedBox.shrink(),
    );
  }
}

extension ResponsiveNum on num {
  /// Tamaño escalado a la pantalla: `16.r`.
  double get r => this * Responsive.actual.k;
}

extension ResponsiveContext on BuildContext {
  Responsive get resp => Responsive.de(this);
}
