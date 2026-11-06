import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'api.dart';
import 'catalogo.dart';
import 'config.dart';
import 'escaner_codigo.dart';
import 'lector/lector.dart';
import 'lector/lector_simulado.dart';
import 'rostro/camara_rostro.dart';
import 'rostro/motor_rostro.dart';
import 'rostro/vista_rostro.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

/// Registro biométrico en el kiosco con el código de RH:
/// rostro (5 tomas con IA) y/o huella (3 lecturas por dedo). Se guarda todo
/// junto al final.
class EnrolarScreen extends StatefulWidget {
  const EnrolarScreen({required this.lector, this.camara, super.key});

  final LectorHuella lector;
  final CamaraRostro? camara;

  @override
  State<EnrolarScreen> createState() => _EnrolarScreenState();
}

/// Numeración ISO/IEC 19794: 1-5 mano derecha (pulgar→meñique), 6-10 izquierda.
const _dedos = {
  2: 'Índice derecho',
  7: 'Índice izquierdo',
  3: 'Medio derecho',
  8: 'Medio izquierdo',
  1: 'Pulgar derecho',
  6: 'Pulgar izquierdo',
};

class _Toma {
  _Toma(this.vector, this.calidad, this.png);

  final List<double> vector;
  final int calidad;
  final Uint8List? png;
}

class _EnrolarScreenState extends State<EnrolarScreen> {
  String? _codigo;
  Map<String, dynamic>? _emp;
  String? _error;
  bool _cargando = false;
  bool _guardando = false;
  late bool _verRostro = widget.camara != null && widget.camara!.error == null;

  // --- Rostro ---
  static const _tomasNecesarias = 5;
  final List<_Toma> _tomas = [];
  StreamSubscription<LecturaRostro>? _sub;
  String _msgCamara = 'Mira a la cámara';
  DateTime _ultimaToma = DateTime.fromMillisecondsSinceEpoch(0);
  bool _capturando = false;
  String? _parecido;

  // --- Huella ---
  int _dedo = 2;
  final List<Captura> _lecturas = [];
  bool _leyendo = false;
  final Map<int, Captura> _listos = {};
  static const _porDedo = 3;

  @override
  void initState() {
    super.initState();
    final cam = widget.camara;
    if (cam != null) {
      // La pantalla se redibuja cuando la cámara se abre, falla o se reabre.
      cam.addListener(_cambioCamara);
      cam.pedirRecorte = true;
      cam.intervalo = const Duration(milliseconds: 300);
      _sub = cam.lecturas.listen(_lectura);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _pedirCodigo());
  }

  @override
  void dispose() {
    _tic?.cancel();
    _sub?.cancel();
    final cam = widget.camara;
    if (cam != null) {
      cam.removeListener(_cambioCamara);
      cam.pedirRecorte = false;
      cam.intervalo = const Duration(milliseconds: 220);
    }
    widget.lector.cancelar();
    super.dispose();
  }

  late bool _camaraFallo = widget.camara?.error != null;

  void _cambioCamara() {
    if (!mounted) return;
    final cam = widget.camara!;
    // Si la cámara había fallado y ya volvió, se regresa a la pestaña de
    // rostro (solo si no se está registrando huella).
    if (cam.error != null) {
      _camaraFallo = true;
    } else if (cam.listo && _camaraFallo) {
      _camaraFallo = false;
      if (!_leyendo && _listos.isEmpty) _verRostro = true;
    }
    setState(() {});
  }

