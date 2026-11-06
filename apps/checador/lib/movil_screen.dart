import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'cola.dart';
import 'equipo.dart';
import 'resultado.dart';
import 'theme.dart';
import 'ui.dart';
import 'ubicacion.dart';
import 'responsive.dart';

/// Celular de un administrativo: un botón grande que solo se habilita dentro
/// de la geocerca de una sede, y que pide la huella / Face ID del teléfono.
class MovilScreen extends StatefulWidget {
  const MovilScreen({super.key});

  @override
  State<MovilScreen> createState() => _MovilScreenState();
}

class _MovilScreenState extends State<MovilScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _empleado;
  List<Sitio> _sitios = const [];
  List<Map<String, dynamic>> _hoy = const [];
  String? _errorEstado;

  Position? _pos;
  Geocerca? _geo;
  String? _errorGps;
  bool _abrirAjustes = false;
  bool _ubicando = false;

  bool _checando = false;
  Timer? _reloj;
  Timer? _gpsTimer;
  DateTime _ahora = DateTime.now();
  StreamSubscription<Map<String, dynamic>>? _subCola;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reloj = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });
    // Mientras la pantalla está abierta, la ubicación se refresca cada 20 s.
    _gpsTimer = Timer.periodic(Duration(seconds: 20), (_) => _ubicar(silencioso: true));
    cola.addListener(_refrescar);
    _subCola = cola.resultados.listen((_) => _cargarEstado());
    cola.iniciar();
    _cargarEstado();
    _ubicar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _gpsTimer?.cancel();
    _subCola?.cancel();
    cola.removeListener(_refrescar);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cargarEstado();
      _ubicar();
      cola.enviar();
    }
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  Future<void> _cargarEstado() async {
    try {
      final r = await Api.movilEstado();
      if (!mounted) return;
      setState(() {
        _empleado = Map<String, dynamic>.from(r['empleado'] as Map);
        _sitios = [for (final s in (r['sedes'] as List)) Sitio.fromJson(Map<String, dynamic>.from(s as Map))];
        _hoy = [for (final c in (r['hoy'] as List)) Map<String, dynamic>.from(c as Map)];
        _errorEstado = null;
        if (_pos != null) _geo = Geocerca.evaluar(_pos!, _sitios);
      });
      cola.marcarEnLinea(true);
    } catch (e) {
      if (!mounted) return;
      if (esErrorDeRed(e)) cola.marcarEnLinea(false);
      setState(() => _errorEstado = mensajeError(e));
    }
  }

  Future<void> _ubicar({bool silencioso = false}) async {
    if (_ubicando || _checando) return;
    if (!silencioso) setState(() => _ubicando = true);
    try {
      final p = await Ubicacion.actual(limite: Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _pos = p;
        _geo = Geocerca.evaluar(p, _sitios);
        _errorGps = null;
        _abrirAjustes = false;
      });
    } on UbicacionError catch (e) {
      if (mounted) {
        setState(() {
          _errorGps = e.mensaje;
          _abrirAjustes = e.abrirAjustes;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorGps = 'No se pudo leer la ubicación.');
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  /// Lo que toca checar ahora, según lo válido de hoy.
  String get _siguiente {
    final validas = _hoy.where((c) => c['estado'] == 'valida').toList();
    if (validas.isEmpty) return 'entrada';
    return validas.last['tipo'] == 'entrada' ? 'salida' : 'entrada';
  }

  Future<void> _checar() async {
    if (_checando) return;
    setState(() => _checando = true);
    try {
      // 1. Huella / Face ID del propio teléfono.
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Confirma tu ${_siguiente == 'entrada' ? 'entrada' : 'salida'}',
        options: AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!ok) return;

      // 2. Ubicación fresca y precisa en el momento de checar.
      final p = await Ubicacion.actual(limite: Duration(seconds: 15), vigencia: Duration(seconds: 45));
      final geo = Geocerca.evaluar(p, _sitios);
      if (mounted) {
        setState(() {
          _pos = p;
          _geo = geo;
        });
      }
      if (geo == null || !geo.dentro) {
        HapticFeedback.vibrate();
        if (mounted) {
          avisar(
            context,
            geo == null
                ? 'No hay sedes configuradas.'
                : 'Estás a ${metros(geo.distancia)} de ${geo.sitio.nombre}. Solo se puede checar dentro de la sede.',
            error: true,
          );
        }
        return;
      }

      // 3. Envío (o a la cola si no hay red).
      final ahora = DateTime.now();
      final payload = <String, dynamic>{
        'cliente_id': Uuid().v4(),
        'ts': ahora.toUtc().toIso8601String(),
        'lat': p.latitude,
        'lng': p.longitude,
        'precision_m': p.accuracy,
        'gps_simulado': p.isMocked,
      };
      final nombre = '${_empleado?['nombres'] ?? ''} ${_empleado?['apellidos'] ?? ''}'.trim();
      Resultado r;
      try {
        final res = (await Api.checar([payload], limite: Duration(seconds: 8))).first;
        if (res['error'] != null) throw Exception(res['error']);
        r = Resultado(
          nombre: nombre,
          foto: _empleado?['foto'] as String?,
          tipo: res['tipo'] as String,
          hora: DateTime.parse(res['ts'] as String),
          estado: res['estado'] as String,
          minutosRetardo: (res['minutos_retardo'] as num?)?.toInt(),
          sede: res['sede'] as String?,
          distanciaM: res['distancia_m'] as num?,
          repetida: res['repetida'] == true,
        );
      } catch (e) {
        if (!esErrorDeRed(e)) rethrow;
        await cola.agregar(payload);
        cola.marcarEnLinea(false);
        r = Resultado(
          nombre: nombre,
          foto: _empleado?['foto'] as String?,
          tipo: _siguiente,
          hora: ahora,
          sede: geo.sitio.nombre,
          pendiente: true,
        );
        // Se refleja en la lista de hoy mientras llega.
        _hoy = [..._hoy, {'tipo': _siguiente, 'ts': payload['ts'], 'estado': 'valida', 'sede': geo.sitio.nombre, 'pendiente': true}];
      }

      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(24.r, 0, 24.r, 32.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TarjetaResultado(r: r),
              SizedBox(height: 24.r),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(ctx), child: Text('Listo')),
              ),
            ],
          ),
        ),
      );
      if (!r.pendiente) await _cargarEstado();
    } on UbicacionError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
      if (e.abrirAjustes) await Ubicacion.abrirAjustes();
    } on PlatformException catch (e) {
      // local_auth: sin biometría, bloqueada por intentos, etc.
      if (mounted) avisar(context, 'Biometría no disponible: ${e.message ?? e.code}', error: true);
    } catch (e) {
      if (mounted) avisar(context, mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _checando = false);
    }
  }

  Future<void> _menu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(ctx.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              title: Text(ctx.isDark ? 'Tema claro' : 'Tema oscuro'),
              onTap: () => Navigator.pop(ctx, 'tema'),
            ),
            if (cola.pendientes > 0)
              ListTile(
                leading: Icon(Icons.cloud_upload_outlined),
                title: Text('Enviar ${cola.pendientes} pendientes'),
                onTap: () => Navigator.pop(ctx, 'cola'),
              ),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Arypsa Checador'),
              subtitle: Text('v$kVersionApp · equipo ${equipo.id?.substring(0, 8)}'),
            ),
            ListTile(
              leading: Icon(Icons.link_off, color: ctx.c.danger),
              title: Text('Desvincular este celular', style: TextStyle(color: ctx.c.danger)),
              onTap: () => Navigator.pop(ctx, 'salir'),
            ),
            SizedBox(height: 8.r),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (v == 'tema') await themeController.toggle();
    if (v == 'cola') await cola.enviar();
    if (v == 'salir' &&
        await confirmar(
          context,
          titulo: 'Desvincular',
          mensaje: 'Para volver a checar desde este teléfono, RH tendrá que darte un código nuevo.',
          si: 'Desvincular',
          peligro: true,
        )) {
      await equipo.olvidar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final emp = _empleado;
    final nombre = emp == null ? '' : '${emp['nombres']} ${emp['apellidos'] ?? ''}'.trim();
    final geo = _geo;
    final dentro = geo?.dentro ?? false;
    final siguiente = _siguiente;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: BrandLogo(height: 22.r),
        actions: [
          if (cola.pendientes > 0)
            Padding(
              padding: EdgeInsets.only(right: 4.r),
              child: StatusChip(label: '${cola.pendientes}', color: c.warn, icon: Icons.cloud_upload_outlined),
            ),
          IconButton(onPressed: _menu, icon: Icon(Icons.more_vert)),
          SizedBox(width: 4.r),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_cargarEstado(), _ubicar()]);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.resp.margen, 4.r, context.resp.margen, 32.r),
          children: [
            // Quién
            Row(
              children: [
                Avatar(nombre: nombre.isEmpty ? '?' : nombre, foto: emp?['foto'] as String?, size: 48.r),
                SizedBox(width: 12.r),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emp == null ? 'Cargando…' : 'Hola, ${emp['nombres']}',
                        style: TextStyle(fontFamily: AppFont.display, fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        emp == null ? '' : '#${emp['numero']}${emp['puesto'] != null ? ' · ${emp['puesto']}' : ''}',
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_errorEstado != null && emp == null) ...[
              SizedBox(height: 12.r),
              StatusChip(label: _errorEstado!, color: c.danger, icon: Icons.cloud_off),
            ],
            SizedBox(height: 28.r),

            // Reloj
            Center(
              child: Text(
                '${dos(_ahora.hour)}:${dos(_ahora.minute)}',
                style: TextStyle(
                  fontFamily: AppFont.display,
                  fontSize: 72,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Center(child: Text(fechaLarga(_ahora), style: TextStyle(color: c.muted, fontWeight: FontWeight.w600))),
            SizedBox(height: 22.r),

            // Ubicación
            _TarjetaUbicacion(
              geo: geo,
              ubicando: _ubicando,
              error: _errorGps,
              sinSedes: emp != null && _sitios.isEmpty,
              onReintentar: () async {
                if (_abrirAjustes) await Ubicacion.abrirAjustes();
                await _ubicar();
              },
            ),
            SizedBox(height: 26.r),

            // Botón
            Center(
              child: _BotonChecar(
                tipo: siguiente,
                habilitado: dentro && emp != null && !_checando,
                cargando: _checando,
                onTap: _checar,
              ),
            ),
            SizedBox(height: 10.r),
            Center(
              child: Text(
                dentro ? 'Se te pedirá tu huella o Face ID' : 'Acércate a la sede para habilitar el botón',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ),

            // Hoy
            SectionTitle('Hoy'),
            if (_hoy.isEmpty)
              Panel(child: Text('Aún no checas hoy.', style: TextStyle(color: c.muted)))
            else
              Panel(
                padding: EdgeInsets.symmetric(vertical: 6.r),
                child: Column(
                  children: [
                    for (final ch in _hoy) _FilaHoy(ch: ch),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaUbicacion extends StatelessWidget {
  const _TarjetaUbicacion({
    required this.geo,
    required this.ubicando,
    required this.error,
    required this.sinSedes,
    required this.onReintentar,
  });

  final Geocerca? geo;
  final bool ubicando;
  final String? error;
  final bool sinSedes;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final g = geo;

    final Color color;
    final IconData icon;
    final String titulo;
    final String sub;

    if (error != null) {
      color = c.danger;
      icon = Icons.location_disabled;
      titulo = 'Sin ubicación';
      sub = error!;
    } else if (sinSedes) {
      color = c.warn;
      icon = Icons.wrong_location_outlined;
      titulo = 'No hay sedes configuradas';
      sub = 'Pide a RH que dé de alta la geocerca.';
    } else if (g == null) {
      color = c.muted;
      icon = Icons.location_searching;
      titulo = 'Buscando ubicación…';
      sub = 'Asegúrate de tener el GPS encendido.';
    } else if (g.dentro) {
      color = c.ok;
      icon = Icons.where_to_vote;
      titulo = 'Estás en ${g.sitio.nombre}';
      sub = 'A ${metros(g.distancia)} del centro · precisión ±${metros(g.precision)}';
    } else {
      color = c.danger;
      icon = Icons.wrong_location;
      titulo = 'Fuera de la sede';
      sub = 'A ${metros(g.distancia)} de ${g.sitio.nombre} (máx. ${metros(g.sitio.radioM)})';
    }

    return Panel(
      color: color.withValues(alpha: context.isDark ? 0.14 : 0.08),
      onTap: onReintentar,
      child: Row(
        children: [
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: ubicando
                ? Padding(padding: EdgeInsets.all(12.r), child: CircularProgressIndicator(strokeWidth: 2.4.r, color: color))
                : Icon(icon, color: color),
          ),
          SizedBox(width: 14.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
                SizedBox(height: 2),
                Text(sub, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3)),
              ],
            ),
          ),
          Icon(Icons.refresh, color: c.muted, size: 20.r),
        ],
      ),
    );
  }
}

class _BotonChecar extends StatelessWidget {
  const _BotonChecar({required this.tipo, required this.habilitado, required this.cargando, required this.onTap});

  final String tipo;
  final bool habilitado;
  final bool cargando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entrada = tipo == 'entrada';
    final base = entrada ? Brand.c500 : Color(0xFF4F46E5);
    final color = habilitado ? base : c.muted.withValues(alpha: 0.35);

    return GestureDetector(
      onTap: habilitado ? onTap : null,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 250),
        width: 210.r,
        height: 210.r,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.3)!],
          ),
          boxShadow: habilitado ? [BoxShadow(color: base.withValues(alpha: 0.40), blurRadius: 36.r, offset: Offset(0, 14.r))] : null,
        ),
        child: cargando
            ? Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fingerprint, color: Colors.white, size: 64.r),
                  SizedBox(height: 6.r),
                  Text('CHECAR', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 2)),
                  Text(
                    entrada ? 'ENTRADA' : 'SALIDA',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: AppFont.display,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FilaHoy extends StatelessWidget {
  const _FilaHoy({required this.ch});

  final Map<String, dynamic> ch;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entrada = ch['tipo'] == 'entrada';
    final estado = ch['estado'] as String? ?? 'valida';
    final ts = DateTime.parse(ch['ts'] as String);
    final ret = (ch['minutos_retardo'] as num?)?.toInt() ?? 0;

    Widget? chip;
    if (ch['pendiente'] == true) {
      chip = StatusChip(label: 'Por enviar', color: c.warn, icon: Icons.cloud_upload_outlined);
    } else if (estado == 'fuera_geocerca') {
      chip = StatusChip(label: 'Fuera de sede', color: c.danger);
    } else if (estado == 'revisar') {
      chip = StatusChip(label: 'En revisión', color: c.info);
    } else if (estado == 'anulada') {
      chip = StatusChip(label: 'Anulada', color: c.muted);
    } else if (ret > 0) {
      chip = StatusChip(label: 'Retardo $ret min', color: c.warn);
    }

    return ListTile(
      leading: Icon(entrada ? Icons.login_rounded : Icons.logout_rounded, color: entrada ? c.ok : Color(0xFF6366F1)),
      title: Text(
        '${entrada ? 'Entrada' : 'Salida'} · ${hhmm(ts)}',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: ch['sede'] == null ? null : Text(ch['sede'] as String, style: TextStyle(color: c.muted, fontSize: 12.5)),
      trailing: chip,
    );
  }
}
