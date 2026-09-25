import 'auditoria_service.dart';
import 'database_service.dart';

/// Igual que el `PagoService` de la app, pero `usuarioResponsable` se
/// recibe explícito en cada llamada en vez de leerse de un global — ver la
/// nota en `models.dart` sobre por qué el servidor no puede usar ese patrón.
class PagoService {
  final AuditoriaService _auditoria = AuditoriaService();

  /// Trae los recibos de pago con los datos formateados para las tarjetas
  /// de la pantalla de Historial de Pagos.
  Future<List<Map<String, dynamic>>> fetchAll() async {
    final result = await DatabaseService.instance.query(
      'SELECT r.codigo_recibo, r.fecha_emision, r.monto_total_pagado, r.descripcion_concepto, '
      'r.metodo_pago, r.referencia, r.activo, r.tipo_movimiento, '
      'cu.numero_periodo, p.numero_cuotas, p.codigo_referencia, cl.cliente_id, cl.nombre_cliente '
      'FROM recibos_pagos r '
      'JOIN prestamos p ON p.prestamo_id = r.prestamo_id '
      'JOIN clientes cl ON cl.cliente_id = p.cliente_id '
      'LEFT JOIN cuotas cu ON cu.cuota_id = r.cuota_id '
      'ORDER BY r.fecha_emision DESC, r.reciboPago_id DESC',
    );

    return result.rows.map((row) {
      final f = row.typedAssoc();
      final fecha = f['fecha_emision'] as DateTime;
      final tipoMovimiento = f['tipo_movimiento'] as String;

      String cuotaTexto;
      switch (tipoMovimiento) {
        case 'Abono_Capital':
          cuotaTexto = 'Abono a Capital (#${f['codigo_referencia']})';
          break;
        case 'Liquidacion_Total':
          cuotaTexto = 'Liquidación Total (#${f['codigo_referencia']})';
          break;
        case 'Pago_Parcial':
          cuotaTexto = 'Pago Parcial (Cuota ${f['numero_periodo']} de ${f['numero_cuotas']})';
          break;
        default:
          cuotaTexto = 'Cuota ${f['numero_periodo']} de ${f['numero_cuotas']}';
      }

      return {
        'codigo_recibo': f['codigo_recibo'],
        'cliente': f['nombre_cliente'],
        // Para los filtros por cliente y por préstamo del Historial de Pagos.
        'cliente_id': f['cliente_id'],
        'prestamo_codigo': f['codigo_referencia'],
        'cuota': cuotaTexto,
        'tipoMovimiento': tipoMovimiento,
        'fecha_emision': _formatDateDisplay(fecha),
        'monto': _formatMoney(_toDouble(f['monto_total_pagado'])),
        'concepto': f['descripcion_concepto'],
        'metodo': f['metodo_pago'] ?? 'No especificado',
        'referencia': (f['referencia'] as String?)?.isNotEmpty == true ? f['referencia'] : 'N/A',
        'activo': f['activo'],
        'mes': fecha.month,
        'anio': fecha.year,
      };
    }).toList();
  }

  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  /// Trae todos los datos de un recibo puntual, ya armados como los
  /// necesita el PDF: cliente, préstamo, las líneas de detalle (saldo de
  /// referencia + el cargo cobrado) y el balance pendiente resultante.
  Future<Map<String, dynamic>> fetchReciboDetalle(String codigoRecibo) async {
    final result = await DatabaseService.instance.query(
      'SELECT r.codigo_recibo, r.fecha_emision, r.monto_total_pagado, r.descripcion_concepto, '
      'r.metodo_pago, r.referencia, r.tipo_movimiento, r.balance_pendiente AS balance_congelado, '
      'cu.numero_periodo, cu.saldo_inicio_periodo, cu.fecha_vencimiento, '
      'cu.monto_interes_generado, cu.monto_capital_amortizado, cu.monto_pagado_acumulado, '
      'p.codigo_referencia, p.balance_actual, p.numero_cuotas, '
      'cl.nombre_cliente, cl.documento_identidad, cl.direccion '
      'FROM recibos_pagos r '
      'JOIN prestamos p ON p.prestamo_id = r.prestamo_id '
      'JOIN clientes cl ON cl.cliente_id = p.cliente_id '
      'LEFT JOIN cuotas cu ON cu.cuota_id = r.cuota_id '
      'WHERE r.codigo_recibo = :codigo',
      {'codigo': codigoRecibo},
    );
    if (result.rows.isEmpty) {
      throw ArgumentError.value(codigoRecibo, 'codigoRecibo', 'El recibo no existe');
    }

    final f = result.rows.first.typedAssoc();
    final tipoMovimiento = f['tipo_movimiento'] as String;
    final fechaEmision = f['fecha_emision'] as DateTime;
    final monto = _toDouble(f['monto_total_pagado']);
    final concepto = f['descripcion_concepto'] as String;

    final List<Map<String, dynamic>> lineas;
    double balancePendiente;

    switch (tipoMovimiento) {
      case 'Abono_Capital':
        final balanceDespues = _toDouble(f['balance_actual']);
        final balanceAntes = balanceDespues + monto;
        lineas = [
          {'fecha': _formatDateDisplay(fechaEmision), 'descripcion': 'Saldo Antes del Abono', 'cantidad': 1, 'precio': balanceAntes},
          {'fecha': null, 'descripcion': concepto, 'cantidad': 1, 'precio': monto},
        ];
        balancePendiente = balanceDespues;
        break;
      case 'Liquidacion_Total':
        lineas = [
          {'fecha': _formatDateDisplay(fechaEmision), 'descripcion': 'Saldo Total Adeudado', 'cantidad': 1, 'precio': monto},
          {'fecha': null, 'descripcion': concepto, 'cantidad': 1, 'precio': monto},
        ];
        balancePendiente = 0;
        break;
      case 'Pago_Parcial':
        final montoTotalCuota = _toDouble(f['monto_interes_generado']) + _toDouble(f['monto_capital_amortizado']);
        final montoPagadoAcumulado = _toDouble(f['monto_pagado_acumulado']);
        lineas = [
          {'fecha': _formatDateDisplay(fechaEmision), 'descripcion': 'Monto Total de la Cuota', 'cantidad': 1, 'precio': montoTotalCuota},
          {'fecha': null, 'descripcion': concepto, 'cantidad': 1, 'precio': monto},
        ];
        balancePendiente = montoTotalCuota - montoPagadoAcumulado;
        break;
      default:
        final saldoInicio = _toDouble(f['saldo_inicio_periodo']);
        final fechaPeriodo = f['fecha_vencimiento'] as DateTime? ?? fechaEmision;
        lineas = [
          {
            'fecha': _formatDateDisplay(fechaEmision),
            'descripcion': 'Saldo Inicio Periodo ${_meses[fechaPeriodo.month - 1]}',
            'cantidad': 1,
            'precio': saldoInicio,
          },
          {'fecha': null, 'descripcion': concepto, 'cantidad': 1, 'precio': monto},
        ];
        // Las cuotas ordinarias son de solo interés (monto_capital_amortizado
        // siempre es 0 en este modelo), así que cobrarla no reduce el saldo.
        balancePendiente = saldoInicio;
    }

    // Recibos emitidos antes de que existiera esta columna no tienen un
    // balance congelado guardado: para esos (únicamente) se conserva el
    // cálculo "en vivo" de arriba como respaldo. Para todo recibo nuevo, el
    // valor guardado en el momento del pago es el correcto — el de arriba
    // puede quedar desactualizado si el préstamo o la cuota cambian después.
    final balanceCongelado = f['balance_congelado'];
    if (balanceCongelado != null) {
      balancePendiente = _toDouble(balanceCongelado);
    }

    return {
      'codigo_recibo': f['codigo_recibo'],
      'fecha_emision': _formatDateDisplay(fechaEmision),
      'cliente_nombre': f['nombre_cliente'],
      'cliente_documento': f['documento_identidad'],
      'cliente_direccion': (f['direccion'] as String?)?.isNotEmpty == true ? f['direccion'] : 'N/A',
      'prestamo_referencia': f['codigo_referencia'],
      'tipo_movimiento': tipoMovimiento,
      'metodo_pago': f['metodo_pago'],
      'referencia': f['referencia'],
      'lineas': lineas,
      'balance_pendiente': balancePendiente,
    };
  }

