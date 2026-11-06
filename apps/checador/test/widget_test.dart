import 'package:flutter_test/flutter_test.dart';

import 'package:arypsa_checador/catalogo.dart';

void main() {
  test('Retardo contra el turno', () {
    final t = TurnoLocal(entrada: '07:00', tolerancia: 10, dias: [1, 2, 3, 4, 5, 6, 7]);
    final hoy = DateTime.now();
    expect(t.retardo(DateTime(hoy.year, hoy.month, hoy.day, 7, 9)), isNull);
    expect(t.retardo(DateTime(hoy.year, hoy.month, hoy.day, 7, 15)), 15);
  });
}
