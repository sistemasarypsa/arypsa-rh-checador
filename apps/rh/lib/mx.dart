/// Validaciones y catálogos de México para el expediente: CURP, RFC, NSS,
/// CLABE, entidades, bancos, vacaciones de ley y factor de integración.
library;

// ---------------------------------------------------------------------------
// CURP
// ---------------------------------------------------------------------------

final _curpRe = RegExp(r'^[A-Z][AEIOUX][A-Z]{2}[0-9]{6}[HMX][A-Z]{5}[0-9A-Z][0-9]$');
const _curpDic = '0123456789ABCDEFGHIJKLMNÑOPQRSTUVWXYZ';

/// null = válida. Revisa formato, fecha y dígito verificador.
String? validarCurp(String? v, {bool obligatoria = false}) {
  final s = (v ?? '').trim().toUpperCase();
  if (s.isEmpty) return obligatoria ? 'Obligatoria' : null;
  if (s.length != 18) return 'Son 18 caracteres (lleva ${s.length})';
  if (!_curpRe.hasMatch(s)) return 'Formato no válido';
  if (datosDeCurp(s) == null) return 'La fecha de nacimiento no existe';
  var suma = 0;
  for (var i = 0; i < 17; i++) {
    final val = _curpDic.indexOf(s[i]);
    if (val < 0) return 'Caracter no válido';
    suma += val * (18 - i);
  }
  final dv = (10 - suma % 10) % 10;
  if (dv.toString() != s[17]) return 'El dígito verificador no cuadra: revisa la CURP';
  return null;
}

class DatosCurp {
  DatosCurp(this.nacimiento, this.sexo, this.entidad);
  final DateTime nacimiento;

  /// 'H' | 'M' | 'X'
  final String sexo;

  /// Nombre de la entidad de nacimiento (o "Nacido en el extranjero").
  final String? entidad;
}

/// Saca fecha de nacimiento, sexo y entidad de una CURP con formato válido.
DatosCurp? datosDeCurp(String curp) {
  final s = curp.trim().toUpperCase();
  if (s.length < 13) return null;
  final yy = int.tryParse(s.substring(4, 6));
  final mm = int.tryParse(s.substring(6, 8));
  final dd = int.tryParse(s.substring(8, 10));
  if (yy == null || mm == null || dd == null) return null;
  // Posición 17: dígito = nacido antes de 2000; letra = 2000 en adelante.
  final siglo = s.length >= 17 && RegExp(r'[A-Z]').hasMatch(s[16]) ? 2000 : 1900;
  final f = DateTime(siglo + yy, mm, dd);
  if (f.month != mm || f.day != dd) return null;
  return DatosCurp(f, s[10], entidadesCurp[s.substring(11, 13)]);
}

const entidadesCurp = {
  'AS': 'Aguascalientes', 'BC': 'Baja California', 'BS': 'Baja California Sur', 'CC': 'Campeche',
  'CL': 'Coahuila', 'CM': 'Colima', 'CS': 'Chiapas', 'CH': 'Chihuahua', 'DF': 'Ciudad de México',
  'DG': 'Durango', 'GT': 'Guanajuato', 'GR': 'Guerrero', 'HG': 'Hidalgo', 'JC': 'Jalisco',
  'MC': 'Estado de México', 'MN': 'Michoacán', 'MS': 'Morelos', 'NT': 'Nayarit', 'NL': 'Nuevo León',
  'OC': 'Oaxaca', 'PL': 'Puebla', 'QT': 'Querétaro', 'QR': 'Quintana Roo', 'SP': 'San Luis Potosí',
  'SL': 'Sinaloa', 'SR': 'Sonora', 'TC': 'Tabasco', 'TS': 'Tamaulipas', 'TL': 'Tlaxcala',
  'VZ': 'Veracruz', 'YN': 'Yucatán', 'ZS': 'Zacatecas', 'NE': 'Nacido en el extranjero',
};

List<String> get entidades => entidadesCurp.values.where((e) => !e.startsWith('Nacido')).toList()..sort();

// ---------------------------------------------------------------------------
// RFC (persona física: 13 caracteres)
// ---------------------------------------------------------------------------

