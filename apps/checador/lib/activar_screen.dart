import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'api.dart';
import 'equipo.dart';
import 'escaner_codigo.dart';
import 'theme.dart';
import 'ui.dart';
import 'ubicacion.dart';
import 'responsive.dart';

/// Primera vez que se abre la app en un equipo: se canjea el código que
/// generó RH. El código dice si el equipo será kiosco o celular de alguien.
class ActivarScreen extends StatefulWidget {
  const ActivarScreen({super.key});

  @override
  State<ActivarScreen> createState() => _ActivarScreenState();
}

class _ActivarScreenState extends State<ActivarScreen> {
  bool _trabajando = false;
  String? _error;

  Future<void> _activar({required bool kiosco}) async {
    setState(() => _error = null);

    // El celular necesita biometría y ubicación antes de gastar el código.
    if (!kiosco) {
      try {
        final auth = LocalAuthentication();
        final soporta = await auth.isDeviceSupported();
        final biom = await auth.getAvailableBiometrics();
        if (!soporta || biom.isEmpty) {
          setState(() => _error = 'Este teléfono no tiene huella o Face ID configurados. '
              'Configúralos en Ajustes del teléfono y vuelve a intentar.');
          return;
        }
        await Ubicacion.asegurarPermiso();
        // Primer uso de la biometría antes de gastar el código: si aquí
        // falla, mejor enterarse ahora y no en la primera checada.
        final ok = await auth.authenticate(
          localizedReason: 'Confirma que este es tu teléfono',
          options: AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );
        if (!ok) {
          setState(() => _error = 'No se confirmó la huella / Face ID. Intenta de nuevo.');
          return;
        }
      } on UbicacionError catch (e) {
        setState(() => _error = e.mensaje);
        if (e.abrirAjustes) await Ubicacion.abrirAjustes();
        return;
      } catch (e) {
        setState(() => _error = mensajeError(e));
        return;
      }
    }
    if (!mounted) return;

    final codigo = await EscanerCodigo.abrir(
      context,
      titulo: kiosco ? 'Activar kiosco' : 'Vincular mi celular',
      ayuda: kiosco
          ? 'Escanea el QR que RH generó en Equipos › Nuevo kiosco.'
          : 'Escanea el QR que RH generó en tu ficha (Vincular celular).',
    );
    if (codigo == null || !mounted) return;

    setState(() => _trabajando = true);
    try {
      final r = await Api.activar(codigo);
      final tipo = r['tipo'] as String;
      if (kiosco && tipo != 'kiosco') throw Exception('Ese código es para vincular un celular, no un kiosco.');
      if (!kiosco && tipo != 'movil') throw Exception('Ese código es para activar un kiosco, no un celular.');

      await equipo.guardar(id: r['equipo_id'] as String, secreto: r['secreto'] as String, tipo: tipo);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24.r),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: BrandLogo(height: 34.r)),
                  SizedBox(height: 28.r),
                  Text(
                    'Reloj checador',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: AppFont.display, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8),
                  ),
                  SizedBox(height: 6.r),
                  Text(
                    '¿Qué va a ser este equipo?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 16),
                  ),
                  SizedBox(height: 28.r),
                  _Opcion(
                    icon: Icons.tablet_android,
                    titulo: 'Kiosco de la empresa',
                    texto: 'Tablet o handheld fija en la entrada, con lector de huella USB. Checa todo el personal.',
                    habilitado: !_trabajando && Platform.isAndroid,
                    nota: Platform.isAndroid ? null : 'Solo Android (el lector USB no funciona en iPhone/iPad).',
                    onTap: () => _activar(kiosco: true),
                  ),
                  SizedBox(height: 14.r),
                  _Opcion(
                    icon: Icons.smartphone,
                    titulo: 'Mi celular',
                    texto: 'Para personal administrativo autorizado por RH. Checas con la huella o Face ID de tu teléfono, '
                        'solo dentro de una sede.',
                    habilitado: !_trabajando,
                    onTap: () => _activar(kiosco: false),
                  ),
                  if (_trabajando) ...[
                    SizedBox(height: 24.r),
                    Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    SizedBox(height: 20.r),
                    Panel(
                      color: c.danger.withValues(alpha: 0.10),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: c.danger),
                          SizedBox(width: 12.r),
                          Expanded(child: Text(_error!, style: TextStyle(height: 1.35))),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 28.r),
                  Text(
                    'El código lo genera Recursos Humanos en la app Arypsa RH. Es de un solo uso.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icon,
    required this.titulo,
    required this.texto,
    required this.habilitado,
    required this.onTap,
    this.nota,
  });

  final IconData icon;
  final String titulo;
  final String texto;
  final bool habilitado;
  final VoidCallback onTap;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = context.scheme.primary;
    return Opacity(
      opacity: habilitado ? 1 : 0.5,
      child: Panel(
        onTap: habilitado ? onTap : null,
        padding: EdgeInsets.all(18.r),
        child: Row(
          children: [
            Container(
              width: 58.r,
              height: 58.r,
              decoration: BoxDecoration(color: p.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18.r)),
              child: Icon(icon, color: p, size: 30.r),
            ),
            SizedBox(width: 16.r),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TextStyle(fontFamily: AppFont.display, fontSize: 17, fontWeight: FontWeight.w700)),
                  SizedBox(height: 4.r),
                  Text(texto, style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
                  if (nota != null) ...[
                    SizedBox(height: 4.r),
                    Text(nota!, style: TextStyle(color: c.warn, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.muted),
          ],
        ),
      ),
    );
  }
}
