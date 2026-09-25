import 'database_service.dart';

/// Igual que el `DashboardService` de la app, sin cambios en la lógica: no
/// escribe nada (solo lecturas agregadas), así que no necesita un
/// `usuarioResponsable` explícito como los servicios que sí auditan.
class DashboardService {
  /// Trae el capital total prestado actual (acumulado de préstamos activos)
  /// con su variación porcentual contra el cierre del mes anterior, y por
  /// separado una serie de "capital nuevo colocado" mes a mes (últimos 6
  /// meses) para graficar la tendencia real de negocio nuevo.
  ///
  /// La serie mensual se calcula por fecha de inicio, incluyendo préstamos
  /// ya finalizados/anulados de vuelta: así una liquidación no reescribe el
  /// historial (a diferencia del total acumulado, que sí solo mira
  /// préstamos activos hoy).
  Future<Map<String, dynamic>> fetchCapitalSummary() async {
    final result = await DatabaseService.instance.query(
      'SELECT capital_inicial, fecha_inicio, activo, estado FROM prestamos',
    );

    final loans = result.rows.map((row) {
      final fields = row.typedAssoc();
      return {
        'capital': double.parse(fields['capital_inicial'].toString()),
        'fecha_inicio': fields['fecha_inicio'] as DateTime,
        'activo': fields['activo'] as bool,
        'estado': fields['estado'] as String,
      };
    }).toList();

    final loansActivos = loans.where((l) => l['activo'] as bool).toList();

    double totalHasta(DateTime limite) {
      return loansActivos.where((l) => !(l['fecha_inicio'] as DateTime).isAfter(limite)).fold<double>(
            0,
            (sum, l) => sum + (l['capital'] as double),
          );
    }

    final now = DateTime.now();
    final totalActual = totalHasta(now);

    final finMesPasado = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
    final totalMesPasado = totalHasta(finMesPasado);

    double? porcentajeCambio;
    if (totalMesPasado > 0) {
      porcentajeCambio = ((totalActual - totalMesPasado) / totalMesPasado) * 100;
    }

    // Capital nuevo colocado en cada uno de los últimos 6 meses (no
    // acumulado): cuenta todo préstamo cuya fecha de inicio cae en ese mes,
    // sin importar si sigue activo hoy. Se excluyen los anulados porque ese
    // capital nunca llegó a colocarse de verdad.
    final loansValidos = loans.where((l) => l['estado'] != 'Anulado').toList();
    final serieCapitalNuevo = <double>[];
    for (int i = 5; i >= 0; i--) {
      final mesRef = DateTime(now.year, now.month - i, 1);
      final totalDelMes = loansValidos.where((l) {
        final fecha = l['fecha_inicio'] as DateTime;
        return fecha.year == mesRef.year && fecha.month == mesRef.month;
      }).fold<double>(0, (sum, l) => sum + (l['capital'] as double));
      serieCapitalNuevo.add(totalDelMes);
    }

    bool? capitalNuevoCreciendo;
    if (serieCapitalNuevo.length >= 2) {
      capitalNuevoCreciendo = serieCapitalNuevo.last >= serieCapitalNuevo[serieCapitalNuevo.length - 2];
    }

    return {
      'total_actual': totalActual,
      'total_mes_pasado': totalMesPasado,
      'porcentaje_cambio': porcentajeCambio,
      'serie_mensual': serieCapitalNuevo,
      'capital_nuevo_creciendo': capitalNuevoCreciendo,
    };
  }