  /// Genera el siguiente código de recibo con formato AAAAMMSSSSSSSS,
  /// igual convención que el código de referencia de los préstamos.
  Future<String> generateNextCodigoRecibo() async {
    final now = DateTime.now();
    final yearMonth = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';

    final result = await DatabaseService.instance.query(
      'SELECT codigo_recibo FROM recibos_pagos '
      'WHERE codigo_recibo LIKE :prefix '
      'ORDER BY codigo_recibo DESC LIMIT 1',
      {'prefix': '$yearMonth%'},
    );

    int nextSeq = 1;
    if (result.rows.isNotEmpty) {
      final lastCode = result.rows.first.colAt(0) as String;
      nextSeq = int.parse(lastCode.substring(6)) + 1;
    }

    return '$yearMonth${nextSeq.toString().padLeft(8, '0')}';
  }

  /// Trae el estado y los montos vigentes de una cuota (total, ya pagado y
  /// restante), usados tanto por [registrarPago] como por [registrarPagoParcial]
  /// para validar el monto ingresado antes de aceptar el pago.
  Future<Map<String, dynamic>> _fetchEstadoCuota(int cuotaId) async {
    final actual = await DatabaseService.instance.query(
      'SELECT estado, prestamo_id, monto_interes_generado, monto_capital_amortizado, '
      'monto_pagado_acumulado, saldo_inicio_periodo '
      'FROM cuotas WHERE cuota_id = :id',
      {'id': cuotaId},
    );
    if (actual.rows.isEmpty) {
      throw ArgumentError.value(cuotaId, 'cuotaId', 'La cuota no existe');
    }
    final f = actual.rows.first.typedAssoc();
    final montoTotal = _toDouble(f['monto_interes_generado']) + _toDouble(f['monto_capital_amortizado']);
    final montoPagado = _toDouble(f['monto_pagado_acumulado']);
    return {
      'estado': f['estado'] as String,
      'prestamoId': f['prestamo_id'] as int,
      'montoTotal': montoTotal,
      'montoPagado': montoPagado,
      'montoRestante': montoTotal - montoPagado,
      'saldoInicioPeriodo': _toDouble(f['saldo_inicio_periodo']),
    };
  }

