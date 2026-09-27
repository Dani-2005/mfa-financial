import 'database_service.dart';

/// Traduce cada combinación de tabla/acción/evento de `auditoria_sistema` a
/// una frase en lenguaje simple, para que tanto la bitácora como el reporte
/// de Auditoría se puedan mostrar a alguien no técnico sin necesidad de
/// explicarle nombres de tablas o JSON crudo. Cualquier combinación no
/// cubierta cae en una descripción genérica en vez de romperse o quedar en
/// blanco. Usado por [ReporteService] y [AuditoriaService].
String descripcionAuditoria({
  required String tabla,
  required String accion,
  required String registroId,
  required String usuario,
  required Map<String, dynamic>? nuevos,
  // Nombre del cliente dueño del préstamo/pago/cliente afectado, resuelto
  // aparte (ver [AuditoriaService.fetchAll]) porque `nuevos` casi nunca lo
  // trae para préstamos y pagos — solo el código del préstamo o el número
  // de recibo. Sin esto, buscar la bitácora por nombre de cliente solo
  // encontraba los eventos hechos directamente sobre su ficha (crearlo o
  // editarlo), no sus préstamos ni pagos.
  String? nombreCliente,
}) {
  String monto(dynamic v) => v == null ? '' : _formatMoney(_toDouble(v));
  // Para pegar al final de una frase que no lo trae ya incluido.
  String sufijoCliente() => (nombreCliente == null || nombreCliente.isEmpty) ? '' : ' (Cliente: $nombreCliente)';

  switch (tabla) {
    case 'clientes':
      if (accion == 'INSERT') {
        return '$usuario registró un nuevo cliente: ${nuevos?['nombre_cliente'] ?? registroId}.';
      }
      if (nuevos != null && nuevos.length == 1 && nuevos.containsKey('activo')) {
        final activo = nuevos['activo'] == true;
        final quien = (nombreCliente == null || nombreCliente.isEmpty) ? 'con documento $registroId' : nombreCliente;
        return '$usuario ${activo ? 'reactivó' : 'desactivó'} al cliente $quien.';
      }
      return '$usuario actualizó los datos del cliente ${nuevos?['nombre_cliente'] ?? registroId}.';

    case 'prestamos':
      if (accion == 'INSERT') {
        return '$usuario creó el préstamo #$registroId por ${monto(nuevos?['capital_inicial'])}${sufijoCliente()}.';
      }
      if (accion == 'DESACTIVAR') {
        return '$usuario liquidó y cerró el préstamo #$registroId${sufijoCliente()}.';
      }
      if (nuevos?['evento'] == 'edicion de terminos') {
        return '$usuario editó los términos del préstamo #$registroId${sufijoCliente()}.';
      }
      if (nuevos?['evento'] == 'inyeccion de capital') {
        return '$usuario inyectó ${monto(nuevos?['monto_inyectado'])} de capital al préstamo #$registroId, '
            'a partir de la cuota ${nuevos?['periodo_desde']}${sufijoCliente()}.';
      }
      if (nuevos?.containsKey('abono_capital') == true) {
        return '$usuario registró un abono a capital de ${monto(nuevos?['abono_capital'])} en el préstamo '
            '#$registroId (recibo ${nuevos?['recibo']})${sufijoCliente()}.';
      }
      return '$usuario actualizó el préstamo #$registroId${sufijoCliente()}.';

    case 'recibos_pagos':
      final montoTexto = monto(nuevos?['monto_total_pagado']);
      if (nuevos?['tipo_movimiento'] == 'Liquidacion_Total') {
        return '$usuario registró la liquidación total de un préstamo (recibo #$registroId) '
            'por $montoTexto${sufijoCliente()}.';
      }
      return '$usuario registró un pago de $montoTexto (recibo #$registroId)${sufijoCliente()}.';

    case 'usuarios':
      switch (nuevos?['evento']) {
        case 'login exitoso':
          return '$usuario inició sesión.';
        case 'login exitoso mediante biometría':
          return '$usuario inició sesión con biometría (huella o rostro).';
        case 'logout':
          return '$usuario cerró sesión.';
        case 'intento de login fallido':
          return 'Intento de inicio de sesión fallido para el usuario "$registroId".';
        case 'cuenta bloqueada por intentos fallidos':
          return 'La cuenta "$registroId" se bloqueó temporalmente por demasiados intentos fallidos.';
        case 'desbloqueo biométrico activado en un dispositivo':
          return '$usuario activó el desbloqueo biométrico en un dispositivo.';
        case 'contraseña actualizada por el propio usuario':
          return '$usuario cambió su contraseña.';
      }
      return '$usuario actualizó datos del usuario "$registroId".';
  }

  return '$usuario ${_accionGenerica(accion)} un registro en "$tabla" (#$registroId).';
}

/// Resuelve, para cada posible `registro_id` que puede aparecer en la
/// bitácora, el nombre del cliente al que pertenece: la cédula del propio
/// cliente, el código de un préstamo suyo, o el número de un recibo de pago
/// suyo. Se arma en tres consultas puntuales (no una por fila) para no
/// volver lenta la bitácora completa. Compartida entre [AuditoriaService] y
/// [ReporteService], que muestran la misma descripción en dos pantallas
/// distintas (la bitácora y el reporte de Auditoría).
Future<Map<String, String>> fetchNombresClientePorRegistro() async {
  final nombres = <String, String>{};

  final porDocumento = await DatabaseService.instance.query(
    'SELECT documento_identidad, nombre_cliente FROM clientes',
  );
  for (final row in porDocumento.rows) {
    final f = row.typedAssoc();
    nombres['${f['documento_identidad']}'] = f['nombre_cliente'] as String;
  }

  final porPrestamo = await DatabaseService.instance.query(
    'SELECT p.codigo_referencia, c.nombre_cliente FROM prestamos p '
    'JOIN clientes c ON c.cliente_id = p.cliente_id',
  );
  for (final row in porPrestamo.rows) {
    final f = row.typedAssoc();
    nombres['${f['codigo_referencia']}'] = f['nombre_cliente'] as String;
  }

  final porRecibo = await DatabaseService.instance.query(
    'SELECT r.codigo_recibo, c.nombre_cliente FROM recibos_pagos r '
    'JOIN prestamos p ON p.prestamo_id = r.prestamo_id '
    'JOIN clientes c ON c.cliente_id = p.cliente_id',
  );
  for (final row in porRecibo.rows) {
    final f = row.typedAssoc();
    nombres['${f['codigo_recibo']}'] = f['nombre_cliente'] as String;
  }

  return nombres;
}

/// Normaliza una columna JSON del driver de MySQL (que a veces llega ya
/// decodificada como Map y a veces no) a un `Map<String, dynamic>?` simple.
Map<String, dynamic>? auditoriaAsMap(dynamic value) {
  if (value == null) return null;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _accionGenerica(String accion) {
  switch (accion) {
    case 'INSERT':
      return 'creó';
    case 'UPDATE':
      return 'actualizó';
    case 'DESACTIVAR':
      return 'desactivó';
    case 'DELETE':
      return 'eliminó';
    default:
      return 'modificó';
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}

String _formatMoney(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
    buffer.write(intPart[i]);
  }
  return '\$${buffer.toString()},${parts[1]}';
}
