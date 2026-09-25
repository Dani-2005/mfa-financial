import 'auditoria_service.dart';
import 'database_service.dart';
import 'loan_calculator.dart';
import 'pago_service.dart';

/// Igual que el `PrestamoService` de la app, pero `usuarioResponsable` se
/// recibe explícito en cada llamada en vez de leerse de un global — ver la
/// nota en `models.dart` sobre por qué el servidor no puede usar ese patrón.
class PrestamoService {
  final AuditoriaService _auditoria = AuditoriaService();
  final PagoService _pagoService = PagoService();

  /// Marca un préstamo como finalizado: eliminación lógica, no física.
  /// Pone estado='Pagado' y activo=false; el registro queda intacto en la
  /// base de datos (y en su auditoría) para historial, pero deja de
  /// aparecer en el listado de préstamos activos.
  Future<void> finalizarPrestamo({
    required String usuarioResponsable,
    required int prestamoId,
    required String codigoReferencia,
  }) async {
    final actual = await DatabaseService.instance.query(
      'SELECT estado FROM prestamos WHERE prestamo_id = :id',
      {'id': prestamoId},
    );
    final estadoAnterior = actual.rows.isNotEmpty ? actual.rows.first.typedAssoc()['estado'] as String? : null;

    await DatabaseService.instance.query(
      "UPDATE prestamos SET estado = 'Pagado', activo = FALSE WHERE prestamo_id = :id",
      {'id': prestamoId},
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'prestamos',
      registroId: codigoReferencia,
      accion: 'DESACTIVAR',
      datosAnteriores: {'estado': estadoAnterior, 'activo': true},
      datosNuevos: {'estado': 'Pagado', 'activo': false},
    );
  }

