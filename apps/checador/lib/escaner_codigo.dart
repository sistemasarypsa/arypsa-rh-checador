import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

/// Lee el QR que genera la app de RH ("ARYPSA-RH:XXXXXXXX") o deja teclear
/// los 8 caracteres. Regresa el código con `Navigator.pop`.
class EscanerCodigo extends StatefulWidget {
  const EscanerCodigo({required this.titulo, required this.ayuda, super.key});

  final String titulo;
  final String ayuda;

  static Future<String?> abrir(BuildContext context, {required String titulo, required String ayuda}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => EscanerCodigo(titulo: titulo, ayuda: ayuda), fullscreenDialog: true),
    );
  }

  @override
  State<EscanerCodigo> createState() => _EscanerCodigoState();
}

class _EscanerCodigoState extends State<EscanerCodigo> {
  final _ctl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [BarcodeFormat.qrCode],
  );
  final _manual = TextEditingController();
  bool _listo = false;

  static final _patron = RegExp(r'^ARYPSA-RH:([A-Z0-9]{8})$');

  @override
  void dispose() {
    _ctl.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _entregar(String codigo) {
    if (_listo) return;
    _listo = true;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, codigo);
  }

  void _detectado(BarcodeCapture c) {
    for (final b in c.barcodes) {
      final m = _patron.firstMatch((b.rawValue ?? '').trim());
      if (m != null) {
        _entregar(m.group(1)!);
        return;
      }
    }
  }

  void _teclear() {
    final v = _manual.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (v.length != 8) {
      avisar(context, 'El código tiene 8 letras y números.', error: true);
      return;
    }
    _entregar(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Cambiar cámara',
            onPressed: () => _ctl.switchCamera(),
            icon: Icon(Icons.cameraswitch_outlined),
          ),
          IconButton(
            tooltip: 'Linterna',
            onPressed: () => _ctl.toggleTorch(),
            icon: Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final lado = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight * 0.55) - 48.r;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24.r, 8.r, 24.r, 24.r),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 460.r),
                child: Column(
                  children: [
                    Text(widget.ayuda, textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.4)),
                    SizedBox(height: 18.r),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card.r),
                      child: SizedBox(
                        width: lado.clamp(200.r, 420.r),
                        height: lado.clamp(200.r, 420.r),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(controller: _ctl, onDetect: _detectado),
                            IgnorePointer(
                              child: Container(
                                margin: EdgeInsets.all(28.r),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 3.r),
                                  borderRadius: BorderRadius.circular(18.r),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 24.r),
                    Row(
                      children: [
                        Expanded(child: Divider(color: c.border)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.r),
                          child: Text('o teclea el código', style: TextStyle(color: c.muted, fontSize: 12.5)),
                        ),
                        Expanded(child: Divider(color: c.border)),
                      ],
                    ),
                    SizedBox(height: 16.r),
                    TextField(
                      controller: _manual,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 9,
                      onSubmitted: (_) => _teclear(),
                      style: TextStyle(
                        fontFamily: AppFont.display,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 5,
                      ),
                      decoration: InputDecoration(hintText: 'XXXX XXXX', counterText: ''),
                    ),
                    SizedBox(height: 12.r),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: _teclear, child: Text('Continuar')),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
