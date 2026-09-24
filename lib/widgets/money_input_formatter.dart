import 'package:flutter/services.dart';

/// `TextInputFormatter` para campos de monto: mientras se escribe, formatea
/// en vivo como "1.234.567,89" (punto de miles, coma decimal) — los dígitos
/// escritos se interpretan de derecha a izquierda como centavos, igual que
/// la mayoría de cajeros/calculadoras de monto.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    while (digitos.length < 3) {
      digitos = '0$digitos';
    }

    final centavos = digitos.substring(digitos.length - 2);
    var entero = digitos.substring(0, digitos.length - 2);
    entero = entero.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final buffer = StringBuffer();
    for (int i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) buffer.write('.');
      buffer.write(entero[i]);
    }

    final texto = '${buffer.toString()},$centavos';
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }

  /// Convierte el texto ya formateado ("1.234.567,89") de vuelta a un
  /// `double` (1234567.89), para cálculos o para mandarlo al servidor.
  /// Devuelve `null` si el texto está vacío o no es un número válido.
  static double? parse(String texto) {
    if (texto.isEmpty) return null;
    final limpio = texto.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(limpio);
  }

  /// Da el texto ya formateado ("1.234.567,89") a partir de un `double`,
  /// para pre-llenar un campo de monto (p. ej. un saldo sugerido) con el
  /// mismo formato que produce este formateador al escribir.
  static String format(double valor) {
    final centavos = (valor.abs() * 100).round().toString().padLeft(3, '0');
    var entero = centavos.substring(0, centavos.length - 2);
    entero = entero.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final decimales = centavos.substring(centavos.length - 2);

    final buffer = StringBuffer();
    for (int i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) buffer.write('.');
      buffer.write(entero[i]);
    }
    return '${valor < 0 ? '-' : ''}${buffer.toString()},$decimales';
  }
}