  Future<void> _pedirCodigo() async {
    // El equipo solo deja abrir una cámara a la vez: el escáner de QR se la
    // quita al reconocimiento facial, así que se suelta y se retoma después.
    final cam = widget.camara;
    await cam?.suspender();
    if (!mounted) return;
    final cod = await EscanerCodigo.abrir(
      context,
      titulo: 'Registro biométrico',
      ayuda: 'Escanea el QR que RH generó en la ficha del empleado (Registrar rostro / huella).',
    );
    // Un respiro para que el escáner termine de soltar la cámara.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    unawaited(cam?.reanudar());
    if (!mounted) return;
    if (cod == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final e = await Api.kioscoCodigo(cod);
      if (!mounted) return;
      setState(() {
        _codigo = cod;
        _emp = e;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // -------------------------------------------------------------------------
  // Rostro
  // -------------------------------------------------------------------------

  void _lectura(LecturaRostro l) {
    if (!mounted || _emp == null || !_verRostro || !_capturando) return;
    if (_tomas.length >= _tomasNecesarias) return;
    if (!l.hayCara) {
      setState(() => _msgCamara = 'No veo tu cara');
      return;
    }
    if (l.aviso != null) {
      setState(() => _msgCamara = l.aviso!);
      return;
    }
    final v = l.vector;
    if (v == null) return;
    if (l.calidad < 55) {
      setState(() => _msgCamara = 'Quédate quieto, de frente y con luz');
      return;
    }
    final ahora = DateTime.now();
    if (ahora.difference(_ultimaToma).inMilliseconds < 450) return;

    // Las tomas deben ser de la MISMA persona (que nadie se cruce a medio registro).
    if (_tomas.isNotEmpty && MotorRostro.distancia(_tomas.first.vector, v) > 0.9) {
      setState(() => _msgCamara = 'Solo una persona frente a la cámara');
      return;
    }
    _ultimaToma = ahora;
    final recorte = l.recorte;
    final png = recorte == null ? null : Uint8List.fromList(img.encodePng(recorte));
    HapticFeedback.lightImpact();

    // ¿Esta cara ya está registrada a nombre de otra persona?
    if (_tomas.isEmpty) {
      final otro = catalogo.galeria.buscar(v, excepto: _emp!['id'] as String);
      if (otro != null && otro.distancia < catalogo.galeria.umbral) {
        final e = catalogo.empleados[otro.empleadoId];
        _parecido = 'Ojo: se parece mucho a ${e?.nombre ?? 'otra persona'}'
            '${e != null ? ' (#${e.numero})' : ''}. Revisa que sea la persona correcta.';
        log('Rostro', 'Registro parecido a ${otro.empleadoId} d=${otro.distancia.toStringAsFixed(3)}');
      }
    }

    setState(() {
      _tomas.add(_Toma(v, l.calidad, png));
      final faltan = _tomasNecesarias - _tomas.length;
      _msgCamara = faltan == 0
          ? 'Listo'
          : (_tomas.length == 2 ? 'Gira apenas la cabeza a un lado' : 'Muy bien, sigue mirando · faltan $faltan');
      if (faltan == 0) _capturando = false;
    });
  }

  DateTime _inicioTomas = DateTime.now();

  /// Refresca la barra de avance y el indicador de la IA mientras se toman fotos.
  Timer? _tic;

  void _iniciarTomas() {
    _inicioTomas = DateTime.now();
    _tic?.cancel();
    _tic = Timer.periodic(Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      if (!_capturando) _tic?.cancel();
      setState(() {});
    });
    setState(() {
      _tomas.clear();
      _parecido = null;
      _capturando = true;
      _msgCamara = 'Mira a la cámara';
    });
  }

  // -------------------------------------------------------------------------
  // Huella
  // -------------------------------------------------------------------------

  Future<void> _leer() async {
    if (_leyendo) return;
    setState(() {
      _leyendo = true;
      _error = null;
    });
    try {
      while (_lecturas.length < _porDedo && mounted) {
        final cap = await widget.lector.capturar();
        if (!mounted) return;
        if (cap.calidad < 40) {
          HapticFeedback.vibrate();
          setState(() => _error = 'Lectura borrosa (calidad ${cap.calidad}). Presiona un poco más y no muevas el dedo.');
          continue;
        }
        HapticFeedback.mediumImpact();
        setState(() {
          _lecturas.add(cap);
          _error = null;
        });
        await Future<void>.delayed(Duration(milliseconds: 600));
      }
      if (!mounted) return;
      final unida = await widget.lector.combinar(List.of(_lecturas));
      if (!mounted) return;
      setState(() {
        _listos[_dedo] = unida;
        _lecturas.clear();
      });
    } on LectorCancelado {
      // salió de la pantalla
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is LectorError ? e.mensaje : mensajeError(e);
          _lecturas.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  void _otroDedo() {
    final siguiente = _dedos.keys.firstWhere((d) => !_listos.containsKey(d), orElse: () => 7);
    setState(() {
      _dedo = siguiente;
      _lecturas.clear();
    });
  }

  // -------------------------------------------------------------------------

  bool get _rostroListo => _tomas.length >= _tomasNecesarias;
  bool get _hayAlgo => _rostroListo || _listos.isNotEmpty;

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await Api.kioscoEnrolar(
        _codigo!,
        plantillas: [
          for (final e in _listos.entries)
            {'dedo': e.key, 'formato': widget.lector.formato, 'plantilla': e.value.plantilla, 'calidad': e.value.calidad},
        ],
        rostros: _rostroListo
            ? [
                for (final t in _tomas) {'modelo': MotorRostro.modelo, 'vector': t.vector, 'calidad': t.calidad},
              ]
            : [],
      );
      if (!mounted) return;
      final que = [if (_rostroListo) 'rostro', if (_listos.isNotEmpty) 'huella'].join(' y ');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.verified, color: ctx.c.ok, size: 48.r),
          title: Text('Registro guardado'),
          content: Text('Se guardó: $que. ${_emp!['nombres']} ya puede checar en este y en todos los kioscos.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text('Listo'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = _emp;
    // Mientras la cámara se reabre (tras el escáner) sigue contando como
    // disponible; solo se desactiva si de plano falló.
    final camOk = widget.camara != null && widget.camara!.error == null;
    return Scaffold(
      appBar: AppBar(title: Text('Registro biométrico')),
      body: _cargando
          ? Center(child: CircularProgressIndicator())
          : e == null
              ? EmptyState(
                  icon: Icons.qr_code_2,
                  title: _error ?? 'Escanea el código',
                  action: FilledButton(onPressed: _pedirCodigo, child: Text('Escanear de nuevo')),
                )
              // Arriba, no centrado: en pantallas bajas (TC51) el contenido no
              // cabe y debe poder bajarse completo.
              : Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(context.resp.margen, 12.r, context.resp.margen, 32.r),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 560.r),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Avatar(nombre: '${e['nombres']} ${e['apellidos'] ?? ''}', foto: e['foto'] as String?, size: 52.r),
                              SizedBox(width: 14.r),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${e['nombres']} ${e['apellidos'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontFamily: AppFont.display, fontSize: 17, fontWeight: FontWeight.w800, height: 1.15),
                                    ),
                                    Text('#${e['numero']}${e['puesto'] != null ? ' · ${e['puesto']}' : ''}',
                                        style: TextStyle(color: c.muted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20.r),
                          SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: true,
                                enabled: camOk,
                                icon: Icon(_rostroListo ? Icons.check_circle : Icons.face_retouching_natural),
                                label: Text('Rostro'),
                              ),
                              ButtonSegment(
                                value: false,
                                icon: Icon(_listos.isNotEmpty ? Icons.check_circle : Icons.fingerprint),
                                label: Text('Huella'),
                              ),
                            ],
                            selected: {_verRostro},
                            onSelectionChanged: _leyendo ? null : (s) => setState(() => _verRostro = s.first),
                          ),
                          if (!camOk)
                            Padding(
                              padding: EdgeInsets.only(top: 8.r),
                              child: Column(
                                children: [
                                  Text('Cámara no disponible: ${widget.camara?.error ?? 'sin iniciar'}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: c.warn, fontSize: 12.5)),
                                  if (widget.camara != null)
                                    TextButton.icon(
                                      onPressed: () => widget.camara!.reabrir(),
                                      icon: Icon(Icons.refresh),
                                      label: Text('Reintentar cámara'),
                                    ),
                                ],
                              ),
                            ),
                          SizedBox(height: 22.r),
                          if (_verRostro && camOk) _seccionRostro(context) else _seccionHuella(context),
                          if (_error != null) ...[
                            SizedBox(height: 12.r),
                            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
                          ],
                          SizedBox(height: 24.r),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _hayAlgo && !_guardando && !_leyendo ? _guardar : null,
                              icon: Icon(Icons.save_outlined),
                              label: Text(
                                _hayAlgo
                                    ? 'Guardar ${[if (_rostroListo) 'rostro', if (_listos.isNotEmpty) '${_listos.length} ${_listos.length == 1 ? 'dedo' : 'dedos'}'].join(' + ')}'
                                    : 'Registra rostro o huella para guardar',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _seccionRostro(BuildContext context) {
    final c = context.c;
    final cam = widget.camara!;
    final listo = _rostroListo;
    final color = listo ? c.ok : (_capturando ? c.info : Brand.ink600);
    // Tamaños según la pantalla: la cámara ocupa ~un tercio del alto, sin
    // pasarse del ancho; las miniaturas se reparten el ancho disponible.
    final pantalla = MediaQuery.sizeOf(context);
    final lado = math.min(pantalla.width * 0.62, pantalla.height * 0.32);
    final mini = math.min(52.r, (math.min(pantalla.width, 560.r) - 2 * context.resp.margen) / _tomasNecesarias - 8.r);
    final sinTomas = _capturando && _tomas.isEmpty && DateTime.now().difference(_inicioTomas).inSeconds >= 4;
    return Column(
      children: [
        VistaCamara(camara: cam, lado: lado, color: color),
        SizedBox(height: 14.r),
        Text(
          listo ? 'Rostro listo' : (_capturando ? _msgCamara : 'Pide al empleado que se pare frente a la tablet'),
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        if (_capturando || listo) ...[
          SizedBox(height: 12.r),
          _AvanceTomas(
            tomas: _tomas.length,
            total: _tomasNecesarias,
            listo: listo,
            analizando: !listo &&
                cam.ultimoProcesado != null &&
                DateTime.now().difference(cam.ultimoProcesado!).inMilliseconds < 1500,
            cuadros: cam.procesados,
            ancho: math.min(pantalla.width - 2 * context.resp.margen, 420.r),
          ),
        ],
        SizedBox(height: 12.r),
        // Las tomas: sirven también para revisar que el recorte salga derecho.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _tomasNecesarias; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.r),
                child: Container(
                  width: mini,
                  height: mini,
                  decoration: BoxDecoration(
                    color: c.field,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: i < _tomas.length ? c.ok : c.border, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: i < _tomas.length && _tomas[i].png != null
                      ? Image.memory(_tomas[i].png!, fit: BoxFit.cover, gaplessPlayback: true)
                      : Icon(Icons.face, color: c.muted.withValues(alpha: 0.4)),
                ),
              ),
          ],
        ),
        // Si en 4 s no hay ni una toma, se muestra qué está viendo la cámara.
        if (sinTomas || cam.ultimoError != null)
          AnimatedBuilder(
            animation: cam,
            builder: (_, _) => Padding(
              padding: EdgeInsets.only(top: 10.r),
              child: Text(
                cam.diagnostico,
                textAlign: TextAlign.center,
                style: TextStyle(color: cam.ultimoError != null ? c.danger : c.muted, fontSize: 11.5),
              ),
            ),
          ),
        if (_parecido != null) ...[
          SizedBox(height: 10.r),
          StatusChip(label: _parecido!, color: c.warn, icon: Icons.warning_amber_rounded),
        ],
        SizedBox(height: 14.r),
        if (!_capturando)
          OutlinedButton.icon(
            onPressed: _iniciarTomas,
            icon: Icon(listo ? Icons.refresh : Icons.camera_front),
            label: Text(listo ? 'Repetir' : 'Empezar'),
          ),
      ],
    );
  }

  Widget _seccionHuella(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        if (widget.lector.simulado)
          Padding(
            padding: EdgeInsets.only(bottom: 12.r),
            child: StatusChip(label: 'Modo prueba: toca el círculo para simular cada lectura', color: c.warn),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8.r,
          runSpacing: 8.r,
          children: [
            for (final d in _dedos.entries)
              ChoiceChip(
                label: Text(d.value),
                avatar: _listos.containsKey(d.key) ? Icon(Icons.check_circle, size: 18.r, color: c.ok) : null,
                selected: _dedo == d.key,
                onSelected: _leyendo
                    ? null
                    : (_) => setState(() {
                          _dedo = d.key;
                          _lecturas.clear();
                        }),
              ),
          ],
        ),
        SizedBox(height: 22.r),
        GestureDetector(
          onTap: () {
            final l = widget.lector;
            if (!_leyendo) {
              _leer();
            } else if (l is LectorSimulado) {
              l.tocar();
            }
          },
          child: _Progreso(
            lecturas: _listos.containsKey(_dedo) ? _porDedo : _lecturas.length,
            total: _porDedo,
            leyendo: _leyendo,
            listo: _listos.containsKey(_dedo),
          ),
        ),
        SizedBox(height: 14.r),
        Text(
          _listos.containsKey(_dedo)
              ? '${_dedos[_dedo]} listo'
              : _leyendo
                  ? 'Pon el ${_dedos[_dedo]!.toLowerCase()} · lectura ${_lecturas.length + 1} de $_porDedo'
                  : 'Toca el círculo y pon el ${_dedos[_dedo]!.toLowerCase()} en el lector',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        if (_listos.isNotEmpty && _listos.length < 2 && !_leyendo) ...[
          SizedBox(height: 12.r),
          OutlinedButton.icon(
            onPressed: _otroDedo,
            icon: Icon(Icons.add),
            label: Text('Registrar otro dedo (recomendado)'),
          ),
        ],
      ],
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.lecturas, required this.total, required this.leyendo, required this.listo});

  final int lecturas;
  final int total;
  final bool leyendo;
  final bool listo;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = listo ? c.ok : context.scheme.primary;
    return SizedBox(
      width: 190.r,
      height: 190.r,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: lecturas / total),
              duration: Duration(milliseconds: 350),
              builder: (_, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: 10.r,
                strokeCap: StrokeCap.round,
                backgroundColor: c.field,
                color: color,
              ),
            ),
          ),
          Container(
            width: 140.r,
            height: 140.r,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: leyendo ? 0.20 : 0.10)),
            child: Icon(listo ? Icons.check_rounded : Icons.fingerprint, size: 84.r, color: color),
          ),
        ],
      ),
    );
  }
}


