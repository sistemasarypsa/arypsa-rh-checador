import 'package:flutter_test/flutter_test.dart';

import 'package:arypsa_rh/datos.dart';
import 'package:arypsa_rh/mx.dart';

void main() {
  test('Turno describe sus días', () {
    final t = Turno(nombre: 'Matutino', entrada: '07:00', salida: '17:00');
    expect(t.diasTexto, 'Lunes a viernes');
  });

  test('CURP: dígito verificador y datos', () {
    expect(validarCurp('GODE561231HDFRRN00'), isNull);
    expect(validarCurp('GODE561231HDFRRN01'), isNotNull);
    expect(validarCurp('GODE561331HDFRRN00'), isNotNull); // mes 13
    final d = datosDeCurp('GODE561231HDFRRN00')!;
    expect(d.nacimiento, DateTime(1956, 12, 31));
    expect(d.sexo, 'H');
    expect(d.entidad, 'Ciudad de México');
  });

  test('RFC coincide con la CURP', () {
    expect(validarRfc('GODE561231AB1', curp: 'GODE561231HDFRRN00'), isNull);
    expect(validarRfc('GODX561231AB1', curp: 'GODE561231HDFRRN00'), isNotNull);
  });

  test('NSS y CLABE', () {
    expect(validarNss('12345678903'), isNull);
    expect(validarNss('12345678901'), isNotNull);
    expect(validarClabe('032180000118359719'), isNull);
    expect(validarClabe('032180000118359710'), isNotNull);
    expect(bancoDeClabe('012180001234567891'), 'BBVA México');
  });

  test('Vacaciones de ley (LFT art. 76)', () {
    expect([1, 2, 3, 4, 5, 6, 10, 11, 16, 21].map(diasVacaciones).toList(), [12, 14, 16, 18, 20, 22, 22, 24, 26, 28]);
    expect(factorIntegracion(DateTime.now().subtract(Duration(days: 30))), closeTo(1.0493, 0.0001));
  });
}