  /// Registra el pago COMPLETO de una cuota (tipo 'Cuota Ordinaria'): crea el
  /// recibo y marca la cuota como 'Pagado'. Falla si la cuota ya estaba
  /// pagada, o si el monto ingresado no cubre lo que falta por pagar (en ese
  /// caso hay que usar "Pago Parcial" en su lugar).
  Future<void> registrarPago({
    required String usuarioResponsable,
    required int cuotaId,
    required double monto,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    if (monto <= 0) {
      throw ArgumentError.value(monto, 'monto', 'Debe ser mayor a 0');
    }

    final cuota = await _fetchEstadoCuota(cuotaId);
    final estadoActual = cuota['estado'] as String;
    final prestamoId = cuota['prestamoId'] as int;
    final montoTotal = cuota['montoTotal'] as double;
    final montoRestante = cuota['montoRestante'] as double;
    final saldoInicioPeriodo = cuota['saldoInicioPeriodo'] as double;
    if (estadoActual == 'Pagado') {
      throw ArgumentError('Esta cuota ya fue pagada anteriormente');
    }
    // Se exige el monto exacto (con una tolerancia de un centavo por
    // redondeo): ni de menos (hay que usar "Pago Parcial") ni de más (el
    // excedente no se aplica a nada, así que se rechaza en vez de perderlo).
    if ((monto - montoRestante).abs() > 0.01) {
      if (monto < montoRestante) {
        throw ArgumentError(
          'El monto ingresado no cubre lo que falta de esta cuota '
          '(falta ${_formatMoney(montoRestante)}). Usa "Pago Parcial" si quieres pagar solo una parte.',
        );
      }
      throw ArgumentError(
        'El monto ingresado supera lo que falta de esta cuota '
        '(falta exactamente ${_formatMoney(montoRestante)}). Ajusta el monto, o registra el excedente '
        'como un movimiento aparte ("Abono a Capital").',
      );
    }

    final codigoRecibo = await generateNextCodigoRecibo();

    // Una cuota ordinaria es de solo interés: pagarla no reduce el saldo del
    // préstamo, así que el balance pendiente que corresponde a ESTE recibo
    // es el saldo con el que arrancó el periodo — se congela aquí mismo para
    // que el recibo lo siga mostrando igual aunque el préstamo cambie después.
    await DatabaseService.instance.query(
      'INSERT INTO recibos_pagos '
      '(codigo_recibo, cuota_id, prestamo_id, tipo_movimiento, fecha_emision, monto_total_pagado, descripcion_concepto, metodo_pago, referencia, balance_pendiente) '
      "VALUES (:codigo, :cuotaId, :prestamoId, 'Cuota_Ordinaria', :fecha, :monto, :concepto, :metodo, :referencia, :balance)",
      {
        'codigo': codigoRecibo,
        'cuotaId': cuotaId,
        'prestamoId': prestamoId,
        'fecha': _formatDate(fechaEmision),
        'monto': monto,
        'concepto': descripcionConcepto,
        'metodo': metodoPago,
        'referencia': referencia,
        'balance': saldoInicioPeriodo,
      },
    );

    await DatabaseService.instance.query(
      "UPDATE cuotas SET estado = 'Pagado', monto_pagado_acumulado = :montoTotal WHERE cuota_id = :id",
      {'montoTotal': montoTotal, 'id': cuotaId},
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'recibos_pagos',
      registroId: codigoRecibo,
      accion: 'INSERT',
      datosNuevos: {
        'cuota_id': cuotaId,
        'monto_total_pagado': monto,
        'descripcion_concepto': descripcionConcepto,
        'metodo_pago': metodoPago,
        'referencia': referencia,
        'fecha_emision': _formatDate(fechaEmision),
      },
    );
  }

  /// Registra un pago PARCIAL de una cuota (tipo 'Pago Parcial'): crea el
  /// recibo, acumula el monto pagado y deja la cuota en estado 'Parcial'.
  /// Falla si la cuota ya estaba pagada, o si el monto ingresado cubre (o
  /// supera) lo que falta por pagar (en ese caso hay que usar "Cuota
  /// Ordinaria" para cerrarla en su lugar).
  Future<void> registrarPagoParcial({
    required String usuarioResponsable,
    required int cuotaId,
    required double monto,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    if (monto <= 0) {
      throw ArgumentError.value(monto, 'monto', 'Debe ser mayor a 0');
    }

    final cuota = await _fetchEstadoCuota(cuotaId);
    final estadoActual = cuota['estado'] as String;
    final prestamoId = cuota['prestamoId'] as int;
    final montoPagado = cuota['montoPagado'] as double;
    final montoRestante = cuota['montoRestante'] as double;
    if (estadoActual == 'Pagado') {
      throw ArgumentError('Esta cuota ya fue pagada anteriormente');
    }
    if (monto >= montoRestante) {
      throw ArgumentError(
        'El monto ingresado cubre toda la cuota (falta ${_formatMoney(montoRestante)}). '
        'Usa "Cuota Ordinaria" para cerrarla en su lugar.',
      );
    }

    final codigoRecibo = await generateNextCodigoRecibo();
    final nuevoAcumulado = montoPagado + monto;
    final balanceDespuesDeEstePago = montoRestante - monto;

    await DatabaseService.instance.query(
      'INSERT INTO recibos_pagos '
      '(codigo_recibo, cuota_id, prestamo_id, tipo_movimiento, fecha_emision, monto_total_pagado, descripcion_concepto, metodo_pago, referencia, balance_pendiente) '
      "VALUES (:codigo, :cuotaId, :prestamoId, 'Pago_Parcial', :fecha, :monto, :concepto, :metodo, :referencia, :balance)",
      {
        'codigo': codigoRecibo,
        'cuotaId': cuotaId,
        'prestamoId': prestamoId,
        'fecha': _formatDate(fechaEmision),
        'monto': monto,
        'concepto': descripcionConcepto,
        'metodo': metodoPago,
        'referencia': referencia,
        'balance': balanceDespuesDeEstePago,
      },
    );

    await DatabaseService.instance.query(
      "UPDATE cuotas SET estado = 'Parcial', monto_pagado_acumulado = :montoPagado WHERE cuota_id = :id",
      {'montoPagado': nuevoAcumulado, 'id': cuotaId},
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'recibos_pagos',
      registroId: codigoRecibo,
      accion: 'INSERT',
      datosNuevos: {
        'cuota_id': cuotaId,
        'monto_total_pagado': monto,
        'descripcion_concepto': descripcionConcepto,
        'metodo_pago': metodoPago,
        'referencia': referencia,
        'fecha_emision': _formatDate(fechaEmision),
      },
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.parse(value as String);
  }

  String _formatMoney(double value) {
    final isNegative = value < 0;
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }
    return '${isNegative ? '-' : ''}\$${buffer.toString()},${parts[1]}';
  }

  String _formatDateDisplay(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
