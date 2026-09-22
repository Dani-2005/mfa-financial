import 'database_service.dart';

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
        'fecha_vencimiento': fechaVencimiento,
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
