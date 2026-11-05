import 'package:flutter/material.dart';

import 'config.dart';
import 'datos.dart';
import 'theme.dart';
import 'ui.dart';
import 'responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Al entrar, la sesión cambia y esta pantalla se reconstruye desde cero;
  /// si luego se rechaza la cuenta, el mensaje viaja por aquí.
  static final aviso = ValueNotifier<String?>(null);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _correo = TextEditingController();
  final _pass = TextEditingController();
  bool _ocultar = true;
  bool _cargando = false;

  @override
  void dispose() {
    _correo.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    if (_correo.text.trim().isEmpty || _pass.text.isEmpty) {
      LoginScreen.aviso.value = 'Escribe tu correo y contraseña.';
      return;
    }
    LoginScreen.aviso.value = null;
    setState(() => _cargando = true);
    try {
      log('ArypsaRH', 'Login: ${_correo.text.trim()}');
      await sb.auth.signInWithPassword(email: _correo.text.trim(), password: _pass.text);
      log('ArypsaRH', 'Login OK, revisando perfil de RH');
      // Una cuenta de Supabase sin perfil de RH no entra.
      final esRh = await sb.rpc('rh_es_rh') as bool? ?? false;
      log('ArypsaRH', 'rh_es_rh() = $esRh');
      if (!esRh) {
        await sb.auth.signOut();
        throw Exception('sin_permiso');
      }
    } catch (e) {
      log('ArypsaRH', 'Login ERROR: $e');
      LoginScreen.aviso.value = mensajeError(e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: Stack(
        children: [
          // Banda roja de marca arriba, como la portada del portal.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).height * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Brand.c500, Brand.c700],
                ),
              ),
              child: CustomPaint(painter: _HuellaFondo()),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20.r),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 420.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: BrandLogo(height: 34.r, forceWhite: true)),
                      SizedBox(height: 10.r),
                      Text(
                        'Recursos Humanos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: AppFont.display,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
                      ),
                      SizedBox(height: 28.r),
                      Panel(
                        padding: EdgeInsets.fromLTRB(22.r, 26.r, 22.r, 22.r),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Entrar',
                                style: TextStyle(
                                  fontFamily: AppFont.display,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 4.r),
                              Text(
                                'Alta de personal y control del reloj checador.',
                                style: TextStyle(color: c.muted),
                              ),
                              SizedBox(height: 22.r),
                              TextField(
                                controller: _correo,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Correo',
                                  prefixIcon: Icon(Icons.alternate_email),
                                ),
                              ),
                              SizedBox(height: 12.r),
                              TextField(
                                controller: _pass,
                                obscureText: _ocultar,
                                autofillHints: [AutofillHints.password],
                                onSubmitted: (_) => _entrar(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => _ocultar = !_ocultar),
                                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                ),
                              ),
                              ValueListenableBuilder<String?>(
                                valueListenable: LoginScreen.aviso,
                                builder: (context, error, _) => error == null
                                    ? SizedBox.shrink()
                                    : Padding(
                                        padding: EdgeInsets.only(top: 14.r),
                                        child: Text(
                                          error,
                                          style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                              ),
                              SizedBox(height: 22.r),
                              FilledButton(
                                onPressed: _cargando ? null : _entrar,
                                child: _cargando
                                    ? SizedBox(
                                        width: 22.r,
                                        height: 22.r,
                                        child: CircularProgressIndicator(strokeWidth: 2.4.r, color: Colors.white),
                                      )
                                    : Text('Entrar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 18.r),
                      Text(
                        'Las cuentas las crea Sistemas. Si olvidaste tu contraseña, pídela a sistemas@arypsa.com.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Crestas de huella dibujadas, muy tenues, sobre la banda roja.
class _HuellaFondo extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.07);
    final centro = Offset(size.width * 0.85, size.height * 0.15);
    for (var i = 1; i < 18; i++) {
      final r = i * 18.0;
      canvas.drawArc(Rect.fromCircle(center: centro, radius: r), 0.4 + i * 0.05, 4.6 - i * 0.04, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
