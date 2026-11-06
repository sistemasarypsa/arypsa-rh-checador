import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme.dart';
import 'responsive.dart';

// ---------------------------------------------------------------------------
// Marca
// ---------------------------------------------------------------------------

class BrandLogo extends StatelessWidget {
  const BrandLogo({this.height, this.forceWhite = false, super.key});

  /// null = 26 escalado a la pantalla.
  final double? height;
  final bool forceWhite;

  @override
  Widget build(BuildContext context) {
    final blanco = forceWhite || context.isDark;
    return Image.asset(
      blanco ? 'assets/img/arypsa-logo-full-white.png' : 'assets/img/arypsa-logo-full.png',
      height: height ?? 26.r,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.isDark ? 'Tema claro' : 'Tema oscuro',
      onPressed: themeController.toggle,
      icon: Icon(context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}

// ---------------------------------------------------------------------------
// Superficies
// ---------------------------------------------------------------------------

/// Tarjeta del portal: muy redondeada, sombra suave en claro, borde en oscuro.
class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    super.key,
  });

  final Widget child;
  /// null = 16 escalado a la pantalla.
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final radius = BorderRadius.circular(AppRadius.card.r);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.scheme.surface,
        borderRadius: radius,
        boxShadow: c.shadows,
        border: c.elevated ? null : Border.all(color: c.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding ?? EdgeInsets.all(16.r), child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.r, 18.r, 4.r, 10.r),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: context.c.muted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Pastilla de estado: "Huella lista", "Retardo 12 min", etc.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.color, this.icon, super.key});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.r, vertical: 5.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14.r, color: color),
            SizedBox(width: 5.r),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, this.message, this.action, super.key});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72.r,
              height: 72.r,
              decoration: BoxDecoration(
                color: context.scheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34.r, color: context.scheme.primary),
            ),
            SizedBox(height: 16.r),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppFont.display, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              SizedBox(height: 6.r),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: context.c.muted, height: 1.4)),
            ],
            if (action != null) ...[SizedBox(height: 18.r), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Foto del empleado
// ---------------------------------------------------------------------------

/// Decodificar base64 en cada build sale caro en listas largas: se guarda.
class _FotoCache {
  static final _m = LinkedHashMap<int, Uint8List>();

  static Uint8List? get(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    final k = Object.hash(b64.length, b64.hashCode);
    final hit = _m.remove(k);
    if (hit != null) {
      _m[k] = hit;
      return hit;
    }
    try {
      final bytes = base64Decode(b64);
      _m[k] = bytes;
      if (_m.length > 400) _m.remove(_m.keys.first);
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

class Avatar extends StatelessWidget {
  const Avatar({required this.nombre, this.foto, this.size, this.ring, super.key});

  final String nombre;
  final String? foto;

  /// null = 44 escalado a la pantalla.
  final double? size;
  final Color? ring;

  String get _iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes[0].substring(0, 1) + partes[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = this.size ?? 44.r;
    final bytes = _FotoCache.get(foto);
    final child = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, width: size, height: size)
        : Container(
            color: context.scheme.primary.withValues(alpha: 0.12),
            alignment: Alignment.center,
            child: Text(
              _iniciales,
              // El tamaño ya sale de `size`, que está escalado.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: AppFont.display,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.36,
                color: context.scheme.primary,
              ),
            ),
          );
    return Container(
      width: size,
      height: size,
      padding: ring != null ? EdgeInsets.all(size * 0.05) : EdgeInsets.zero,
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: ClipOval(child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Mensajes
// ---------------------------------------------------------------------------

/// Traduce las excepciones de las funciones SQL (`raise exception 'x'`) y de
/// la red a algo que se pueda leer en planta.
String mensajeError(Object e) {
  debugPrint('[error] ${e.runtimeType}: $e');
  String raw;
  if (e is PostgrestException) {
    raw = e.message;
  } else if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Correo o contraseña incorrectos.';
    return e.message;
  } else {
    raw = e.toString();
  }
  const conocidos = {
    'equipo_invalido': 'Este equipo fue dado de baja o ya no es válido. Hay que activarlo de nuevo.',
    'codigo_invalido': 'El código no existe, ya se usó o ya venció. Pide uno nuevo a RH.',
    'codigo_no_es_de_equipo': 'Ese código es para registrar huella, no para activar un equipo.',
    'empleado_no_disponible': 'El empleado está dado de baja o no tiene permitido checar desde celular.',
    'empleado_no_encontrado': 'No se encontró el empleado.',
    'falta_consentimiento': 'Falta registrar el consentimiento del empleado para usar su huella.',
    'empleado_sin_checado_movil': 'Activa "Checa desde su celular" en la ficha del empleado.',
    'sede_no_encontrada': 'Elige una sede activa.',
    'sin_permiso': 'Tu cuenta no tiene permisos de RH.',
    'sin_plantillas': 'No se capturó ninguna huella.',
  };
  for (final entry in conocidos.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  if (raw.contains('duplicate key') && raw.contains('numero')) {
    return 'Ya existe un empleado con ese número.';
  }
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('TimeoutException')) {
    return 'Sin conexión con el servidor. Revisa el internet.';
  }
  return raw.replaceFirst('Exception: ', '');
}

void avisar(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? context.c.danger : null,
    ),
  );
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String si = 'Sí, continuar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
        FilledButton(
          style: peligro ? FilledButton.styleFrom(backgroundColor: ctx.c.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(si),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ---------------------------------------------------------------------------
// Fechas (siempre hora local del equipo; las empresas están en México)
// ---------------------------------------------------------------------------

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String dos(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime t) {
  final l = t.toLocal();
  return '${dos(l.hour)}:${dos(l.minute)}';
}

String hhmmss(DateTime t) {
  final l = t.toLocal();
  return '${dos(l.hour)}:${dos(l.minute)}:${dos(l.second)}';
}

String fechaLarga(DateTime t) {
  final l = t.toLocal();
  return '${_dias[l.weekday - 1]} ${l.day} de ${_meses[l.month - 1]}';
}

String fechaCorta(DateTime t) {
  final l = t.toLocal();
  return '${l.day} ${_meses[l.month - 1].substring(0, 3)} ${l.year}';
}

String haceCuanto(DateTime? t) {
  if (t == null) return 'nunca';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 60) return 'hace un momento';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  if (d.inDays < 30) return 'hace ${d.inDays} días';
  return fechaCorta(t);
}

String metros(num? m) {
  if (m == null) return '—';
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
  return '${m.round()} m';
}

DateTime? fechaDe(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
