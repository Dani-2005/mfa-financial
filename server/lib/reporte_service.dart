import 'database_service.dart';

/// Arma los datos reales para el Centro de Generación de Reportes de
/// Auditoría: una fila por registro, con los mismos nombres de campo que
/// ya se muestran como checkboxes en la pantalla (así el PDF solo necesita
/// filtrar por las claves que el usuario marcó, sin lógica adicional).
class ReporteService {
  Future<List<Map<String, dynamic>>> fetchDatos({
    required String modulo,
    int? clienteId,
  }) async {
    switch (modulo) {
      case 'Clientes':
        return _fetchClientes();
      case 'Préstamos':
        return _fetchPrestamos(clienteId);
      case 'Pagos':
        return _fetchPagos(clienteId);
      case 'Auditoría':
        return _fetchAuditoria();
      default:
        return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchClientes() async {
    final result = await DatabaseService.instance.query(
      'SELECT documento_identidad, nombre_cliente, telefono, direccion, activo '
      'FROM clientes ORDER BY nombre_cliente',
    );
    return result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'Cédula / ID': f['documento_identidad'],
        'Nombre Completo': f['nombre_cliente'],
        'Teléfono': (f['telefono'] as String?)?.isNotEmpty == true ? f['telefono'] : 'N/A',
        'Dirección': (f['direccion'] as String?)?.isNotEmpty == true ? f['direccion'] : 'N/A',
        'Estatus Activo': (f['activo'] as bool) ? 'Activo' : 'Inactivo',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPrestamos(int? clienteId) async {
    final result = await DatabaseService.instance.query(
      'SELECT p.codigo_referencia, c.documento_identidad, p.capital_inicial, p.numero_cuotas, p.estado '
      'FROM prestamos p JOIN clientes c ON c.cliente_id = p.cliente_id '
      '${clienteId != null ? 'WHERE p.cliente_id = :clienteId ' : ''}'
      'ORDER BY p.created_at DESC',
      clienteId != null ? {'clienteId': clienteId} : null,
    );
    return result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'Código Préstamo': f['codigo_referencia'],
        'Cédula Cliente': f['documento_identidad'],
        'Monto Aprobado': _formatMoney(_toDouble(f['capital_inicial'])),
        'Plazo': '${f['numero_cuotas']} cuotas',
        'Estatus': f['estado'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchPagos(int? clienteId) async {
    final result = await DatabaseService.instance.query(
      'SELECT r.codigo_recibo, c.documento_identidad, p.codigo_referencia, r.monto_total_pagado, '
      'r.descripcion_concepto, r.metodo_pago, r.referencia, r.fecha_emision '
      'FROM recibos_pagos r '
      'JOIN prestamos p ON p.prestamo_id = r.prestamo_id '
      'JOIN clientes c ON c.cliente_id = p.cliente_id '
      '${clienteId != null ? 'WHERE p.cliente_id = :clienteId ' : ''}'
      'ORDER BY r.fecha_emision DESC',
      clienteId != null ? {'clienteId': clienteId} : null,
    );
    return result.rows.map((row) {
      final f = row.typedAssoc();
      final metodo = (f['metodo_pago'] as String?) ?? 'N/A';
      final referencia = f['referencia'] as String?;
      return {
        'Número Recibo': f['codigo_recibo'],
        'Cédula Cliente': f['documento_identidad'],
        'Préstamo': '#${f['codigo_referencia']}',
        'Monto Pagado': _formatMoney(_toDouble(f['monto_total_pagado'])),
        'Descripción': f['descripcion_concepto'],
        'Referencia / Método': referencia?.isNotEmpty == true ? '$metodo - $referencia' : metodo,
        'Fecha': _formatDate(f['fecha_emision'] as DateTime),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAuditoria() async {
    final result = await DatabaseService.instance.query(
      'SELECT auditoriaSistema_id, tabla_afectada, accion, registro_id, usuario_responsable, fecha_accion, '
      'datos_anteriores, datos_nuevos '
      'FROM auditoria_sistema ORDER BY fecha_accion DESC LIMIT 500',
    );
    return result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'ID Log': '${f['auditoriaSistema_id']}',
        'Tabla Afectada': f['tabla_afectada'],
        'Acción': f['accion'],
        'Registro ID': f['registro_id'],
        'Usuario Responsable': f['usuario_responsable'] ?? 'N/A',
        'Fecha Acción': _formatFechaHora(f['fecha_accion'] as DateTime),
        'Snapshots JSON': _resumenJson(f['datos_anteriores'], f['datos_nuevos']),
      };
    }).toList();
  }

  String _resumenJson(dynamic anteriores, dynamic nuevos) {
    String corto(dynamic v) {
      if (v == null) return 'NULL';
      final texto = v.toString();
      return texto.length > 80 ? '${texto.substring(0, 80)}...' : texto;
    }

    return 'Antes: ${corto(anteriores)} | Después: ${corto(nuevos)}';
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatFechaHora(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