/// Barra de avance del registro de rostro: cuántas tomas van y si la IA está
/// analizando la cámara en este momento.
class _AvanceTomas extends StatelessWidget {
  const _AvanceTomas({
    required this.tomas,
    required this.total,
    required this.listo,
    required this.analizando,
    required this.cuadros,
    required this.ancho,
  });

  final int tomas;
  final int total;
  final bool listo;
  final bool analizando;
  final int cuadros;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = listo ? c.ok : c.info;
    return SizedBox(
      width: ancho,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: tomas / total),
              duration: Duration(milliseconds: 350),
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10.r,
                backgroundColor: c.field,
                color: color,
              ),
            ),
          ),
          SizedBox(height: 8.r),
          Row(
            children: [
              Text(
                listo ? '¡Listo! $total de $total tomas' : '$tomas de $total tomas',
                style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13),
              ),
              Spacer(),
              if (!listo) ...[
                // Punto que late cada vez que la IA termina un cuadro.
                AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: 9.r,
                  height: 9.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: analizando ? (cuadros.isEven ? c.ok : c.ok.withValues(alpha: 0.35)) : c.danger,
                  ),
                ),
                SizedBox(width: 6.r),
                Text(
                  analizando ? 'IA analizando · $cuadros' : 'La cámara no entrega imágenes',
                  style: TextStyle(fontSize: 12, color: analizando ? c.muted : c.danger, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