  /// Capital nuevo colocado en cada uno de los 12 meses de [anio] (misma
  /// definición que la serie mensual de [fetchCapitalSummary], pero para el
  /// año completo en vez de solo los últimos 6 meses corridos), junto con
  /// la lista de años que sí tienen algún préstamo — para el selector de
  /// año de la pantalla de detalle del dashboard.
  Future<Map<String, dynamic>> fetchCapitalPorAnio(int anio) async {
    final result = await DatabaseService.instance.query(
      "SELECT capital_inicial, fecha_inicio FROM prestamos WHERE estado <> 'Anulado'",
    );

    final loans = result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'capital': double.parse(f['capital_inicial'].toString()),
        'fecha_inicio': f['fecha_inicio'] as DateTime,
      };
    }).toList();

    final meses = List<double>.filled(12, 0);
    for (final l in loans) {
      final fecha = l['fecha_inicio'] as DateTime;
      if (fecha.year == anio) {
        meses[fecha.month - 1] += l['capital'] as double;
      }
    }

    final aniosDisponibles = loans.map((l) => (l['fecha_inicio'] as DateTime).year).toSet().toList()..sort();
    if (aniosDisponibles.isEmpty) aniosDisponibles.add(DateTime.now().year);

    return {'meses': meses, 'anios_disponibles': aniosDisponibles};
  }

  /// Trae el total de intereses cobrados (acumulado hasta hoy) con su
  /// variación porcentual contra el cierre del mes anterior, y por separado
  /// una serie de "intereses cobrados por mes" (últimos 6 meses) para
  /// graficar la tendencia, igual que [fetchCapitalSummary] pero sobre
  /// ingresos por intereses en vez de capital colocado.
  ///
  /// Solo cuentan los recibos de tipo 'Cuota_Ordinaria' y 'Pago_Parcial':
  /// son los únicos que cobran interés puro (ver la nota en
  /// `PagoService.registrarPago` del servidor — una cuota ordinaria no
  /// amortiza capital, así que todo lo que paga es interés). 'Abono_Capital'
  /// y 'Liquidacion_Total' mueven o cierran el capital del préstamo, no son
  /// ingreso por interés, así que se excluyen a propósito.
  Future<Map<String, dynamic>> fetchInteresesSummary() async {
    final result = await DatabaseService.instance.query(
      "SELECT monto_total_pagado, fecha_emision FROM recibos_pagos "
      "WHERE tipo_movimiento IN ('Cuota_Ordinaria', 'Pago_Parcial') AND activo = TRUE",
    );

    final pagos = result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'monto': double.parse(f['monto_total_pagado'].toString()),
        'fecha': f['fecha_emision'] as DateTime,
      };
    }).toList();

    double totalHasta(DateTime limite) {
      return pagos.where((p) => !(p['fecha'] as DateTime).isAfter(limite)).fold<double>(
            0,
            (sum, p) => sum + (p['monto'] as double),
          );
    }

    final now = DateTime.now();
    final totalActual = totalHasta(now);

    final finMesPasado = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
    final totalMesPasado = totalHasta(finMesPasado);

    double? porcentajeCambio;
    if (totalMesPasado > 0) {
      porcentajeCambio = ((totalActual - totalMesPasado) / totalMesPasado) * 100;
    }

    final serieInteresesMensual = <double>[];
    for (int i = 5; i >= 0; i--) {
      final mesRef = DateTime(now.year, now.month - i, 1);
      final totalDelMes = pagos.where((p) {
        final fecha = p['fecha'] as DateTime;
        return fecha.year == mesRef.year && fecha.month == mesRef.month;
      }).fold<double>(0, (sum, p) => sum + (p['monto'] as double));
      serieInteresesMensual.add(totalDelMes);
    }

    bool? interesesCreciendo;
    if (serieInteresesMensual.length >= 2) {
      interesesCreciendo = serieInteresesMensual.last >= serieInteresesMensual[serieInteresesMensual.length - 2];
    }

    return {
      'total_actual': totalActual,
      'total_mes_pasado': totalMesPasado,
      'porcentaje_cambio': porcentajeCambio,
      'serie_mensual': serieInteresesMensual,
      'intereses_creciendo': interesesCreciendo,
    };
  }

  /// Intereses cobrados en cada uno de los 12 meses de [anio] (misma
  /// definición que la serie mensual de [fetchInteresesSummary], pero para
  /// el año completo), junto con la lista de años que sí tienen algún
  /// recibo — para el selector de año de la pantalla de detalle.
  Future<Map<String, dynamic>> fetchInteresesPorAnio(int anio) async {
    final result = await DatabaseService.instance.query(
      "SELECT monto_total_pagado, fecha_emision FROM recibos_pagos "
      "WHERE tipo_movimiento IN ('Cuota_Ordinaria', 'Pago_Parcial') AND activo = TRUE",
    );

    final pagos = result.rows.map((row) {
      final f = row.typedAssoc();
      return {
        'monto': double.parse(f['monto_total_pagado'].toString()),
        'fecha': f['fecha_emision'] as DateTime,
      };
    }).toList();

    final meses = List<double>.filled(12, 0);
    for (final p in pagos) {
      final fecha = p['fecha'] as DateTime;
      if (fecha.year == anio) {
        meses[fecha.month - 1] += p['monto'] as double;
      }
    }

    final aniosDisponibles = pagos.map((p) => (p['fecha'] as DateTime).year).toSet().toList()..sort();
    if (aniosDisponibles.isEmpty) aniosDisponibles.add(DateTime.now().year);

    return {'meses': meses, 'anios_disponibles': aniosDisponibles};
  }

  /// Préstamos que siguen en curso: no desactivados y sin cerrar (ni pagados
  /// ni anulados). Misma definición de "activo" usada en ClienteService.
  Future<int> fetchPrestamosActivosCount() async {
    final result = await DatabaseService.instance.query(
      "SELECT COUNT(*) AS n FROM prestamos WHERE activo = TRUE AND estado NOT IN ('Pagado', 'Anulado')",
    );
    return result.rows.first.typedAssoc()['n'] as int;
  }

  /// Próximas cuotas por cobrar (estado='Pendiente') de préstamos activos,
  /// ordenadas por fecha de vencimiento. Devuelve el total real de cuotas
  /// pendientes y solo las [limite] más próximas ya formateadas para las
  /// tarjetas de alerta del dashboard, con los IDs necesarios para poder
  /// llevar directo al formulario de "Registrar Pago" con todo pre-llenado.
  Future<Map<String, dynamic>> fetchProximasCuotas({int limite = 5}) async {
    final result = await DatabaseService.instance.query(
      'SELECT cu.cuota_id, cu.fecha_vencimiento, cu.monto_interes_generado, cu.monto_capital_amortizado, '
      'p.prestamo_id, p.cliente_id, p.codigo_referencia, c.nombre_cliente '
      'FROM cuotas cu '
      'JOIN prestamos p ON p.prestamo_id = cu.prestamo_id '
      'JOIN clientes c ON c.cliente_id = p.cliente_id '
      "WHERE cu.estado = 'Pendiente' AND p.activo = TRUE "
      'ORDER BY cu.fecha_vencimiento ASC',
    );

    final hoy = DateTime.now();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

    final todas = result.rows.map((row) {
      final f = row.typedAssoc();
      final fechaVencimiento = f['fecha_vencimiento'] as DateTime;
      final monto = double.parse(f['monto_interes_generado'].toString()) +
          double.parse(f['monto_capital_amortizado'].toString());
      final diasDiferencia = fechaVencimiento.difference(hoySinHora).inDays;

      return {
        'cuota_id': f['cuota_id'],
        'prestamo_id': f['prestamo_id'],
        'cliente_id': f['cliente_id'],
        'nombre_cliente': f['nombre_cliente'],
        'codigo_referencia': f['codigo_referencia'],
        'monto': monto,
        'fecha_vencimiento': fechaVencimiento.toIso8601String(),
        'fecha_vencimiento_display': _formatFecha(fechaVencimiento),
        'is_urgent': diasDiferencia <= 3,
        'is_vencida': diasDiferencia < 0,
      };
    }).toList();

    return {
      'total_pendientes': todas.length,
      'proximas': todas.take(limite).toList(),
    };
  }

  String _formatFecha(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year}';
  }
}
