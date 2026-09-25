import 'auditoria_descripcion.dart';
import 'database_service.dart';

/// Arma los datos reales para el Centro de Generación de Reportes de
/// Auditoría: una fila por registro, con los mismos nombres de campo que
/// ya se muestran como checkboxes en la pantalla (así el PDF solo necesita
/// filtrar por las claves que el usuario marcó, sin lógica adicional).
class ReporteService {
  Future<List<Map<String, dynamic>>> fetchDatos({
    required String modulo,
    int? clienteId,
    String? tipoAccion,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    switch (modulo) {
      case 'Clientes':
        return _fetchClientes();
      case 'Préstamos':
        return _fetchPrestamos(clienteId);
      case 'Pagos':
        return _fetchPagos(clienteId);
      case 'Auditoría':
        return _fetchAuditoria(tipoAccion, fechaDesde, fechaHasta);
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
      'SELECT p.codigo_referencia, p.nombre_prestamo, c.documento_identidad, p.capital_inicial, p.numero_cuotas, p.estado '
      'FROM prestamos p JOIN clientes c ON c.cliente_id = p.cliente_id '
      '${clienteId != null ? 'WHERE p.cliente_id = :clienteId ' : ''}'
      'ORDER BY p.created_at DESC',
      clienteId != null ? {'clienteId': clienteId} : null,
    );
    return result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'Código Préstamo': f['codigo_referencia'],
        'Nombre del Préstamo': (f['nombre_prestamo'] as String?)?.isNotEmpty == true ? f['nombre_prestamo'] : 'N/A',
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

  /// [tipoAccion] filtra el reporte por tipo de evento: null/'TODAS' no
  /// filtra; 'INSERT'/'DESACTIVAR' filtran por esa columna `accion` tal
  /// cual. 'UPDATE' y 'LOGINS' se distinguen entre sí aunque ambos son
  /// filas con `accion = 'UPDATE'`: los eventos de login (éxito, fallido o
  /// por biometría) se registran así porque técnicamente actualizan la fila
  /// del usuario, pero conceptualmente son otra cosa, así que se separan
  /// buscando la palabra "login" dentro del JSON de `datos_nuevos`.
  ///
  /// [fechaDesde]/[fechaHasta] acotan por `fecha_accion` (inclusive en
  /// ambos extremos) — pensado para que el reporte no salga con miles de
  /// páginas cuando la bitácora crece; se combinan con el límite fijo de
  /// 500 filas, que sigue aplicando igual como último resguardo.
  Future<List<Map<String, dynamic>>> _fetchAuditoria(
    String? tipoAccion,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  ) async {
    final condiciones = <String>[];
    final params = <String, dynamic>{};

    switch (tipoAccion) {
      case 'INSERT':
      case 'DESACTIVAR':
        condiciones.add('accion = :accion');
        params['accion'] = tipoAccion;
        break;
      case 'UPDATE':
        condiciones.add("accion = 'UPDATE' AND (datos_nuevos IS NULL OR datos_nuevos NOT LIKE '%login%')");
        break;
      case 'LOGINS':
        condiciones.add("accion = 'UPDATE' AND datos_nuevos LIKE '%login%'");
        break;
    }
    if (fechaDesde != null) {
      condiciones.add('fecha_accion >= :fechaDesde');
      params['fechaDesde'] = _formatFechaSql(fechaDesde);
    }
    if (fechaHasta != null) {
      // El final de ese día completo, no la medianoche con la que arranca.
      condiciones.add('fecha_accion <= :fechaHasta');
      params['fechaHasta'] = _formatFechaSql(fechaHasta.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
    }
    final whereClause = condiciones.isEmpty ? '' : 'WHERE ${condiciones.join(' AND ')} ';

    final result = await DatabaseService.instance.query(
      'SELECT auditoriaSistema_id, tabla_afectada, accion, registro_id, usuario_responsable, fecha_accion, '
      'datos_anteriores, datos_nuevos '
      'FROM auditoria_sistema ${whereClause}ORDER BY fecha_accion DESC LIMIT 500',
      params.isEmpty ? null : params,
    );
    return result.rows.map((row) {
      final f = row.typedAssoc();
      final tabla = f['tabla_afectada'] as String;
      final accion = f['accion'] as String;
      final registroId = f['registro_id'] as String;
      final usuario = (f['usuario_responsable'] as String?) ?? 'N/A';
      final nuevos = auditoriaAsMap(f['datos_nuevos']);
      return {
        'ID Log': '${f['auditoriaSistema_id']}',
        'Tabla Afectada': tabla,
        'Acción': accion,
        'Registro ID': registroId,
        'Usuario Responsable': usuario,
        'Fecha Acción': _formatFechaHora(f['fecha_accion'] as DateTime),
        'Descripción': descripcionAuditoria(
          tabla: tabla,
          accion: accion,
          registroId: registroId,
          usuario: usuario,
          nuevos: nuevos,
        ),
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

  String _formatFechaSql(DateTime date) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${dos(date.month)}-${dos(date.day)} ${dos(date.hour)}:${dos(date.minute)}:${dos(date.second)}';
  }
}
