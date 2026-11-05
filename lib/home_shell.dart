import 'package:flutter/material.dart';

import 'empleados_screen.dart';
import 'equipos_screen.dart';
import 'hoy_screen.dart';
import 'responsive.dart';
import 'sedes_screen.dart';
import 'theme.dart';

/// Teléfono: barra de navegación abajo. Tablet o pantalla ancha: riel a la
/// izquierda y el contenido centrado con ancho máximo (no se estira).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Destino {
  const _Destino(this.icono, this.activo, this.texto);

  final IconData icono;
  final IconData activo;
  final String texto;
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pantallas = <Widget>[
    HoyScreen(),
    EmpleadosScreen(),
    SedesScreen(),
    EquiposScreen(),
  ];

  static const _destinos = [
    _Destino(Icons.today_outlined, Icons.today, 'Hoy'),
    _Destino(Icons.badge_outlined, Icons.badge, 'Personal'),
    _Destino(Icons.place_outlined, Icons.place, 'Sedes'),
    _Destino(Icons.devices_other_outlined, Icons.devices_other, 'Equipos'),
  ];

  @override
  Widget build(BuildContext context) {
    final r = context.resp;
    final contenido = IndexedStack(index: _tab, children: _pantallas);

    if (r.compacto) {
      return Scaffold(
        body: contenido,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final d in _destinos)
              NavigationDestination(icon: Icon(d.icono), selectedIcon: Icon(d.activo), label: d.texto),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.85,
              leading: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.r),
                child: Image.asset('assets/img/arypsa-mark.png', width: 36.r, height: 36.r),
              ),
              destinations: [
                for (final d in _destinos)
                  NavigationRailDestination(icon: Icon(d.icono), selectedIcon: Icon(d.activo), label: Text(d.texto)),
              ],
            ),
            VerticalDivider(width: 1, color: context.c.border),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: r.expandido ? 1100.r : double.infinity),
                  child: contenido,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
