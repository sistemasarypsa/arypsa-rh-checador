import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'catalogo.dart';
import 'cola.dart';
import 'enrolar_screen.dart';
import 'config.dart';
import 'equipo.dart';
import 'lector/lector.dart';
import 'lector/lector_simulado.dart';
import 'resultado.dart';
import 'rostro/camara_rostro.dart';
import 'rostro/vista_rostro.dart';
import 'theme.dart';
import 'ui.dart';
import 'ubicacion.dart';
import 'responsive.dart';

/// Pantalla fija del kiosco: reloj grande, lector siempre escuchando y
/// confirmación a pantalla completa con foto. Funciona sin internet.
class KioscoScreen extends StatefulWidget {
  const KioscoScreen({super.key});

  @override
  State<KioscoScreen> createState() => _KioscoScreenState();
}

class _KioscoScreenState extends State<KioscoScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  LectorHuella? _lector;
  String? _errorLector;
  bool _pausa = false;
  bool _vivo = true;
  bool _noReconocido = false;
  bool _procesando = false;

  Resultado? _resultado;
  Timer? _ocultarResultado;
  final List<Resultado> _recientes = [];

  Timer? _reloj;
  Timer? _gps;
  Timer? _adminTimer;
  DateTime _ahora = DateTime.now();

  // --- Rostro -------------------------------------------------------------
  CamaraRostro? _cam;
  StreamSubscription<LecturaRostro>? _subCam;

  /// Lo que dice el círculo de la cámara.
  String _msgRostro = 'Mírame';
  EstadoRostro _estadoRostro = EstadoRostro.buscando;

  /// Candidato reconocido y cuántas lecturas seguidas coincide.
  String? _candidato;
  int _aciertos = 0;
  double _distCandidato = 1;

  /// Prueba de vida en curso.
  DateTime? _vidaDesde;
  double _yawInicial = 0;
  bool _vioOjosAbiertos = false;

  /// Desde cuándo hay una cara enfrente que no se reconoce.
  DateTime? _sinReconocerDesde;

  /// Modo doble: cara ya confirmada, falta el dedo de esta persona.
  String? _esperaHuellaDe;
  DateTime? _esperaHuellaHasta;

  /// Quien acaba de checar con la cara no vuelve a disparar mientras sigue enfrente.
  final Map<String, DateTime> _recienRostro = {};

  late final AnimationController _pulso =
      AnimationController(vsync: this, duration: Duration(milliseconds: 1800))..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _reloj = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });
    _arrancar();
  }

  Future<void> _arrancar() async {
    final l = await LectorHuella.crear();
    try {
      await l.iniciar();
    } catch (e) {
      _errorLector = e.toString();
    }
    _lector = l;
    l.addListener(_refrescar);
    catalogo.addListener(_refrescar);
    cola.addListener(_refrescar);
    await cola.iniciar();
    await catalogo.iniciar(l);
    unawaited(_iniciarCamara());
    unawaited(_actualizarGps());
    _gps = Timer.periodic(Duration(minutes: 5), (_) => _actualizarGps());
    if (mounted) setState(() {});
    unawaited(_bucle());
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  /// El kiosco está atornillado: la ubicación sirve para detectar que alguien
  /// se lo llevó, no para validar a cada persona. Se toma cada 5 min.
  Future<void> _actualizarGps() async {
    try {
      await Ubicacion.actual(precision: LocationAccuracy.medium, limite: Duration(seconds: 25));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      unawaited(catalogo.sincronizar());
      unawaited(_cam?.reanudar());
    } else if (state == AppLifecycleState.paused) {
      // En segundo plano Android corta la cámara: se suelta para no pelearla.
      unawaited(_cam?.suspender());
    }
  }

  @override
  void dispose() {
    _vivo = false;
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _gps?.cancel();
    _adminTimer?.cancel();
    _ocultarResultado?.cancel();
    _pulso.dispose();
    _lector?.removeListener(_refrescar);
    catalogo.removeListener(_refrescar);
    cola.removeListener(_refrescar);
    _lector?.cerrar();
    _subCam?.cancel();
    _cam?.cerrar();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Bucle del lector
  // -------------------------------------------------------------------------

  Future<void> _bucle() async {
    while (_vivo) {
      final l = _lector;
      if (l == null || _pausa || _procesando) {
        await Future<void>.delayed(Duration(milliseconds: 250));
        continue;
      }
      try {
        final c = await l.identificar();
        if (!_vivo || _pausa) continue;
        _errorLector = null;
        if (c == null || !catalogo.empleados.containsKey(c.empleadoId)) {
          await _mostrarNoReconocido();
        } else {
          await _porHuella(c);
        }
      } on LectorCancelado {
        await Future<void>.delayed(Duration(milliseconds: 150));
      } catch (e) {
        _errorLector = e.toString();
        _refrescar();
        await Future<void>.delayed(Duration(seconds: 2));
      }
    }
  }

  Future<void> _mostrarNoReconocido() async {
    HapticFeedback.vibrate();
    setState(() => _noReconocido = true);
    await Future<void>.delayed(Duration(milliseconds: 1600));
    if (mounted) setState(() => _noReconocido = false);
  }

  /// Huella reconocida: según el modo de la sede, checa o completa el doble factor.
  Future<void> _porHuella(Coincidencia c) async {
    final emp = catalogo.empleados[c.empleadoId]!;
    if (catalogo.modo == 'doble' && emp.rostros.isNotEmpty && (_cam?.listo ?? false)) {
      final espera = _esperaHuellaDe;
      final vigente = _esperaHuellaHasta != null && DateTime.now().isBefore(_esperaHuellaHasta!);
      if (espera == emp.id && vigente) {
        _esperaHuellaDe = null;
        await _checar(emp.id, c.puntaje, 'rostro+huella');
      } else {
        // Doble factor: primero la cara, luego el dedo de la MISMA persona.
        setState(() {
          _msgRostro = 'Primero mírame a la cámara';
          _estadoRostro = EstadoRostro.aviso;
        });
        await _mostrarNoReconocido();
      }
      return;
    }
    await _checar(emp.id, c.puntaje, 'lector');
  }

  Future<void> _checar(String empleadoId, int puntaje, String metodo) async {
    final emp = catalogo.empleados[empleadoId]!;
    final ahora = DateTime.now();
    final pos = Ubicacion.ultima;
    final payload = <String, dynamic>{
      'cliente_id': Uuid().v4(),
      'empleado_id': emp.id,
      'ts': ahora.toUtc().toIso8601String(),
      'lat': pos?.latitude,
      'lng': pos?.longitude,
      'precision_m': pos?.accuracy,
      'gps_simulado': pos?.isMocked ?? false,
      'puntaje': puntaje,
      'metodo': metodo,
    };
    log('Checador', 'Checada ${emp.numero} por $metodo (puntaje $puntaje)');

    setState(() => _procesando = true);
    Resultado r;
    try {
      // Con red se espera poco: la fila de las 7:00 no puede esperar al servidor.
      final res = (await Api.checar([payload], limite: Duration(milliseconds: 3500))).first;
      if (res['error'] != null) throw Exception(res['error']);
      r = Resultado(
        nombre: emp.nombre,
        foto: emp.foto,
        tipo: res['tipo'] as String,
        hora: DateTime.parse(res['ts'] as String),
        estado: res['estado'] as String,
        minutosRetardo: (res['minutos_retardo'] as num?)?.toInt(),
        sede: res['sede'] as String? ?? catalogo.sedeNombre,
        distanciaM: res['distancia_m'] as num?,
        repetida: res['repetida'] == true,
      );
      cola.marcarEnLinea(true);
    } catch (e) {
      if (!esErrorDeRed(e)) {
        setState(() => _procesando = false);
        _errorLector = mensajeError(e);
        await _mostrarNoReconocido();
        return;
      }
      // Sin red: se guarda y se adivina el tipo con lo último que se checó aquí.
      await cola.agregar(payload);
      cola.marcarEnLinea(false);
      final tipo = catalogo.tipoProbable(emp.id, ahora);
      r = Resultado(
        nombre: emp.nombre,
        foto: emp.foto,
        tipo: tipo,
        hora: ahora,
        minutosRetardo: tipo == 'entrada' ? emp.turno?.retardo(ahora) : null,
        sede: catalogo.sedeNombre,
        pendiente: true,
      );
    }
    if (r.valida && !r.repetida) await catalogo.anotar(emp.id, r.hora, r.tipo);

    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
    if (!mounted) return;
    setState(() {
      _procesando = false;
      _resultado = r;
      if (!r.repetida) {
        _recientes.insert(0, r);
        if (_recientes.length > 6) _recientes.removeLast();
      }
    });
    if (metodo != 'lector') _recienRostro[emp.id] = DateTime.now();
    _reiniciarRostro();
    _ocultarResultado?.cancel();
    _ocultarResultado = Timer(Duration(milliseconds: 3800), () {
      if (mounted) setState(() => _resultado = null);
    });
  }

  // -------------------------------------------------------------------------
  // Rostro
  // -------------------------------------------------------------------------

  Future<void> _iniciarCamara() async {
    final cam = CamaraRostro();
    _cam = cam;
    cam.addListener(_refrescar);
    await cam.iniciar();
    if (!mounted) return;
    _subCam = cam.lecturas.listen(_lectura);
    setState(() {});
  }

  void _reiniciarRostro() {
    _candidato = null;
    _aciertos = 0;
    _vidaDesde = null;
    _vioOjosAbiertos = false;
    _sinReconocerDesde = null;
    _cam?.intervalo = const Duration(milliseconds: 220);
  }

  void _ponerRostro(EstadoRostro e, String msg) {
    if (_estadoRostro == e && _msgRostro == msg) return;
    if (mounted) {
      setState(() {
        _estadoRostro = e;
        _msgRostro = msg;
      });
    }
  }

  void _lectura(LecturaRostro l) {
    if (!mounted || _pausa || _procesando || _resultado != null) return;
    final ahora = DateTime.now();
    _recienRostro.removeWhere((_, t) => ahora.difference(t).inSeconds > 20);

    // Doble factor esperando el dedo.
    final espera = _esperaHuellaDe;
    if (espera != null) {
      if (_esperaHuellaHasta != null && ahora.isAfter(_esperaHuellaHasta!)) {
        _esperaHuellaDe = null;
      } else {
        _ponerRostro(EstadoRostro.huella, 'Ahora pon tu dedo en el lector');
        return;
      }
    }

    if (!l.hayCara) {
      _reiniciarRostro();
      _ponerRostro(
        EstadoRostro.buscando,
        catalogo.galeria.vacia ? 'Aún no hay caras registradas' : 'Mírame',
      );
      return;
    }

    // 1) Prueba de vida: parpadeo o giro de cabeza, con la misma persona enfrente.
    final desde = _vidaDesde;
    final cand = _candidato;
    if (desde != null && cand != null) {
      if (ahora.difference(desde).inSeconds > 6) {
        _reiniciarRostro();
        _ponerRostro(EstadoRostro.aviso, 'No detecté movimiento, intenta de nuevo');
        return;
      }
      final ojos = l.ojos;
      if (ojos != null && ojos > 0.6) _vioOjosAbiertos = true;
      final parpadeo = _vioOjosAbiertos && ojos != null && ojos < 0.25;
      final giro = (l.yaw - _yawInicial).abs() >= 14;
      if (parpadeo || giro) {
        log('Rostro', 'Vida OK (${parpadeo ? 'parpadeo' : 'giro'}) para ${cand.substring(0, 6)}');
        _confirmarRostro(cand);
      }
      return;
    }

    if (l.aviso != null) {
      _ponerRostro(EstadoRostro.aviso, l.aviso!);
      return;
    }
    final v = l.vector;
    if (v == null) return;

    if (catalogo.galeria.vacia) {
      _ponerRostro(EstadoRostro.aviso, 'Aún no hay caras registradas · usa tu huella');
      return;
    }

    // 2) ¿Quién es? Se pide la misma respuesta en 2 lecturas seguidas.
    final m = catalogo.galeria.identificar(v);
    if (m == null || !catalogo.empleados.containsKey(m.empleadoId)) {
      _candidato = null;
      _aciertos = 0;
      _sinReconocerDesde ??= ahora;
      final segundos = ahora.difference(_sinReconocerDesde!).inSeconds;
      _ponerRostro(
        EstadoRostro.aviso,
        segundos >= 3 ? 'No te reconozco · usa tu huella' : 'Reconociendo…',
      );
      return;
    }
    _sinReconocerDesde = null;
    if (_recienRostro.containsKey(m.empleadoId)) {
      _ponerRostro(EstadoRostro.listo, 'Ya quedó tu registro');
      return;
    }
    if (m.empleadoId == _candidato) {
      _aciertos++;
    } else {
      _candidato = m.empleadoId;
      _aciertos = 1;
    }
    _distCandidato = m.distancia;
    if (_aciertos >= 2) {
      _vidaDesde = ahora;
      _yawInicial = l.yaw;
      _vioOjosAbiertos = (l.ojos ?? 0) > 0.6;
      // Cuadros más seguidos para alcanzar a ver el parpadeo.
      _cam?.intervalo = const Duration(milliseconds: 90);
      final nombre = catalogo.empleados[m.empleadoId]!.nombres.split(' ').first;
      _ponerRostro(EstadoRostro.vida, 'Hola $nombre · parpadea o gira un poco la cabeza');
    } else {
      _ponerRostro(EstadoRostro.reconociendo, 'Reconociendo…');
    }
  }

  void _confirmarRostro(String empleadoId) {
    // Puntaje 0–100 a partir de la distancia (solo informativo para RH).
    final puntaje = ((1 - _distCandidato / 1.4) * 100).round().clamp(0, 100);
    _reiniciarRostro();
    if (catalogo.modo == 'doble' && (_lector != null)) {
      _esperaHuellaDe = empleadoId;
      _esperaHuellaHasta = DateTime.now().add(Duration(seconds: 10));
      HapticFeedback.mediumImpact();
      _ponerRostro(EstadoRostro.huella, 'Ahora pon tu dedo en el lector');
      return;
    }
    unawaited(_checar(empleadoId, puntaje, 'rostro'));
  }

  // -------------------------------------------------------------------------
  // Modo prueba (lector simulado)
  // -------------------------------------------------------------------------

  Future<void> _simularDedo() async {
    final l = _lector;
    if (l is! LectorSimulado || _resultado != null) return;
    final numero = await showDialog<String>(context: context, builder: (_) => _TecladoNumero());
    if (numero == null) return;
    l.tocar(catalogo.porNumero(numero)?.id ?? '-');
  }

  // -------------------------------------------------------------------------
  // Menú de administración (logo presionado 3 s)
  // -------------------------------------------------------------------------

  // ignore: unused_element
  void _adminInicio() {
    _adminTimer?.cancel();
    _adminTimer = Timer(Duration(seconds: 3), () {
      HapticFeedback.heavyImpact();
      _menuAdmin();
    });
  }

  void _adminFin() => _adminTimer?.cancel();

  Future<void> _pausar() async {
    _pausa = true;
    await _lector?.cancelar();
  }

  Future<void> _menuAdmin() async {
    final l = _lector;
    final accion = await showModalBottomSheet<String>(
      context: context,
      // Se puede deslizar: en pantallas bajas (TC51) no caben todas las
      // opciones de golpe.
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.fingerprint),
              title: Text('Registrar rostro / huella'),
              subtitle: Text('Con el código que genera RH'),
              onTap: () => Navigator.pop(ctx, 'enrolar'),
            ),
            ListTile(
              leading: Icon(Icons.sync),
              title: Text('Sincronizar ahora'),
              subtitle: Text('Última: ${haceCuanto(catalogo.ultimaSync)} · ${catalogo.empleados.length} personas'),
              onTap: () => Navigator.pop(ctx, 'sync'),
            ),
            ListTile(
              leading: Icon(Icons.cloud_upload_outlined),
              title: Text('Enviar pendientes (${cola.pendientes})'),
              onTap: () => Navigator.pop(ctx, 'cola'),
            ),
            ListTile(
              leading: Icon(Icons.usb),
              title: Text(l?.simulado ?? true ? 'Usar lector ZKTeco' : 'Usar modo prueba (sin lector)'),
              subtitle: Text('Ahora: ${l?.nombre ?? '—'}'),
              onTap: () => Navigator.pop(ctx, 'lector'),
            ),
            if (_cam != null)
              ListTile(
                leading: Icon(Icons.cameraswitch_outlined),
                title: Text(_cam!.espejo ? 'Usar cámara trasera' : 'Usar cámara frontal'),
                subtitle: Text(_cam!.hayFrontal ? 'Ahora: ${_cam!.espejo ? 'frontal' : 'trasera'}' : 'Este equipo no tiene cámara frontal'),
                onTap: () => Navigator.pop(ctx, 'camara'),
              ),
            if (_cam != null)
              ListTile(
                leading: Icon(Icons.restart_alt),
                title: Text('Reiniciar cámara'),
                subtitle: Text('Si se ve negra o no detecta caras'),
                onTap: () => Navigator.pop(ctx, 'reiniciar_cam'),
              ),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(catalogo.equipoNombre ?? 'Kiosco'),
              subtitle: Text('Equipo ${equipo.id?.substring(0, 8)} · v$kVersionApp'),
            ),
            SizedBox(height: 8.r),
          ],
        ),
        ),
      ),
    );
    if (!mounted) return;
    switch (accion) {
      case 'enrolar':
        await _pausar();
        if (!mounted || l == null) return;
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EnrolarScreen(lector: l, camara: _cam)));
        await catalogo.sincronizar();
        _pausa = false;
      case 'sync':
        await catalogo.sincronizar(completa: true);
        if (mounted) {
          avisar(context, catalogo.errorSync == null ? 'Sincronizado' : 'No se pudo: ${mensajeError(catalogo.errorSync!)}',
              error: catalogo.errorSync != null);
        }
      case 'cola':
        await cola.enviar();
      case 'reiniciar_cam':
        await CamaraRostro.olvidarGiro();
        _reiniciarRostro();
        final cam = _cam;
        if (cam != null) {
          cam.removeListener(_refrescar);
          await _subCam?.cancel();
          await cam.cerrar();
        }
        await _iniciarCamara();
        if (mounted) avisar(context, 'Cámara reiniciada');
      case 'camara':
        final cam = _cam;
        if (cam == null) return;
        await CamaraRostro.preferirFrontal(!cam.espejo);
        await _subCam?.cancel();
        cam.removeListener(_refrescar);
        await cam.cerrar();
        _reiniciarRostro();
        await _iniciarCamara();
      case 'lector':
        await LectorHuella.preferir(l?.simulado ?? true ? 'auto' : 'sim');
        await _pausar();
        l?.removeListener(_refrescar);
        await l?.cerrar();
        final nuevo = await LectorHuella.crear();
        try {
          await nuevo.iniciar();
          _errorLector = null;
        } catch (e) {
          _errorLector = e.toString();
        }
        nuevo.addListener(_refrescar);
        _lector = nuevo;
        catalogo.lector = nuevo;
        await catalogo.sincronizar(completa: true);
        _pausa = false;
        if (mounted) {
          setState(() {});
          if (nuevo.simulado && (l?.simulado ?? true)) {
            avisar(context, 'No se detectó el lector ZKTeco (o falta integrar su SDK). Sigue en modo prueba.', error: true);
          }
        }
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: Builder(builder: _ui),
    );
  }

  Widget _ui(BuildContext context) {
    final c = context.c;
    final r = _resultado;
    return Scaffold(
      backgroundColor: Brand.ink950,
      body: Stack(
        children: [
          // Brillo de marca en la esquina.
          Positioned(
            top: -220.r,
            right: -160.r,
            child: Container(
              width: 520.r,
              height: 520.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Brand.c500.withValues(alpha: 0.22), Colors.transparent]),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final horizontal = box.maxWidth > box.maxHeight && box.maxWidth > 700;
                final lado = (horizontal ? box.maxHeight * 0.5 : box.maxWidth * 0.62).clamp(180.r, 420.r);
                final cam = _cam;
                final pad = cam != null && cam.listo && cam.controlador != null
                    ? PanelRostro(
                        camara: cam,
                        lado: lado,
                        estado: _noReconocido ? EstadoRostro.error : _estadoRostro,
                        mensaje: _noReconocido ? 'No te reconocí' : _msgRostro,
                        procesando: _procesando,
                        pieHuella: _lector == null
                            ? null
                            : (_lector!.simulado ? 'Toca aquí para simular tu huella' : 'o pon tu dedo en el lector'),
                        onTapHuella: _simularDedo,
                        error: _errorLector ?? cam.ultimoError,
                      )
                    : _Pad(
                  pulso: _pulso,
                  simulado: _lector?.simulado ?? false,
                  noReconocido: _noReconocido,
                  procesando: _procesando,
                  error: _errorLector,
                  sinPersonal: catalogo.empleados.isEmpty,
                  onTap: _simularDedo,
                  lado: lado,
                  avisoCamara: cam?.error,
                );
                return Column(
                  children: [
                    _barra(context),
                    Expanded(
                      child: horizontal
                          ? Row(
                              children: [
                                Expanded(child: _relojYRecientes(context, grande: true)),
                                Expanded(child: Center(child: pad)),
                              ],
                            )
                          : Column(
                              children: [
                                SizedBox(height: 8.r),
                                _reloj2(context, grande: false),
                                Expanded(child: Center(child: pad)),
                                _recientesFila(context),
                                SizedBox(height: 12.r),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Confirmación a pantalla completa
          IgnorePointer(
            ignoring: r == null,
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 220),
              child: r == null
                  ? SizedBox.expand()
                  : GestureDetector(
                      key: ValueKey(r),
                      onTap: () => setState(() => _resultado = null),
                      child: Container(
                        color: Brand.ink950.withValues(alpha: 0.94),
                        alignment: Alignment.center,
                        padding: EdgeInsets.all(24.r),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.85, end: 1),
                          duration: Duration(milliseconds: 380),
                          curve: Curves.easeOutBack,
                          builder: (_, s, child) => Transform.scale(scale: s, child: child),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: TarjetaResultado(r: r, grande: MediaQuery.sizeOf(context).shortestSide > 600),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (catalogo.sincronizando && catalogo.empleados.isEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(color: c.ok, minHeight: 3.r),
            ),
        ],
      ),
    );
  }

  Widget _barra(BuildContext context) {
    final c = context.c;
    final l = _lector;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.r, 12.r, 4.r, 4.r),
      child: Row(
        children: [
          // Menú de administración: logo presionado (un segundo). Área de
          // toque más grande que el logo para que sea fácil de atinar.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () {
              HapticFeedback.heavyImpact();
              _menuAdmin();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.r),
              child: BrandLogo(height: 26.r, forceWhite: true),
            ),
          ),
          SizedBox(width: 10.r),
          // Sede y estados: si no caben (teléfono angosto) se encogen en vez
          // de desbordarse.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (catalogo.sedeNombre != null) ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 180.r),
                        child: Text(
                          catalogo.sedeNombre!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(width: 10.r),
                    ],
                    if (l != null && l.simulado) ...[
                      StatusChip(label: 'MODO PRUEBA', color: c.warn, icon: Icons.science_outlined),
                      SizedBox(width: 8.r),
                    ] else if (l != null && l.estado == EstadoLector.desconectado) ...[
                      StatusChip(label: 'Lector desconectado', color: c.danger, icon: Icons.usb_off),
                      SizedBox(width: 8.r),
                    ],
                    cola.enLinea
                        ? StatusChip(
                            label: cola.pendientes > 0 ? 'Enviando ${cola.pendientes}' : 'En línea',
                            color: c.ok,
                            icon: Icons.wifi,
                          )
                        : StatusChip(
                            label: cola.pendientes > 0 ? 'Sin internet · ${cola.pendientes} guardadas' : 'Sin internet',
                            color: c.warn,
                            icon: Icons.wifi_off,
                          ),
                  ],
                ),
              ),
            ),
          ),
          // Engrane discreto: también abre el menú (mantener presionado).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => avisar(context, 'Mantén presionado el engrane para abrir el menú'),
            onLongPress: () {
              HapticFeedback.heavyImpact();
              _menuAdmin();
            },
            child: Padding(
              padding: EdgeInsets.all(10.r),
              child: Icon(Icons.settings_outlined, size: 22.r, color: c.muted.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reloj2(BuildContext context, {required bool grande}) {
    final c = context.c;
    final t = _ahora;
    return Column(
      crossAxisAlignment: grande ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        // El reloj nunca se desborda: si no cabe, se encoge.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${dos(t.hour)}:${dos(t.minute)}',
              style: TextStyle(
                fontFamily: AppFont.display,
                fontSize: grande ? 120 : 76,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -4,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(width: 8.r),
            Text(
              dos(t.second),
              style: TextStyle(
                fontFamily: AppFont.display,
                fontSize: grande ? 38 : 26,
                fontWeight: FontWeight.w700,
                color: Brand.c400,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        ),
        SizedBox(height: 6.r),
        Text(
          _capital(fechaLarga(t)),
          style: TextStyle(color: c.muted, fontSize: grande ? 22 : 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _relojYRecientes(BuildContext context, {required bool grande}) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(40.r, 12.r, 12.r, 24.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Spacer(),
          _reloj2(context, grande: grande),
          Spacer(),
          if (_recientes.isNotEmpty) ...[
            Text('ÚLTIMAS CHECADAS',
                style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            SizedBox(height: 10.r),
            for (final r in _recientes.take(4))
              Padding(
                padding: EdgeInsets.only(bottom: 8.r),
                child: Row(
                  children: [
                    Avatar(nombre: r.nombre, foto: r.foto, size: 38.r),
                    SizedBox(width: 12.r),
                    Expanded(
                      child: Text(r.nombre,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      '${r.entrada ? 'Entrada' : 'Salida'} ${hhmm(r.hora)}',
                      style: TextStyle(color: r.entrada ? c.ok : Color(0xFFA5B4FC), fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _recientesFila(BuildContext context) {
    if (_recientes.isEmpty) return SizedBox(height: 56.r);
    final c = context.c;
    return SizedBox(
      height: 56.r,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.r),
        itemCount: _recientes.length,
        separatorBuilder: (_, _) => SizedBox(width: 8.r),
        itemBuilder: (_, i) {
          final r = _recientes[i];
          return Container(
            padding: EdgeInsets.fromLTRB(6.r, 6.r, 14.r, 6.r),
            decoration: BoxDecoration(color: Brand.ink800, borderRadius: BorderRadius.circular(AppRadius.pill.r)),
            child: Row(
              children: [
                Avatar(nombre: r.nombre, foto: r.foto, size: 40.r),
                SizedBox(width: 10.r),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.nombre.split(' ').first, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(
                      '${r.entrada ? 'Entrada' : 'Salida'} ${hhmm(r.hora)}',
                      style: TextStyle(color: r.entrada ? c.ok : Color(0xFFA5B4FC), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// El círculo del lector: pulsa mientras espera, se pone rojo si no reconoce.
class _Pad extends StatelessWidget {
  const _Pad({
    required this.pulso,
    required this.simulado,
    required this.noReconocido,
    required this.procesando,
    required this.error,
    required this.sinPersonal,
    required this.onTap,
    required this.lado,
    this.avisoCamara,
  });

  final String? avisoCamara;
  final Animation<double> pulso;
  final bool simulado;
  final bool noReconocido;
  final bool procesando;
  final String? error;
  final bool sinPersonal;
  final VoidCallback onTap;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = noReconocido ? c.danger : Brand.c500;
    final String texto;
    final String? sub;
    if (noReconocido) {
      texto = 'No te reconocí';
      sub = 'Limpia el dedo y vuelve a intentar';
    } else if (procesando) {
      texto = 'Un momento…';
      sub = null;
    } else if (sinPersonal) {
      texto = 'Sin personal registrado';
      sub = 'Registra rostros y huellas desde el menú (engrane ⚙︎ de arriba, mantener presionado)';
    } else {
      texto = simulado ? 'Toca para simular' : 'Coloca tu dedo';
      sub = simulado ? 'Modo prueba: teclea tu número de empleado' : 'en el lector';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: simulado ? onTap : null,
          child: SizedBox(
            width: lado,
            height: lado,
            child: AnimatedBuilder(
              animation: pulso,
              builder: (context, _) {
                final t = pulso.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ondas
                    for (final fase in [0.0, 0.5])
                      Opacity(
                        opacity: (1 - ((t + fase) % 1)) * 0.5,
                        child: Container(
                          width: lado * (0.62 + 0.38 * ((t + fase) % 1)),
                          height: lado * (0.62 + 0.38 * ((t + fase) % 1)),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
                        ),
                      ),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      width: lado * 0.62,
                      height: lado * 0.62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                        ),
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 40.r, spreadRadius: 2.r)],
                      ),
                      child: procesando
                          ? Center(child: CircularProgressIndicator(color: Colors.white))
                          : Icon(
                              noReconocido ? Icons.close_rounded : Icons.fingerprint,
                              size: lado * 0.36,
                              color: Colors.white,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        SizedBox(height: 18.r),
        Text(
          texto,
          style: TextStyle(fontFamily: AppFont.display, fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        if (sub != null) Text(sub, style: TextStyle(color: c.muted, fontSize: 15)),
        if (error != null && !noReconocido)
          Padding(
            padding: EdgeInsets.only(top: 10.r),
            child: StatusChip(label: error!, color: c.danger, icon: Icons.error_outline),
          ),
        if (avisoCamara != null)
          Padding(
            padding: EdgeInsets.only(top: 10.r),
            child: StatusChip(label: 'Rostro apagado: $avisoCamara', color: c.warn, icon: Icons.no_photography_outlined),
          ),
      ],
    );
  }
}

/// Teclado grande para el modo prueba (el número de empleado hace de dedo).
class _TecladoNumero extends StatefulWidget {
  const _TecladoNumero();

  @override
  State<_TecladoNumero> createState() => _TecladoNumeroState();
}

class _TecladoNumeroState extends State<_TecladoNumero> {
  String _v = '';

  @override
  Widget build(BuildContext context) {
    Widget tecla(String t, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: EdgeInsets.all(5.r),
          child: SizedBox(
            width: 72.r,
            height: 60.r,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))),
              onPressed: onTap ?? () => setState(() => _v = (_v + t).length > 10 ? _v : _v + t),
              child: icon != null ? Icon(icon) : Text(t, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
        );

    return AlertDialog(
      title: Text('Número de empleado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _v.isEmpty ? '—' : _v,
            style: TextStyle(fontFamily: AppFont.display, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4),
          ),
          SizedBox(height: 12.r),
          for (final fila in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [for (final t in fila) tecla(t)]),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tecla('', icon: Icons.backspace_outlined, onTap: () {
                if (_v.isNotEmpty) setState(() => _v = _v.substring(0, _v.length - 1));
              }),
              tecla('0'),
              tecla('', icon: Icons.check, onTap: () => Navigator.pop(context, _v)),
            ],
          ),
        ],
      ),
    );
  }
}