final _rfcRe = RegExp(r'^[A-ZÑ&]{4}[0-9]{6}[A-Z0-9]{3}$');

String? validarRfc(String? v, {String? curp}) {
  final s = (v ?? '').trim().toUpperCase();
  if (s.isEmpty) return null;
  if (s.length != 13) return 'Son 13 caracteres (lleva ${s.length})';
  if (!_rfcRe.hasMatch(s)) return 'Formato no válido';
  final c = (curp ?? '').trim().toUpperCase();
  if (c.length >= 10 && s.substring(0, 10) != c.substring(0, 10)) {
    return 'Los primeros 10 caracteres deberían coincidir con la CURP (${c.substring(0, 10)})';
  }
  return null;
}

// ---------------------------------------------------------------------------
// NSS (IMSS): 11 dígitos, el último es verificador (Luhn)
// ---------------------------------------------------------------------------

String? validarNss(String? v) {
  final s = (v ?? '').replaceAll(RegExp(r'\D'), '');
  if (s.isEmpty) return null;
  if (s.length != 11) return 'Son 11 dígitos (lleva ${s.length})';
  var suma = 0;
  for (var i = 0; i < 10; i++) {
    var d = int.parse(s[i]) * (i.isEven ? 1 : 2);
    if (d > 9) d -= 9;
    suma += d;
  }
  final dv = (10 - suma % 10) % 10;
  if (dv != int.parse(s[10])) return 'El dígito verificador no cuadra: revisa el NSS';
  return null;
}

// ---------------------------------------------------------------------------
// CLABE: 18 dígitos, banco en los primeros 3, verificador con pesos 3-7-1
// ---------------------------------------------------------------------------

String? validarClabe(String? v) {
  final s = (v ?? '').replaceAll(RegExp(r'\D'), '');
  if (s.isEmpty) return null;
  if (s.length != 18) return 'Son 18 dígitos (lleva ${s.length})';
  const pesos = [3, 7, 1];
  var suma = 0;
  for (var i = 0; i < 17; i++) {
    suma += (int.parse(s[i]) * pesos[i % 3]) % 10;
  }
  final dv = (10 - suma % 10) % 10;
  if (dv != int.parse(s[17])) return 'El dígito verificador no cuadra: revisa la CLABE';
  return null;
}

/// Banco según los 3 primeros dígitos de la CLABE.
String? bancoDeClabe(String clabe) {
  final s = clabe.replaceAll(RegExp(r'\D'), '');
  if (s.length < 3) return null;
  return bancos[s.substring(0, 3)];
}

const bancos = {
  '002': 'Banamex', '006': 'Bancomext', '009': 'Banobras', '012': 'BBVA México', '014': 'Santander',
  '019': 'Banjército', '021': 'HSBC', '030': 'BanBajío', '036': 'Inbursa', '042': 'Mifel',
  '044': 'Scotiabank', '058': 'Banregio', '059': 'Invex', '060': 'Bansi', '062': 'Afirme',
  '072': 'Banorte', '106': 'Bank of America', '113': 'Ve por Más', '127': 'Banco Azteca',
  '128': 'Autofin', '130': 'Compartamos', '132': 'Multiva', '133': 'Actinver', '136': 'Intercam',
  '137': 'BanCoppel', '140': 'Consubanco', '145': 'Bbase', '147': 'Bankaool', '152': 'Bancrea',
  '166': 'Banco del Bienestar', '638': 'Nu México', '646': 'STP', '722': 'Mercado Pago',
};

// ---------------------------------------------------------------------------
// Otros
// ---------------------------------------------------------------------------

String? validarCp(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return null;
  return RegExp(r'^\d{5}$').hasMatch(s) ? null : 'Son 5 dígitos';
}

String? validarTelefono(String? v) {
  final s = (v ?? '').replaceAll(RegExp(r'[\s\-()+]'), '');
  if (s.isEmpty) return null;
  return RegExp(r'^\d{10,13}$').hasMatch(s) ? null : '10 dígitos';
}

String? validarCorreo(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return null;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Correo no válido';
}

