import 'database_service.dart';
import 'dashboard_service.dart';

/// Arma los datos agregados para la pestaña de "Gráficas" de Auditoría.
/// Reutiliza donde puede la misma lógica ya usada en otras pantallas
/// (capital nuevo por mes del Dashboard, umbrales de vencimiento) para que
/// los números coincidan entre pantallas.
class GraficasService {
  final DashboardService _dashboardService = DashboardService();

  static const _mesesAbrev = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  /// Capital nuevo colocado en cada uno de los últimos 6 meses (mismo dato
  /// que la mini-gráfica del Dashboard), con las etiquetas de mes ya
  /// resueltas para el eje X.
  Future<Map<String, dynamic>> fetchCapitalNuevoPorMes() async {
    final resumen = await _dashboardService.fetchCapitalSummary();
    final valores = (resumen['serie_mensual'] as List).cast<double>();
    final ahora = DateTime.now();
    final etiquetas = List.generate(valores.length, (i) {
      final offset = valores.length - 1 - i;
      final mes = DateTime(ahora.year, ahora.month - offset, 1);
      return _mesesAbrev[mes.month - 1];
    });
    return {'etiquetas': etiquetas, 'valores': valores};
  }

  /// Total cobrado (recibos_pagos) en cada uno de los últimos 6 meses,
  /// separado por tipo de movimiento, para una barra agrupada.
  Future<Map<String, dynamic>> fetchIngresosPorMes() async {
    final result = await DatabaseService.instance.query(
      'SELECT fecha_emision, tipo_movimiento, monto_total_pagado FROM recibos_pagos',
    );

    final ahora = DateTime.now();
    final etiquetas = <String>[];
    final porTipo = {'Cuota_Ordinaria': <double>[], 'Abono_Capital': <double>[], 'Liquidacion_Total': <double>[]};

    for (int i = 5; i >= 0; i--) {
      final mesRef = DateTime(ahora.year, ahora.month - i, 1);
      etiquetas.add(_mesesAbrev[mesRef.month - 1]);
      for (final tipo in porTipo.keys) {
        // Los pagos parciales se contabilizan dentro de "Cuota Ordinaria":
        // desde el punto de vista de esta gráfica son el mismo tipo de
        // ingreso (pago de cuota), solo que fraccionado en varios recibos.
        final tiposEquivalentes = tipo == 'Cuota_Ordinaria' ? ['Cuota_Ordinaria', 'Pago_Parcial'] : [tipo];
        final total = result.rows
            .map((r) => r.typedAssoc())
            .where((f) {
              final fecha = f['fecha_emision'] as DateTime;
              return tiposEquivalentes.contains(f['tipo_movimiento']) &&
                  fecha.year == mesRef.year &&
                  fecha.month == mesRef.month;
            })
            .fold<double>(0, (sum, f) => sum + _toDouble(f['monto_total_pagado']));
        porTipo[tipo]!.add(total);
      }
    }

    return {
      'etiquetas': etiquetas,
      'cuotaOrdinaria': porTipo['Cuota_Ordinaria'],
      'abonoCapital': porTipo['Abono_Capital'],
      'liquidacionTotal': porTipo['Liquidacion_Total'],
    };
  }

  /// Cuántos préstamos activos hay en cada estado de salud (mismas
  /// categorías que ya usan las pestañas de la pantalla de Préstamos: Al
  /// día, Pendiente, En Mora; más los ya Pagados).
  Future<Map<String, int>> fetchDistribucionEstados() async {
    final result = await DatabaseService.instance.query(
      'SELECT p.activo, p.estado, v.salud_pago '
      'FROM prestamos p '
      'LEFT JOIN vista_salud_prestamos v ON v.prestamo_id = p.prestamo_id',
    );

    final conteo = {'AL DÍA': 0, 'PENDIENTE': 0, 'EN MORA': 0, 'PAGADO': 0};
    for (final row in result.rows) {
      final f = row.typedAssoc();
      final activo = f['activo'] as bool;
      final estado = f['estado'] as String;
      final status = (!activo || estado == 'Pagado') ? 'PAGADO' : ((f['salud_pago'] as String?) ?? 'AL DÍA');
      conteo[status] = (conteo[status] ?? 0) + 1;
    }
    return conteo;
  }

  /// Cuotas pendientes de préstamos activos, agrupadas por qué tan cerca
  /// está su fecha de vencimiento: ya vencidas, próximas a vencer (7 días)
  /// o todavía lejos ("al día").
  Future<Map<String, int>> fetchCuotasPorVencimiento() async {
    final result = await DatabaseService.instance.query(
      'SELECT cu.fecha_vencimiento FROM cuotas cu '
      'JOIN prestamos p ON p.prestamo_id = cu.prestamo_id '
      "WHERE cu.estado = 'Pendiente' AND p.activo = TRUE",
    );

    final hoy = DateTime.now();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

    int vencidas = 0, proximas = 0, alDia = 0;
    for (final row in result.rows) {
      final fecha = row.typedAssoc()['fecha_vencimiento'] as DateTime;
      final diff = fecha.difference(hoySinHora).inDays;
      if (diff < 0) {
        vencidas++;
      } else if (diff <= 7) {
        proximas++;
      } else {
        alDia++;
      }
    }
    return {'Vencidas': vencidas, 'Próximas (7 días)': proximas, 'Al día': alDia};
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.parse(value as String);
  }
}