  /// Trae los préstamos activos (no finalizados) de un cliente, para el
  /// selector de préstamo del formulario de "Registrar Pago".
  Future<List<Map<String, dynamic>>> fetchActivosPorCliente(int clienteId) async {
    final result = await DatabaseService.instance.query(
      'SELECT prestamo_id, codigo_referencia, tipo_tasa, tipo_calculo, numero_cuotas '
      'FROM prestamos WHERE cliente_id = :clienteId AND activo = TRUE '
      'ORDER BY created_at DESC',
      {'clienteId': clienteId},
    );

    return result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'prestamo_id': f['prestamo_id'],
        'codigo_referencia': f['codigo_referencia'],
        'loanType': '${f['tipo_tasa']} · ${f['tipo_calculo']}',
        'numero_cuotas': f['numero_cuotas'],
      };
    }).toList();
  }

  /// Trae las cuotas pendientes o parcialmente pagadas (estado='Pendiente' o
  /// 'Parcial') de un préstamo, para el selector de cuota del formulario de
  /// "Registrar Pago" (tanto para Cuota Ordinaria como para Pago Parcial).
  /// 'montoSugerido' es siempre el MONTO RESTANTE de la cuota (lo que falta
  /// por pagar), no el monto total original.
  Future<List<Map<String, dynamic>>> fetchCuotasPendientes(int prestamoId) async {
    final result = await DatabaseService.instance.query(
      'SELECT c.cuota_id, c.numero_periodo, c.fecha_vencimiento, c.estado, '
      'c.monto_interes_generado, c.monto_capital_amortizado, c.monto_pagado_acumulado, p.numero_cuotas '
      'FROM cuotas c '
      'JOIN prestamos p ON p.prestamo_id = c.prestamo_id '
      "WHERE c.prestamo_id = :prestamoId AND c.estado IN ('Pendiente', 'Parcial') "
      'ORDER BY c.numero_periodo',
      {'prestamoId': prestamoId},
    );

    return result.rows.map((row) {
      final f = row.typedAssoc();
      final montoTotal = _toDouble(f['monto_interes_generado']) + _toDouble(f['monto_capital_amortizado']);
      final montoPagado = _toDouble(f['monto_pagado_acumulado']);
      final montoRestante = montoTotal - montoPagado;

      return {
        'cuota_id': f['cuota_id'],
        'numeroPeriodo': f['numero_periodo'],
        'numeroCuotas': f['numero_cuotas'],
        'fechaVencimiento': _formatDateDisplay(f['fecha_vencimiento'] as DateTime),
        'estado': f['estado'],
        'montoTotal': montoTotal,
        'montoPagado': montoPagado,
        'montoSugerido': montoRestante,
      };
    }).toList();
  }

  /// Trae los préstamos (activos y finalizados) con los datos ya
  /// formateados para las tarjetas de la pantalla de listado (monto,
  /// progreso, estado de pago...). Los finalizados (activo=false) se
  /// devuelven con status='PAGADO' para poder mostrarlos en su propia
  /// pestaña, sin mezclarlos con los préstamos activos.
  Future<List<Map<String, dynamic>>> fetchAll() async {
    final result = await DatabaseService.instance.query(
      'SELECT p.prestamo_id, p.codigo_referencia, p.capital_inicial, p.balance_actual, '
      'p.tasa_interes_mensual, p.tipo_tasa, p.tipo_calculo, p.frecuencia_pago, p.fecha_inicio, '
      'p.numero_cuotas, p.mes_cambio_capitalizacion, p.estado, p.activo, c.nombre_cliente, c.tipo_cliente, '
      "(SELECT COUNT(*) FROM cuotas cu WHERE cu.prestamo_id = p.prestamo_id AND cu.interes_capitalizado = FALSE) "
      'AS cuotas_cobrables, '
      "(SELECT COUNT(*) FROM cuotas cu WHERE cu.prestamo_id = p.prestamo_id AND cu.interes_capitalizado = FALSE "
      "AND cu.estado = 'Pagado') AS cuotas_cobradas, "
      '(SELECT cu.saldo_fin_periodo FROM cuotas cu WHERE cu.prestamo_id = p.prestamo_id '
      'ORDER BY cu.numero_periodo DESC LIMIT 1) AS saldo_final_proyectado, '
      "(SELECT MIN(cu.fecha_vencimiento) FROM cuotas cu WHERE cu.prestamo_id = p.prestamo_id AND cu.estado = 'Pendiente') "
      'AS proxima_fecha_vencimiento, '
      'v.salud_pago '
      'FROM prestamos p '
      'JOIN clientes c ON c.cliente_id = p.cliente_id '
      'LEFT JOIN vista_salud_prestamos v ON v.prestamo_id = p.prestamo_id '
      'ORDER BY p.created_at DESC',
    );

    final today = DateTime.now();
    final hoy = DateTime(today.year, today.month, today.day);

    return result.rows.map((row) {
      final f = row.typedAssoc();

      // Las cuotas donde el interés se capitaliza no tienen nada que cobrar
      // (se reinvierte en el saldo), así que no cuentan como "progreso de
      // pago" — solo las cuotas realmente cobrables reflejan cuánto se le
      // ha cobrado de verdad al cliente.
      final cuotasCobrables = f['cuotas_cobrables'] as int;
      final cuotasCobradas = f['cuotas_cobradas'] as int;
      final saldoFinalProyectado = _toDouble(f['saldo_final_proyectado']);
      final proximaFecha = f['proxima_fecha_vencimiento'] as DateTime?;
      final activo = f['activo'] as bool;
      final estadoDb = f['estado'] as String;
      final status = (!activo || estadoDb == 'Pagado') ? 'PAGADO' : ((f['salud_pago'] as String?) ?? 'AL DÍA');
      final nombreCliente = f['nombre_cliente'] as String;
      final tipoTasa = f['tipo_tasa'] as String;
      final tipoCalculo = f['tipo_calculo'] as String;
      final numeroCuotas = f['numero_cuotas'] as int;
      final mesCambioCapitalizacion = f['mes_cambio_capitalizacion'] as int?;

      // Si hay cuotas que capitalizan, se indica el rango exacto (siempre
      // arranca en la cuota 1): hasta la cuota anterior a la transición a
      // Renta Fija (préstamo por fases), o hasta la última cuota si es un
      // Compuesto puro que capitaliza todo el plazo.
      String? capitalizacionInfo;
      if (tipoCalculo == 'Compuesto') {
        final ultimaCuotaCapitalizando = mesCambioCapitalizacion != null ? mesCambioCapitalizacion - 1 : numeroCuotas;
        if (ultimaCuotaCapitalizando >= 1) {
          capitalizacionInfo = ultimaCuotaCapitalizando == 1
              ? 'Capitalizando en la cuota 1'
              : 'Capitalizando de cuota 1 a cuota $ultimaCuotaCapitalizando';
        }
      }

      final String progressText;
      final double progressValue;
      if (cuotasCobrables == 0) {
        progressText = '$capitalizacionInfo · Saldo final proyectado: ${_formatMoney(saldoFinalProyectado)}';
        progressValue = 0.0;
      } else if (capitalizacionInfo != null) {
        progressText = '$capitalizacionInfo · Cuota $cuotasCobradas de $cuotasCobrables en Renta Fija';
        progressValue = cuotasCobradas / cuotasCobrables;
      } else {
        progressText = 'Cuota $cuotasCobradas de $cuotasCobrables';
        progressValue = cuotasCobradas / cuotasCobrables;
      }

      return {
        'prestamo_id': f['prestamo_id'],
        'name': nombreCliente,
        'code': '#${f['codigo_referencia']}',
        'frecuencia': f['frecuencia_pago'],
        'tipoTasa': tipoTasa,
        'tipoCalculo': tipoCalculo,
        'loanType': '$tipoTasa · $tipoCalculo',
        'totalAmount': _formatMoney(_toDouble(f['capital_inicial'])),
        'remainingAmount': _formatMoney(_toDouble(f['balance_actual'])),
        'progressText': progressText,
        'progressValue': progressValue,
        'status': status,
        'dueDate': _formatDueDate(proximaFecha, hoy),
        'interestRate': '${_toDouble(f['tasa_interes_mensual']).toStringAsFixed(1)}%',
        'startDate': _formatDateDisplay(f['fecha_inicio'] as DateTime),
        'initials': _initials(nombreCliente),
        'isCompany': f['tipo_cliente'] == 'JURIDICO',
        'isUrgent': status == 'PENDIENTE',
        'isOverdue': status == 'EN MORA',
      };
    }).toList();
  }

  /// Trae los datos completos de un préstamo (más allá de lo que ya
  /// muestra la tarjeta del listado): si tiene cambio de tasa programado,
  /// si es una operación por fases, cliente, frecuencia, etc. — usado para
  /// el encabezado del PDF del plan de pagos.
  Future<Map<String, dynamic>> fetchDetalle(int prestamoId) async {
    final result = await DatabaseService.instance.query(
      'SELECT p.codigo_referencia, p.tipo_tasa, p.tipo_calculo, p.capital_inicial, '
      'p.tasa_interes_mensual, p.mes_cambio_tasa, p.nueva_tasa_interes, '
      'p.mes_cambio_capitalizacion, p.frecuencia_pago, p.fecha_inicio, p.numero_cuotas, '
      'p.estado, p.activo, c.nombre_cliente, c.documento_identidad '
      'FROM prestamos p JOIN clientes c ON c.cliente_id = p.cliente_id '
      'WHERE p.prestamo_id = :id',
      {'id': prestamoId},
    );
    if (result.rows.isEmpty) {
      throw ArgumentError.value(prestamoId, 'prestamoId', 'El préstamo no existe');
    }
    final f = result.rows.first.typedAssoc();
    final nuevaTasa = f['nueva_tasa_interes'];
    return {
      'codigoReferencia': f['codigo_referencia'],
      'clienteNombre': f['nombre_cliente'],
      'clienteDocumento': f['documento_identidad'],
      'tipoTasa': f['tipo_tasa'],
      'tipoCalculo': f['tipo_calculo'],
      'capitalInicial': _formatMoney(_toDouble(f['capital_inicial'])),
      'tasaInteresMensual': '${_toDouble(f['tasa_interes_mensual']).toStringAsFixed(1)}%',
      'mesCambioTasa': f['mes_cambio_tasa'],
      'nuevaTasaInteres': nuevaTasa == null ? null : '${_toDouble(nuevaTasa).toStringAsFixed(1)}%',
      'mesCambioCapitalizacion': f['mes_cambio_capitalizacion'],
      'frecuenciaPago': f['frecuencia_pago'],
      'fechaInicio': _formatDateDisplay(f['fecha_inicio'] as DateTime),
      'numeroCuotas': f['numero_cuotas'],
      'estado': f['estado'],
      'activo': f['activo'],
    };
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

  static const _mesesAbrev = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _formatDueDate(DateTime? fecha, DateTime hoy) {
    if (fecha == null) return 'Sin cuotas pendientes';

    final diff = fecha.difference(hoy).inDays;
    final fechaCorta = '${fecha.day.toString().padLeft(2, '0')} ${_mesesAbrev[fecha.month - 1]}';

    if (diff < 0) return 'Vence hace ${-diff} día${-diff == 1 ? '' : 's'}';
    if (diff == 0) return 'Vence hoy';
    if (diff <= 7) return 'Vence en $diff día${diff == 1 ? '' : 's'} ($fechaCorta)';
    return 'Vence: $fechaCorta ${fecha.year}';
  }

  /// Trae el cronograma de cuotas de un préstamo, ya formateado para la
  /// tabla de "Plan de Pagos" del detalle.
  Future<List<Map<String, dynamic>>> fetchCuotas(int prestamoId) async {
    final result = await DatabaseService.instance.query(
      'SELECT numero_periodo, fecha_vencimiento, saldo_inicio_periodo, tasa_aplicada, '
      'monto_interes_generado, monto_capital_amortizado, interes_capitalizado, saldo_fin_periodo, estado '
      'FROM cuotas WHERE prestamo_id = :prestamoId ORDER BY numero_periodo',
      {'prestamoId': prestamoId},
    );

    return result.rows.map((row) {
      final f = row.typedAssoc();
      final estado = f['estado'] as String;

      return {
        'periodo': (f['numero_periodo'] as int).toString(),
        'fecha': _formatDateDisplay(f['fecha_vencimiento'] as DateTime),
        'saldoInicio': _formatMoney(_toDouble(f['saldo_inicio_periodo'])),
        'tasa': '${_toDouble(f['tasa_aplicada']).toStringAsFixed(1)}%',
        'interes': _formatMoney(_toDouble(f['monto_interes_generado'])),
        'amortizacion': _formatMoney(_toDouble(f['monto_capital_amortizado'])),
        'capitalizado': (f['interes_capitalizado'] as bool) ? 'Sí' : 'No',
        'saldoFin': _formatMoney(_toDouble(f['saldo_fin_periodo'])),
        'estado': estado,
      };
    }).toList();
  }

  /// Trae los movimientos de capital (inyecciones/retiros) de un préstamo,
  /// formateados para mostrarse en el detalle.
  Future<List<Map<String, dynamic>>> fetchMovimientosCapital(int prestamoId) async {
    final result = await DatabaseService.instance.query(
      'SELECT tipo, periodo_aplicacion, monto, fecha_transaccion '
      'FROM transacciones_capital '
      'WHERE prestamo_id = :prestamoId AND activo = TRUE '
      'ORDER BY periodo_aplicacion, fecha_transaccion',
      {'prestamoId': prestamoId},
    );

    return result.rows.map((row) {
      final f = row.typedAssoc();
      final tipo = f['tipo'] as String;
      final periodo = f['periodo_aplicacion'] as int?;

      return {
        'tipo': tipo == 'Inyeccion' ? 'Inyección' : 'Retiro',
        'esInyeccion': tipo == 'Inyeccion',
        'monto': _formatMoney(_toDouble(f['monto'])),
        'periodo': periodo,
        'fecha': _formatDateDisplay(f['fecha_transaccion'] as DateTime),
      };
    }).toList();
  }

  String _initials(String nombre) {
    final parts = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  /// Genera el siguiente código de referencia con formato AAAAMMSSSSSSSS:
  /// 4 dígitos de año + 2 de mes + 8 de número secuencial (reinicia cada mes).
  Future<String> generateNextCodigo() async {
    final now = DateTime.now();
    final yearMonth = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';

    final result = await DatabaseService.instance.query(
      'SELECT codigo_referencia FROM prestamos '
      'WHERE codigo_referencia LIKE :prefix '
      'ORDER BY codigo_referencia DESC LIMIT 1',
      {'prefix': '$yearMonth%'},
    );

    int nextSeq = 1;
    if (result.rows.isNotEmpty) {
      final lastCode = result.rows.first.colAt(0) as String;
      nextSeq = int.parse(lastCode.substring(6)) + 1;
    }

    return '$yearMonth${nextSeq.toString().padLeft(8, '0')}';
  }

  /// [tipoTasa] es 'Fija' o 'Variable'. [tipoCalculo] es 'Simple' o 'Compuesto'.
  /// Cuando [tipoTasa] es 'Variable', [mesCambioTasa] y [nuevaTasaInteres] son
  /// obligatorios; cuando es 'Fija', ambos deben venir null.
  Future<void> create({
    required String usuarioResponsable,
    required String codigoReferencia,
    required int clienteId,
    required String tipoTasa,
    required String tipoCalculo,
    required double capitalInicial,
    required double tasaInteresMensual,
    int? mesCambioTasa,
    double? nuevaTasaInteres,
    int? mesCambioCapitalizacion,
    required String frecuenciaPago,
    required DateTime fechaInicio,
    required int numeroCuotas,
    List<MovimientoCapitalPlanificado> movimientosPlanificados = const [],
  }) async {
    if (tipoTasa != 'Fija' && tipoTasa != 'Variable') {
      throw ArgumentError.value(tipoTasa, 'tipoTasa', "Debe ser 'Fija' o 'Variable'");
    }
    if (tipoCalculo != 'Simple' && tipoCalculo != 'Compuesto') {
      throw ArgumentError.value(tipoCalculo, 'tipoCalculo', "Debe ser 'Simple' o 'Compuesto'");
    }
    if (tipoTasa == 'Fija' && (mesCambioTasa != null || nuevaTasaInteres != null)) {
      throw ArgumentError("Un préstamo de tasa 'Fija' no puede tener mesCambioTasa/nuevaTasaInteres");
    }
    if (tipoTasa == 'Variable' && (mesCambioTasa == null || nuevaTasaInteres == null)) {
      throw ArgumentError("Un préstamo de tasa 'Variable' requiere mesCambioTasa y nuevaTasaInteres");
    }
    if (mesCambioCapitalizacion != null && tipoCalculo != 'Compuesto') {
      throw ArgumentError("La operación por fases (mesCambioCapitalizacion) solo aplica si tipoCalculo es 'Compuesto'");
    }

    final capitaliza = tipoCalculo == 'Compuesto';
    final esOperacionPorFases = mesCambioCapitalizacion != null;

    // Se calcula el cronograma completo ANTES de tocar la base de datos:
    // si alguna fórmula/validación falla, no se inserta nada a medias.
    final cronograma = LoanCalculator.generarCronograma(
      capitaliza: capitaliza,
      capitalInicial: capitalInicial,
      tasaInicial: tasaInteresMensual,
      nuevaTasa: nuevaTasaInteres,
      mesCambioTasa: mesCambioTasa,
      mesCambioCapitalizacion: mesCambioCapitalizacion,
      numeroCuotas: numeroCuotas,
      frecuenciaPago: frecuenciaPago,
      fechaInicio: fechaInicio,
      movimientosPlanificados: movimientosPlanificados,
    );

    final result = await DatabaseService.instance.query(
      'INSERT INTO prestamos '
      '(codigo_referencia, cliente_id, tipo_tasa, tipo_calculo, capital_inicial, balance_actual, '
      'tasa_interes_mensual, mes_cambio_tasa, nueva_tasa_interes, mes_cambio_capitalizacion, '
      'frecuencia_pago, fecha_inicio, numero_cuotas, estado) '
      'VALUES (:codigo, :clienteId, :tipoTasa, :tipoCalculo, :capital, :capital, :tasa, :mesCambio, :nuevaTasa, '
      ':mesCambioCap, :frecuencia, :fechaInicio, :numeroCuotas, :estado)',
      {
        'codigo': codigoReferencia,
        'clienteId': clienteId,
        'tipoTasa': tipoTasa,
        'tipoCalculo': tipoCalculo,
        'capital': capitalInicial,
        'tasa': tasaInteresMensual,
        'mesCambio': mesCambioTasa,
        'nuevaTasa': nuevaTasaInteres,
        'mesCambioCap': mesCambioCapitalizacion,
        'frecuencia': frecuenciaPago,
        'fechaInicio': _formatDate(fechaInicio),
        'numeroCuotas': numeroCuotas,
        'estado': esOperacionPorFases ? 'Acumulacion' : 'Activo',
      },
    );

    final prestamoId = result.lastInsertID.toInt();

    for (final cuota in cronograma) {
      // Un periodo capitalizado no tiene nada que cobrar (el interés se
      // reinvierte en el saldo), así que queda resuelto desde que se genera.
      final capitalizado = cuota['interes_capitalizado'] as bool;

      await DatabaseService.instance.query(
        'INSERT INTO cuotas '
        '(prestamo_id, numero_periodo, fecha_vencimiento, saldo_inicio_periodo, tasa_aplicada, '
        'monto_interes_generado, monto_capital_amortizado, interes_capitalizado, saldo_fin_periodo, estado) '
        'VALUES (:prestamoId, :numeroPeriodo, :fechaVencimiento, :saldoInicio, :tasa, '
        ':interes, :amortizado, :capitalizado, :saldoFin, :estado)',
        {
          'prestamoId': prestamoId,
          'numeroPeriodo': cuota['numero_periodo'],
          'fechaVencimiento': _formatDate(cuota['fecha_vencimiento'] as DateTime),
          'saldoInicio': cuota['saldo_inicio_periodo'],
          'tasa': cuota['tasa_aplicada'],
          'interes': cuota['monto_interes_generado'],
          'amortizado': cuota['monto_capital_amortizado'],
          'capitalizado': capitalizado,
          'saldoFin': cuota['saldo_fin_periodo'],
          'estado': capitalizado ? 'Pagado' : 'Pendiente',
        },
      );
    }

    for (final m in movimientosPlanificados) {
      final fecha = m.periodoDesde == 1
          ? fechaInicio
          : LoanCalculator.fechaDePeriodo(fechaInicio, frecuenciaPago, m.periodoDesde - 1);

      await DatabaseService.instance.query(
        'INSERT INTO transacciones_capital '
        '(prestamo_id, fecha_transaccion, tipo, periodo_aplicacion, monto, descripcion) '
        'VALUES (:prestamoId, :fecha, :tipo, :periodo, :monto, :descripcion)',
        {
          'prestamoId': prestamoId,
          'fecha': _formatDate(fecha),
          'tipo': m.esInyeccion ? 'Inyeccion' : 'Retiro',
          'periodo': m.periodoDesde,
          'monto': m.monto,
          'descripcion':
              'Movimiento planificado desde la creación del préstamo, a partir de la cuota ${m.periodoDesde}.',
        },
      );
    }

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'prestamos',
      registroId: codigoReferencia,
      accion: 'INSERT',
      datosNuevos: {
        'codigo_referencia': codigoReferencia,
        'cliente_id': clienteId,
        'tipo_tasa': tipoTasa,
        'tipo_calculo': tipoCalculo,
        'capital_inicial': capitalInicial,
        'tasa_interes_mensual': tasaInteresMensual,
        'mes_cambio_tasa': mesCambioTasa,
        'nueva_tasa_interes': nuevaTasaInteres,
        'mes_cambio_capitalizacion': mesCambioCapitalizacion,
        'frecuencia_pago': frecuenciaPago,
        'fecha_inicio': _formatDate(fechaInicio),
        'numero_cuotas': numeroCuotas,
        'movimientos_planificados': movimientosPlanificados
            .map((m) => {
                  'periodo_desde': m.periodoDesde,
                  'tipo': m.esInyeccion ? 'Inyeccion' : 'Retiro',
                  'monto': m.monto,
                })
            .toList(),
      },
    );
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Trae los datos crudos (sin formatear) de un préstamo para prellenar el
  /// formulario de edición, junto con si ya tiene actividad registrada
  /// (algún pago o alguna cuota que ya no está en 'Pendiente'): la pantalla
  /// usa eso para avisar que el cronograma se va a recalcular con los
  /// términos nuevos, sin alterar los pagos ya cobrados.
  Future<Map<String, dynamic>> fetchParaEditar(int prestamoId) async {
    final result = await DatabaseService.instance.query(
      'SELECT codigo_referencia, cliente_id, tipo_tasa, tipo_calculo, capital_inicial, '
      'tasa_interes_mensual, mes_cambio_tasa, nueva_tasa_interes, mes_cambio_capitalizacion, '
      'frecuencia_pago, fecha_inicio, numero_cuotas, estado, activo '
      'FROM prestamos WHERE prestamo_id = :id',
      {'id': prestamoId},
    );
    if (result.rows.isEmpty) {
      throw ArgumentError.value(prestamoId, 'prestamoId', 'El préstamo no existe');
    }
    final f = result.rows.first.typedAssoc();
    if (!(f['activo'] as bool) || f['estado'] == 'Pagado') {
      throw ArgumentError('Este préstamo ya está finalizado/liquidado, no se puede editar.');
    }

    final actividad = await DatabaseService.instance.query(
      'SELECT '
      '(SELECT COUNT(*) FROM recibos_pagos WHERE prestamo_id = :id) AS recibos, '
      "(SELECT COUNT(*) FROM cuotas WHERE prestamo_id = :id AND estado <> 'Pendiente') AS cuotasNoPendientes",
      {'id': prestamoId},
    );
    final a = actividad.rows.first.typedAssoc();
    final tieneActividad = (a['recibos'] as int) > 0 || (a['cuotasNoPendientes'] as int) > 0;

    final nuevaTasa = f['nueva_tasa_interes'];
    return {
      'codigoReferencia': f['codigo_referencia'],
      'clienteId': f['cliente_id'],
      'tipoTasa': f['tipo_tasa'],
      'tipoCalculo': f['tipo_calculo'],
      'capitalInicial': _toDouble(f['capital_inicial']),
      'tasaInteresMensual': _toDouble(f['tasa_interes_mensual']),
      'mesCambioTasa': f['mes_cambio_tasa'],
      'nuevaTasaInteres': nuevaTasa == null ? null : _toDouble(nuevaTasa),
      'mesCambioCapitalizacion': f['mes_cambio_capitalizacion'],
      'frecuenciaPago': f['frecuencia_pago'],
      'fechaInicio': _formatDate(f['fecha_inicio'] as DateTime),
      'numeroCuotas': f['numero_cuotas'],
      'tieneActividad': tieneActividad,
    };
  }

  /// Edita los términos de un préstamo ya existente: recalcula el
  /// cronograma completo desde el periodo 1 con los datos nuevos (misma
  /// fórmula que [create], vía [LoanCalculator.generarCronograma]), pero en
  /// vez de insertar cuotas nuevas, ACTUALIZA las que ya existen período por
  /// período sin tocar su `estado`/pago acumulado — así un pago ya cobrado
  /// sigue marcado como cobrado aunque el monto de interés/capital de ese
  /// período se recalcule con la tasa o el capital nuevos. Los movimientos
  /// de capital ya registrados (`transacciones_capital`) se vuelven a
  /// aplicar en el nuevo cronograma en su mismo período, así que no se
  /// pierden. Si se reduce el número de cuotas por debajo de un período que
  /// ya tiene un pago registrado, se rechaza: ese pago quedaría sin cuota a
  /// la cual pertenecer.
  Future<void> editar({
    required String usuarioResponsable,
    required int prestamoId,
    required int clienteId,
    required String tipoTasa,
    required String tipoCalculo,
    required double capitalInicial,
    required double tasaInteresMensual,
    int? mesCambioTasa,
    double? nuevaTasaInteres,
    int? mesCambioCapitalizacion,
    required String frecuenciaPago,
    required DateTime fechaInicio,
    required int numeroCuotas,
  }) async {
    if (tipoTasa != 'Fija' && tipoTasa != 'Variable') {
      throw ArgumentError.value(tipoTasa, 'tipoTasa', "Debe ser 'Fija' o 'Variable'");
    }
    if (tipoCalculo != 'Simple' && tipoCalculo != 'Compuesto') {
      throw ArgumentError.value(tipoCalculo, 'tipoCalculo', "Debe ser 'Simple' o 'Compuesto'");
    }
    if (tipoTasa == 'Fija' && (mesCambioTasa != null || nuevaTasaInteres != null)) {
      throw ArgumentError("Un préstamo de tasa 'Fija' no puede tener mesCambioTasa/nuevaTasaInteres");
    }
    if (tipoTasa == 'Variable' && (mesCambioTasa == null || nuevaTasaInteres == null)) {
      throw ArgumentError("Un préstamo de tasa 'Variable' requiere mesCambioTasa y nuevaTasaInteres");
    }
    if (mesCambioCapitalizacion != null && tipoCalculo != 'Compuesto') {
      throw ArgumentError("La operación por fases (mesCambioCapitalizacion) solo aplica si tipoCalculo es 'Compuesto'");
    }

    final actual = await DatabaseService.instance.query(
      'SELECT codigo_referencia, numero_cuotas, estado, activo FROM prestamos WHERE prestamo_id = :id',
      {'id': prestamoId},
    );
    if (actual.rows.isEmpty) {
      throw ArgumentError.value(prestamoId, 'prestamoId', 'El préstamo no existe');
    }
    final actualF = actual.rows.first.typedAssoc();
    if (!(actualF['activo'] as bool) || actualF['estado'] == 'Pagado') {
      throw ArgumentError('Este préstamo ya está finalizado/liquidado, no se puede editar.');
    }
    final codigoReferencia = actualF['codigo_referencia'] as String;
    final numeroCuotasAnterior = actualF['numero_cuotas'] as int;

    final protegido = await DatabaseService.instance.query(
      "SELECT MAX(numero_periodo) AS maxProtegido FROM cuotas WHERE prestamo_id = :id AND estado <> 'Pendiente'",
      {'id': prestamoId},
    );
    final maxProtegido = protegido.rows.first.typedAssoc()['maxProtegido'] as int?;
    if (maxProtegido != null && numeroCuotas < maxProtegido) {
      throw ArgumentError(
        'No se puede reducir el préstamo a $numeroCuotas cuotas: la cuota $maxProtegido ya tiene un pago '
        'registrado. Para reducir el plazo, primero habría que revertir ese pago.',
      );
    }

    // Los movimientos de capital ya registrados (incluyendo los planificados
    // desde la creación) se vuelven a aplicar en el cronograma recalculado,
    // en su mismo período — si el nuevo número de cuotas queda por debajo de
    // alguno de esos períodos, generarCronograma lo rechaza más abajo.
    final movimientosRows = await DatabaseService.instance.query(
      'SELECT tipo, periodo_aplicacion, monto FROM transacciones_capital '
      'WHERE prestamo_id = :id AND activo = TRUE AND periodo_aplicacion IS NOT NULL '
      'ORDER BY periodo_aplicacion',
      {'id': prestamoId},
    );
    final movimientos = movimientosRows.rows.map((row) {
      final f = row.typedAssoc();
      return MovimientoCapitalPlanificado(
        periodoDesde: f['periodo_aplicacion'] as int,
        esInyeccion: f['tipo'] == 'Inyeccion',
        monto: _toDouble(f['monto']),
      );
    }).toList();

    final capitaliza = tipoCalculo == 'Compuesto';
    final esOperacionPorFases = mesCambioCapitalizacion != null;

    // Igual que en create(): se calcula todo el cronograma nuevo ANTES de
    // tocar la base de datos, para no dejar nada a medias si falla.
    final cronograma = LoanCalculator.generarCronograma(
      capitaliza: capitaliza,
      capitalInicial: capitalInicial,
      tasaInicial: tasaInteresMensual,
      nuevaTasa: nuevaTasaInteres,
      mesCambioTasa: mesCambioTasa,
      mesCambioCapitalizacion: mesCambioCapitalizacion,
      numeroCuotas: numeroCuotas,
      frecuenciaPago: frecuenciaPago,
      fechaInicio: fechaInicio,
      movimientosPlanificados: movimientos,
    );

    await DatabaseService.instance.query(
      'UPDATE prestamos SET cliente_id = :clienteId, tipo_tasa = :tipoTasa, tipo_calculo = :tipoCalculo, '
      'capital_inicial = :capital, tasa_interes_mensual = :tasa, mes_cambio_tasa = :mesCambio, '
      'nueva_tasa_interes = :nuevaTasa, mes_cambio_capitalizacion = :mesCambioCap, '
      'frecuencia_pago = :frecuencia, fecha_inicio = :fechaInicio, numero_cuotas = :numeroCuotas, '
      'estado = :estado WHERE prestamo_id = :id',
      {
        'clienteId': clienteId,
        'tipoTasa': tipoTasa,
        'tipoCalculo': tipoCalculo,
        'capital': capitalInicial,
        'tasa': tasaInteresMensual,
        'mesCambio': mesCambioTasa,
        'nuevaTasa': nuevaTasaInteres,
        'mesCambioCap': mesCambioCapitalizacion,
        'frecuencia': frecuenciaPago,
        'fechaInicio': _formatDate(fechaInicio),
        'numeroCuotas': numeroCuotas,
        'estado': esOperacionPorFases ? 'Acumulacion' : 'Activo',
        'id': prestamoId,
      },
    );

    for (final cuota in cronograma) {
      final periodo = cuota['numero_periodo'] as int;
      final capitalizado = cuota['interes_capitalizado'] as bool;
      if (periodo <= numeroCuotasAnterior) {
        // Se actualiza el período existente sin tocar estado/monto pagado:
        // si ya se cobró, sigue cobrado, aunque el desglose interés/capital
        // de ese período cambie con los nuevos términos.
        await DatabaseService.instance.query(
          'UPDATE cuotas SET fecha_vencimiento = :fecha, saldo_inicio_periodo = :saldoInicio, '
          'tasa_aplicada = :tasa, monto_interes_generado = :interes, interes_capitalizado = :capitalizado, '
          'saldo_fin_periodo = :saldoFin WHERE prestamo_id = :prestamoId AND numero_periodo = :periodo',
          {
            'fecha': _formatDate(cuota['fecha_vencimiento'] as DateTime),
            'saldoInicio': cuota['saldo_inicio_periodo'],
            'tasa': cuota['tasa_aplicada'],
            'interes': cuota['monto_interes_generado'],
            'capitalizado': capitalizado,
            'saldoFin': cuota['saldo_fin_periodo'],
            'prestamoId': prestamoId,
            'periodo': periodo,
          },
        );
      } else {
        await DatabaseService.instance.query(
          'INSERT INTO cuotas '
          '(prestamo_id, numero_periodo, fecha_vencimiento, saldo_inicio_periodo, tasa_aplicada, '
          'monto_interes_generado, monto_capital_amortizado, interes_capitalizado, saldo_fin_periodo, estado) '
          'VALUES (:prestamoId, :numeroPeriodo, :fechaVencimiento, :saldoInicio, :tasa, '
          ':interes, :amortizado, :capitalizado, :saldoFin, :estado)',
          {
            'prestamoId': prestamoId,
            'numeroPeriodo': periodo,
            'fechaVencimiento': _formatDate(cuota['fecha_vencimiento'] as DateTime),
            'saldoInicio': cuota['saldo_inicio_periodo'],
            'tasa': cuota['tasa_aplicada'],
            'interes': cuota['monto_interes_generado'],
            'amortizado': cuota['monto_capital_amortizado'],
            'capitalizado': capitalizado,
            'saldoFin': cuota['saldo_fin_periodo'],
            'estado': capitalizado ? 'Pagado' : 'Pendiente',
          },
        );
      }
    }

    if (numeroCuotas < numeroCuotasAnterior) {
      // Seguro por el check de más arriba (ninguno de estos períodos tiene
      // pago), pero además la propia base de datos lo bloquearía si lo
      // tuviera (FK de recibos_pagos.cuota_id).
      await DatabaseService.instance.query(
        'DELETE FROM cuotas WHERE prestamo_id = :id AND numero_periodo > :numeroCuotas',
        {'id': prestamoId, 'numeroCuotas': numeroCuotas},
      );
    }

    final saldoInfo = await fetchSaldoActual(prestamoId);
    await DatabaseService.instance.query(
      'UPDATE prestamos SET balance_actual = :saldo WHERE prestamo_id = :id',
      {'saldo': saldoInfo['saldoActual'], 'id': prestamoId},
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'prestamos',
      registroId: codigoReferencia,
      accion: 'UPDATE',
      datosNuevos: {
        'evento': 'edicion de terminos',
        'cliente_id': clienteId,
        'tipo_tasa': tipoTasa,
        'tipo_calculo': tipoCalculo,
        'capital_inicial': capitalInicial,
        'tasa_interes_mensual': tasaInteresMensual,
        'mes_cambio_tasa': mesCambioTasa,
        'nueva_tasa_interes': nuevaTasaInteres,
        'mes_cambio_capitalizacion': mesCambioCapitalizacion,
        'frecuencia_pago': frecuenciaPago,
        'fecha_inicio': _formatDate(fechaInicio),
        'numero_cuotas': numeroCuotas,
      },
    );
  }

  /// Trae los datos financieros de un préstamo necesarios para recalcular
  /// su cronograma (usado por Abono a Capital, Liquidación Total e
  /// Inyección de Capital).
  Future<Map<String, dynamic>> _fetchDatosParaRecalculo(int prestamoId) async {
    final result = await DatabaseService.instance.query(
      'SELECT codigo_referencia, tipo_calculo, tasa_interes_mensual, mes_cambio_tasa, nueva_tasa_interes, '
      'mes_cambio_capitalizacion, frecuencia_pago, fecha_inicio, numero_cuotas, estado, activo, balance_actual '
      'FROM prestamos WHERE prestamo_id = :id',
      {'id': prestamoId},
    );
    if (result.rows.isEmpty) {
      throw ArgumentError.value(prestamoId, 'prestamoId', 'El préstamo no existe');
    }
    final f = result.rows.first.typedAssoc();
    if (!(f['activo'] as bool) || f['estado'] == 'Pagado') {
      throw ArgumentError('Este préstamo ya está finalizado/liquidado, no admite más movimientos.');
    }
    return f;
  }

  /// Saldo actual (capital vigente) de un préstamo y el periodo a partir del
  /// cual se aplicaría un Abono a Capital: la próxima cuota con estado
  /// 'Pendiente'. Si no hay ninguna pendiente (préstamo 100% capitalizando,
  /// sin fase de Renta Fija todavía definida) [periodoInicial] viene null y
  /// [saldoActual] es el saldo acumulado a la fecha (el de la última cuota).
  Future<Map<String, dynamic>> fetchSaldoActual(int prestamoId) async {
    final pendiente = await DatabaseService.instance.query(
      "SELECT numero_periodo, saldo_inicio_periodo FROM cuotas "
      "WHERE prestamo_id = :id AND estado = 'Pendiente' ORDER BY numero_periodo LIMIT 1",
      {'id': prestamoId},
    );

    if (pendiente.rows.isNotEmpty) {
      final f = pendiente.rows.first.typedAssoc();
      return {
        'periodoInicial': f['numero_periodo'] as int,
        'saldoActual': _toDouble(f['saldo_inicio_periodo']),
      };
    }

    final ultima = await DatabaseService.instance.query(
      'SELECT saldo_fin_periodo FROM cuotas WHERE prestamo_id = :id ORDER BY numero_periodo DESC LIMIT 1',
      {'id': prestamoId},
    );
    if (ultima.rows.isEmpty) {
      throw ArgumentError('Este préstamo no tiene cuotas generadas.');
    }
    return {
      'periodoInicial': null,
      'saldoActual': _toDouble(ultima.rows.first.typedAssoc()['saldo_fin_periodo']),
    };
  }

  /// Encuentra el periodo a partir del cual se debe aplicar un Abono a
  /// Capital hecho hoy, y el saldo vigente en ese punto.
  ///
  /// Si el préstamo tiene una cuota 'Pendiente' (préstamos Simple, o la fase
  /// de Renta Fija de un préstamo por fases), se ancla ahí — es el cursor
  /// natural de "qué falta por cobrar todavía".
  ///
  /// Si no tiene ninguna Pendiente (un préstamo Compuesto puro, sin fases:
  /// todas sus cuotas se auto-resuelven como capitalizadas desde que se
  /// crean, así que no hay ese cursor), se ancla en la SIGUIENTE cuota
  /// según la fecha real de hoy: la primera cuya fecha de vencimiento
  /// todavía no ha llegado. La cuota de hoy (o cualquiera ya vencida)
  /// conserva el interés que ya se le calculó — se considera devengado —,
  /// y es a partir de la próxima que el interés se aplica sobre el saldo
  /// ya reducido por el abono.
  Future<Map<String, dynamic>> fetchAnclaAbono(int prestamoId) async {
    final pendiente = await DatabaseService.instance.query(
      "SELECT numero_periodo, saldo_inicio_periodo FROM cuotas "
      "WHERE prestamo_id = :id AND estado = 'Pendiente' ORDER BY numero_periodo LIMIT 1",
      {'id': prestamoId},
    );
    if (pendiente.rows.isNotEmpty) {
      final f = pendiente.rows.first.typedAssoc();
      return {
        'periodoInicial': f['numero_periodo'] as int,
        'saldoActual': _toDouble(f['saldo_inicio_periodo']),
      };
    }

    final hoy = DateTime.now();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
    final vigente = await DatabaseService.instance.query(
      'SELECT numero_periodo, saldo_inicio_periodo FROM cuotas '
      'WHERE prestamo_id = :id AND fecha_vencimiento > :hoy '
      'ORDER BY fecha_vencimiento ASC, numero_periodo ASC LIMIT 1',
      {'id': prestamoId, 'hoy': _formatDate(hoySinHora)},
    );
    if (vigente.rows.isEmpty) {
      throw ArgumentError(
        'Este préstamo ya llegó al final de su plazo proyectado (todas sus cuotas vencieron). '
        'No se puede anclar un Abono a Capital aquí; considera una Liquidación Total.',
      );
    }
    final f = vigente.rows.first.typedAssoc();
    return {
      'periodoInicial': f['numero_periodo'] as int,
      'saldoActual': _toDouble(f['saldo_inicio_periodo']),
    };
  }

  /// Registra un Abono a Capital: reduce el saldo vigente a partir del
  /// periodo devuelto por [fetchAnclaAbono] y recalcula in-place todas las
  /// cuotas futuras (intereses y saldos), manteniendo fechas y cambios de
  /// tasa/capitalización ya programados. Falla si no hay ningún periodo
  /// futuro donde anclar el recálculo, o si el monto supera lo que se debe.
  Future<String> registrarAbonoCapital({
    required String usuarioResponsable,
    required int prestamoId,
    required double monto,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    if (monto <= 0) {
      throw ArgumentError.value(monto, 'monto', 'Debe ser mayor a 0');
    }

    final datos = await _fetchDatosParaRecalculo(prestamoId);
    final codigoReferencia = datos['codigo_referencia'] as String;

    final ancla = await fetchAnclaAbono(prestamoId);
    final periodoInicial = ancla['periodoInicial'] as int;
    final saldoActual = ancla['saldoActual'] as double;

    if (monto > saldoActual) {
      throw ArgumentError(
        'No puedes abonar más de lo que se debe actualmente (${_formatMoney(saldoActual)}).',
      );
    }
    final nuevoSaldo = saldoActual - monto;

    final movimientosFuturosRows = await DatabaseService.instance.query(
      'SELECT tipo, periodo_aplicacion, monto FROM transacciones_capital '
      'WHERE prestamo_id = :id AND activo = TRUE AND periodo_aplicacion > :periodoInicial',
      {'id': prestamoId, 'periodoInicial': periodoInicial},
    );
    final movimientosFuturos = movimientosFuturosRows.rows.map((row) {
      final f = row.typedAssoc();
      return MovimientoCapitalPlanificado(
        periodoDesde: f['periodo_aplicacion'] as int,
        esInyeccion: f['tipo'] == 'Inyeccion',
        monto: _toDouble(f['monto']),
      );
    }).toList();

    final recalculado = LoanCalculator.recalcularDesde(
      capitaliza: datos['tipo_calculo'] == 'Compuesto',
      saldoInicial: nuevoSaldo,
      tasaInicial: _toDouble(datos['tasa_interes_mensual']),
      nuevaTasa: datos['nueva_tasa_interes'] != null ? _toDouble(datos['nueva_tasa_interes']) : null,
      mesCambioTasa: datos['mes_cambio_tasa'] as int?,
      mesCambioCapitalizacion: datos['mes_cambio_capitalizacion'] as int?,
      numeroCuotas: datos['numero_cuotas'] as int,
      frecuenciaPago: datos['frecuencia_pago'] as String,
      fechaInicio: datos['fecha_inicio'] as DateTime,
      periodoInicial: periodoInicial,
      movimientosFuturos: movimientosFuturos,
    );

    final codigoRecibo = await _pagoService.generateNextCodigoRecibo();

    for (final cuota in recalculado) {
      await DatabaseService.instance.query(
        'UPDATE cuotas SET saldo_inicio_periodo = :saldoInicio, tasa_aplicada = :tasa, '
        'monto_interes_generado = :interes, interes_capitalizado = :capitalizado, saldo_fin_periodo = :saldoFin '
        'WHERE prestamo_id = :prestamoId AND numero_periodo = :periodo',
        {
          'saldoInicio': cuota['saldo_inicio_periodo'],
          'tasa': cuota['tasa_aplicada'],
          'interes': cuota['monto_interes_generado'],
          'capitalizado': cuota['interes_capitalizado'],
          'saldoFin': cuota['saldo_fin_periodo'],
          'prestamoId': prestamoId,
          'periodo': cuota['numero_periodo'],
        },
      );
    }

    await DatabaseService.instance.query(
      'UPDATE prestamos SET balance_actual = :saldo WHERE prestamo_id = :id',
      {'saldo': nuevoSaldo, 'id': prestamoId},
    );

    await DatabaseService.instance.query(
      'INSERT INTO transacciones_capital '
      "(prestamo_id, fecha_transaccion, tipo, periodo_aplicacion, monto, descripcion) "
      "VALUES (:prestamoId, :fecha, 'Retiro', :periodo, :monto, :descripcion)",
      {
        'prestamoId': prestamoId,
        'fecha': _formatDate(fechaEmision),
        'periodo': periodoInicial,
        'monto': monto,
        'descripcion': 'Abono a capital registrado el ${_formatDate(fechaEmision)} mediante el recibo $codigoRecibo.',
      },
    );

    await DatabaseService.instance.query(
      'INSERT INTO recibos_pagos '
      "(codigo_recibo, cuota_id, prestamo_id, tipo_movimiento, fecha_emision, monto_total_pagado, descripcion_concepto, metodo_pago, referencia, balance_pendiente) "
      "VALUES (:codigo, NULL, :prestamoId, 'Abono_Capital', :fecha, :monto, :concepto, :metodo, :referencia, :balance)",
      {
        'codigo': codigoRecibo,
        'prestamoId': prestamoId,
        'fecha': _formatDate(fechaEmision),
        'monto': monto,
        'concepto': descripcionConcepto,
        'metodo': metodoPago,
        'referencia': referencia,
        'balance': nuevoSaldo,
      },
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'prestamos',
      registroId: codigoReferencia,
      accion: 'UPDATE',
      datosAnteriores: {'balance_actual': saldoActual},
      datosNuevos: {
        'balance_actual': nuevoSaldo,
        'abono_capital': monto,
        'recibo': codigoRecibo,
        'periodo_desde': periodoInicial,
      },
    );

    return codigoRecibo;
  }

  /// Registra una Liquidación Total (pago bullet): paga el 100% del saldo
  /// vigente en un único recibo, marca todas las cuotas pendientes restantes
  /// como 'Pagado' y finaliza el préstamo (estado='Pagado', activo=false),
  /// reutilizando la misma eliminación lógica de [finalizarPrestamo].
  Future<String> registrarLiquidacionTotal({
    required String usuarioResponsable,
    required int prestamoId,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    final datos = await _fetchDatosParaRecalculo(prestamoId);
    final codigoReferencia = datos['codigo_referencia'] as String;

    final saldoInfo = await fetchSaldoActual(prestamoId);
    final saldoActual = saldoInfo['saldoActual'] as double;

    final codigoRecibo = await _pagoService.generateNextCodigoRecibo();

    await DatabaseService.instance.query(
      'INSERT INTO recibos_pagos '
      "(codigo_recibo, cuota_id, prestamo_id, tipo_movimiento, fecha_emision, monto_total_pagado, descripcion_concepto, metodo_pago, referencia, balance_pendiente) "
      "VALUES (:codigo, NULL, :prestamoId, 'Liquidacion_Total', :fecha, :monto, :concepto, :metodo, :referencia, 0)",
      {
        'codigo': codigoRecibo,
        'prestamoId': prestamoId,
        'fecha': _formatDate(fechaEmision),
        'monto': saldoActual,
        'concepto': descripcionConcepto,
        'metodo': metodoPago,
        'referencia': referencia,
      },
    );

    await DatabaseService.instance.query(
      "UPDATE cuotas SET estado = 'Pagado' WHERE prestamo_id = :id AND estado = 'Pendiente'",
      {'id': prestamoId},
    );

    await DatabaseService.instance.query(
      'UPDATE prestamos SET balance_actual = 0 WHERE prestamo_id = :id',
      {'id': prestamoId},
    );

    await finalizarPrestamo(
      usuarioResponsable: usuarioResponsable,
      prestamoId: prestamoId,
      codigoReferencia: codigoReferencia,
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'recibos_pagos',
      registroId: codigoRecibo,
      accion: 'INSERT',
      datosNuevos: {
        'prestamo_id': prestamoId,
        'tipo_movimiento': 'Liquidacion_Total',
        'monto_total_pagado': saldoActual,
        'descripcion_concepto': descripcionConcepto,
      },
    );

    return codigoRecibo;
  }

  /// Cuotas donde se puede anclar una Inyección de Capital hecha en
  /// cualquier momento del préstamo: cualquier cuota todavía 'Pendiente'
  /// (para no reescribir cuotas ya cobradas al cliente), sin importar si es
  /// la próxima o una más adelante — el prestamista elige libremente desde
  /// cuál. Si el préstamo no tiene ninguna 'Pendiente' (Compuesto puro, sin
  /// fases: todas sus cuotas se auto-resuelven capitalizadas desde que se
  /// crean), se ofrecen en su lugar las cuotas cuya fecha de vencimiento
  /// todavía no ha llegado (el interés ya devengado hasta hoy se considera
  /// cerrado), igual que en [fetchAnclaAbono].
  Future<List<Map<String, dynamic>>> fetchCuotasElegiblesParaInyeccion(int prestamoId) async {
    final pendientes = await DatabaseService.instance.query(
      "SELECT numero_periodo, fecha_vencimiento, saldo_inicio_periodo FROM cuotas "
      "WHERE prestamo_id = :id AND estado = 'Pendiente' ORDER BY numero_periodo",
      {'id': prestamoId},
    );

    Iterable<dynamic> rows = pendientes.rows;
    if (rows.isEmpty) {
      final hoy = DateTime.now();
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
      final futuras = await DatabaseService.instance.query(
        'SELECT numero_periodo, fecha_vencimiento, saldo_inicio_periodo FROM cuotas '
        'WHERE prestamo_id = :id AND fecha_vencimiento > :hoy ORDER BY numero_periodo',
        {'id': prestamoId, 'hoy': _formatDate(hoySinHora)},
      );
      rows = futuras.rows;
    }

    return rows.map((row) {
      final f = row.typedAssoc();
      return {
        'numeroPeriodo': f['numero_periodo'] as int,
        'fechaVencimiento': _formatDateDisplay(f['fecha_vencimiento'] as DateTime),
        'saldoActual': _toDouble(f['saldo_inicio_periodo']),
      };
    }).toList();
  }

  /// Registra una Inyección de Capital: aumenta el saldo a partir de la
  /// cuota [periodoDesde] elegida por el prestamista (una de las devueltas
  /// por [fetchCuotasElegiblesParaInyeccion]) y recalcula in-place todas las
  /// cuotas desde ese punto en adelante, respetando la mecánica de cálculo,
  /// la tasa y la operación por fases ya configuradas para el préstamo
  /// (misma fórmula que usa el cronograma original, vía
  /// [LoanCalculator.recalcularDesde]). No genera recibo: a diferencia de un
  /// Abono a Capital o una Cuota Ordinaria, no es un pago recibido del
  /// cliente, sino capital adicional que el prestamista aporta al préstamo.
  ///
  /// El balance_actual del préstamo se recalcula de forma independiente
  /// (igual que [fetchSaldoActual]) en vez de asumir el saldo resultante en
  /// el ancla: si el prestamista elige una cuota futura (no la próxima
  /// pendiente), el saldo que se debe cobrar hoy no cambia todavía. Ese
  /// balance_actual recalculado es lo que devuelve, para que la pantalla
  /// pueda refrescar el "Saldo Actual" mostrado sin otra consulta.
  Future<double> registrarInyeccionCapital({
    required String usuarioResponsable,
    required int prestamoId,
    required int periodoDesde,
    required double monto,
    String? descripcionConcepto,
    required DateTime fechaTransaccion,
  }) async {
    if (monto <= 0) {
      throw ArgumentError.value(monto, 'monto', 'Debe ser mayor a 0');
    }

    final datos = await _fetchDatosParaRecalculo(prestamoId);
    final codigoReferencia = datos['codigo_referencia'] as String;
    final balanceAnterior = _toDouble(datos['balance_actual']);

    final elegibles = await fetchCuotasElegiblesParaInyeccion(prestamoId);
    Map<String, dynamic>? ancla;
    for (final c in elegibles) {
      if (c['numeroPeriodo'] == periodoDesde) {
        ancla = c;
        break;
      }
    }
    if (ancla == null) {
      throw ArgumentError(
        'La cuota seleccionada ya no está disponible para inyectar capital. Actualiza la pantalla e intenta de nuevo.',
      );
    }
    final saldoAntes = ancla['saldoActual'] as double;
    final nuevoSaldoEnAncla = saldoAntes + monto;

    final movimientosFuturosRows = await DatabaseService.instance.query(
      'SELECT tipo, periodo_aplicacion, monto FROM transacciones_capital '
      'WHERE prestamo_id = :id AND activo = TRUE AND periodo_aplicacion > :periodoDesde',
      {'id': prestamoId, 'periodoDesde': periodoDesde},
    );
    final movimientosFuturos = movimientosFuturosRows.rows.map((row) {
      final f = row.typedAssoc();
      return MovimientoCapitalPlanificado(
        periodoDesde: f['periodo_aplicacion'] as int,
        esInyeccion: f['tipo'] == 'Inyeccion',
        monto: _toDouble(f['monto']),
      );
    }).toList();

    final recalculado = LoanCalculator.recalcularDesde(
      capitaliza: datos['tipo_calculo'] == 'Compuesto',
      saldoInicial: nuevoSaldoEnAncla,
      tasaInicial: _toDouble(datos['tasa_interes_mensual']),
      nuevaTasa: datos['nueva_tasa_interes'] != null ? _toDouble(datos['nueva_tasa_interes']) : null,
      mesCambioTasa: datos['mes_cambio_tasa'] as int?,
      mesCambioCapitalizacion: datos['mes_cambio_capitalizacion'] as int?,
      numeroCuotas: datos['numero_cuotas'] as int,
      frecuenciaPago: datos['frecuencia_pago'] as String,
      fechaInicio: datos['fecha_inicio'] as DateTime,
      periodoInicial: periodoDesde,
      movimientosFuturos: movimientosFuturos,
    );

    for (final cuota in recalculado) {
      await DatabaseService.instance.query(
        'UPDATE cuotas SET saldo_inicio_periodo = :saldoInicio, tasa_aplicada = :tasa, '
        'monto_interes_generado = :interes, interes_capitalizado = :capitalizado, saldo_fin_periodo = :saldoFin '
        'WHERE prestamo_id = :prestamoId AND numero_periodo = :periodo',
        {
          'saldoInicio': cuota['saldo_inicio_periodo'],
          'tasa': cuota['tasa_aplicada'],
          'interes': cuota['monto_interes_generado'],
          'capitalizado': cuota['interes_capitalizado'],
          'saldoFin': cuota['saldo_fin_periodo'],
          'prestamoId': prestamoId,
          'periodo': cuota['numero_periodo'],
        },
      );
    }

    final saldoActualInfo = await fetchSaldoActual(prestamoId);
    final balanceActualizado = saldoActualInfo['saldoActual'] as double;

    await DatabaseService.instance.query(
      'UPDATE prestamos SET balance_actual = :saldo WHERE prestamo_id = :id',
      {'saldo': balanceActualizado, 'id': prestamoId},
    );

    final descripcion = (descripcionConcepto == null || descripcionConcepto.trim().isEmpty)
        ? 'Inyección de capital registrada el ${_formatDate(fechaTransaccion)}, a partir de la cuota $periodoDesde.'
        : 'Inyección de capital registrada el ${_formatDate(fechaTransaccion)}, a partir de la cuota $periodoDesde. '
            'Motivo: ${descripcionConcepto.trim()}';

    await DatabaseService.instance.query(
      'INSERT INTO transacciones_capital '
      "(prestamo_id, fecha_transaccion, tipo, periodo_aplicacion, monto, descripcion) "
      "VALUES (:prestamoId, :fecha, 'Inyeccion', :periodo, :monto, :descripcion)",
      {
        'prestamoId': prestamoId,
        'fecha': _formatDate(fechaTransaccion),
        'periodo': periodoDesde,
        'monto': monto,
        'descripcion': descripcion,
      },
    );

    await _auditoria.log(
      usuarioResponsable: usuarioResponsable,
      tablaAfectada: 'prestamos',
      registroId: codigoReferencia,
      accion: 'UPDATE',
      datosAnteriores: {'balance_actual': balanceAnterior},
      datosNuevos: {
        'evento': 'inyeccion de capital',
        'monto_inyectado': monto,
        'periodo_desde': periodoDesde,
        'balance_actual': balanceActualizado,
      },
    );

    return balanceActualizado;
  }
}