/// Años cumplidos entre dos fechas.
int aniosEntre(DateTime desde, DateTime hasta) {
  var a = hasta.year - desde.year;
  if (hasta.month < desde.month || (hasta.month == desde.month && hasta.day < desde.day)) a--;
  return a;
}

/// "3 años 2 meses", "8 meses", "12 días".
String antiguedadTexto(DateTime ingreso, [DateTime? hoy]) {
  final h = hoy ?? DateTime.now();
  var meses = (h.year - ingreso.year) * 12 + h.month - ingreso.month;
  if (h.day < ingreso.day) meses--;
  if (meses < 0) return 'Ingresa ${ingreso.day}/${ingreso.month}/${ingreso.year}';
  if (meses == 0) return '${h.difference(ingreso).inDays} días';
  final a = meses ~/ 12, m = meses % 12;
  return [if (a > 0) '$a ${a == 1 ? 'año' : 'años'}', if (m > 0) '$m ${m == 1 ? 'mes' : 'meses'}'].join(' ');
}

/// Días de vacaciones por el año de servicio que se está cumpliendo
/// (LFT art. 76, reforma "vacaciones dignas" vigente desde 2023).
/// [anio] = 1 para el primer año cumplido.
int diasVacaciones(int anio) {
  if (anio <= 0) return 0;
  if (anio <= 5) return 10 + anio * 2; // 12, 14, 16, 18, 20
  return 22 + ((anio - 6) ~/ 5) * 2; // 6-10: 22, 11-15: 24, 16-20: 26…
}

/// Factor de integración mínimo de ley para el SDI: aguinaldo de 15 días y
/// prima vacacional del 25 % sobre las vacaciones del año que corre.
double factorIntegracion(DateTime? ingreso, [DateTime? hoy]) {
  final h = hoy ?? DateTime.now();
  final anio = ingreso == null ? 1 : aniosEntre(ingreso, h) + 1;
  return 1 + (15 + diasVacaciones(anio) * 0.25) / 365;
}

String dineroMx(num? v) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(2);
  final partes = s.split('.');
  final ent = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '\$$ent.${partes[1]}';
}

// Catálogos para los menús del formulario ------------------------------------

const estadosCiviles = ['Soltero(a)', 'Casado(a)', 'Unión libre', 'Divorciado(a)', 'Viudo(a)'];
const escolaridades = [
  'Primaria', 'Secundaria', 'Bachillerato / Preparatoria', 'Carrera técnica', 'Licenciatura / Ingeniería',
  'Maestría', 'Doctorado',
];
const tiposSangre = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];
const parentescos = [
  'Esposo(a)', 'Concubino(a)', 'Hijo(a)', 'Padre', 'Madre', 'Hermano(a)', 'Abuelo(a)', 'Tío(a)', 'Amigo(a)', 'Otro',
];

const tiposContrato = {
  'indeterminado': 'Tiempo indeterminado',
  'determinado': 'Tiempo determinado',
  'prueba': 'Periodo de prueba',
  'capacitacion': 'Capacitación inicial',
  'obra': 'Obra determinada',
  'temporada': 'Por temporada',
};
const jornadas = {'diurna': 'Diurna', 'nocturna': 'Nocturna', 'mixta': 'Mixta'};
const periodicidades = {'semanal': 'Semanal', 'catorcenal': 'Catorcenal', 'quincenal': 'Quincenal', 'mensual': 'Mensual'};
const formasPago = {'transferencia': 'Transferencia', 'efectivo': 'Efectivo', 'cheque': 'Cheque'};
const tiposInfonavit = {
  'porcentaje': 'Porcentaje',
  'cuota_fija': 'Cuota fija',
  'vsm': 'Veces salario mínimo',
  'umi': 'UMI',
};
const tiposBaja = {
  'renuncia': 'Renuncia voluntaria',
  'despido': 'Despido / rescisión',
  'termino_contrato': 'Término de contrato',
  'abandono': 'Abandono de empleo',
  'jubilacion': 'Jubilación / pensión',
  'defuncion': 'Defunción',
  'otro': 'Otro',
};
const regimenesFiscales = {
  '605': '605 · Sueldos y salarios',
  '606': '606 · Arrendamiento',
  '612': '612 · Act. empresariales y profesionales',
  '626': '626 · RESICO',
};
