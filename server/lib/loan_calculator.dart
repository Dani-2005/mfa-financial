/// Un movimiento de capital planificado desde la creación del préstamo
/// (por ejemplo: "voy a inyectar \$500 a partir de la cuota 5").
class MovimientoCapitalPlanificado {
  final int periodoDesde;
  final bool esInyeccion;
  final double monto;

  const MovimientoCapitalPlanificado({
    required this.periodoDesde,
    required this.esInyeccion,
    required this.monto,
  });
}

/// Calcula el cronograma de cuotas de un préstamo.
///
/// El comportamiento se define con dos ejes independientes:
///   - [capitaliza] (mecánica de cálculo): si es `false` ("Simple"), el
///     interés de cada periodo se calcula sobre el saldo vigente y NO se
///     amortiza automáticamente (el saldo solo cambia por los movimientos
///     de capital planificados). Si es `true` ("Compuesto"), el interés
///     generado se suma al saldo cada periodo, así que el siguiente periodo
///     calcula sobre un saldo mayor.
///   - [mesCambioTasa]/[nuevaTasa] (comportamiento de la tasa): si ambos
///     vienen informados ("Variable"), la tasa aplicada cambia a partir de
///     ese periodo; si vienen nulos ("Fija"), la tasa inicial se usa en
///     todo el cronograma.
///
/// [movimientosPlanificados] permite anticipar inyecciones/retiros de
/// capital en periodos futuros: el ajuste se aplica al saldo justo al
/// inicio del periodo indicado, antes de calcular el interés de ese
/// periodo, y se mantiene para todos los periodos siguientes.
///
/// [mesCambioCapitalizacion] habilita una operación "por fases": solo
/// aplica cuando [capitaliza] es `true`. A partir de ese periodo (inclusive)
/// el saldo deja de capitalizarse: se congela en el valor acumulado al
/// cierre de la fase anterior, y el interés generado cada periodo ya no se
/// suma al saldo sino que pasa a ser el pago líquido exigible al cliente
/// (misma mecánica que "Simple", pero sobre el saldo acumulado en fase 1
/// en vez del capital inicial).
class LoanCalculator {
  static List<Map<String, dynamic>> generarCronograma({
    required bool capitaliza,
    required double capitalInicial,
    required double tasaInicial,
    double? nuevaTasa,
    int? mesCambioTasa,
    int? mesCambioCapitalizacion,
    required int numeroCuotas,
    required String frecuenciaPago,
    required DateTime fechaInicio,
    List<MovimientoCapitalPlanificado> movimientosPlanificados = const [],
  }) {
    if (capitalInicial <= 0) {
      throw ArgumentError.value(capitalInicial, 'capitalInicial', 'Debe ser mayor a 0');
    }
    if (tasaInicial < 0) {
      throw ArgumentError.value(tasaInicial, 'tasaInicial', 'No puede ser negativa');
    }
    if (numeroCuotas <= 0) {
      throw ArgumentError.value(numeroCuotas, 'numeroCuotas', 'Debe ser mayor a 0');
    }
    final tieneVariacion = mesCambioTasa != null || nuevaTasa != null;
    if (tieneVariacion) {
      if (mesCambioTasa == null || nuevaTasa == null) {
        throw ArgumentError('Si la tasa es variable, se requieren mesCambioTasa y nuevaTasa juntos');
      }
      if (mesCambioTasa < 1 || mesCambioTasa > numeroCuotas) {
        throw ArgumentError.value(
          mesCambioTasa,
          'mesCambioTasa',
          'Debe estar entre 1 y numeroCuotas ($numeroCuotas)',
        );
      }
      if (nuevaTasa < 0) {
        throw ArgumentError.value(nuevaTasa, 'nuevaTasa', 'No puede ser negativa');
      }
    }

    if (mesCambioCapitalizacion != null) {
      if (!capitaliza) {
        throw ArgumentError('mesCambioCapitalizacion solo aplica cuando capitaliza es true');
      }
      if (mesCambioCapitalizacion < 1 || mesCambioCapitalizacion > numeroCuotas) {
        throw ArgumentError.value(
          mesCambioCapitalizacion,
          'mesCambioCapitalizacion',
          'Debe estar entre 1 y numeroCuotas ($numeroCuotas)',
        );
      }
    }

    final ajustesPorPeriodo = <int, double>{};
    for (final m in movimientosPlanificados) {
      if (m.monto <= 0) {
        throw ArgumentError.value(m.monto, 'monto', 'El monto de un movimiento planificado debe ser mayor a 0');
      }
      if (m.periodoDesde < 1 || m.periodoDesde > numeroCuotas) {
        throw ArgumentError.value(
          m.periodoDesde,
          'periodoDesde',
          'Debe estar entre 1 y numeroCuotas ($numeroCuotas)',
        );
      }
      final delta = m.esInyeccion ? m.monto : -m.monto;
      ajustesPorPeriodo[m.periodoDesde] = (ajustesPorPeriodo[m.periodoDesde] ?? 0) + delta;
    }

    final cuotas = <Map<String, dynamic>>[];
    double saldo = capitalInicial;

    for (int periodo = 1; periodo <= numeroCuotas; periodo++) {
      final ajuste = ajustesPorPeriodo[periodo];
      if (ajuste != null) {
        saldo += ajuste;
        if (saldo < 0) {
          throw ArgumentError(
            'El retiro de capital planificado en la cuota $periodo deja el saldo en negativo '
            '(${saldo.toStringAsFixed(2).replaceFirst('.', ',')}). No puede retirarse más de lo disponible en ese momento.',
          );
        }
      }

      final tasaVigente = (tieneVariacion && periodo >= mesCambioTasa!) ? nuevaTasa! : tasaInicial;
      final capitalizaEstePeriodo =
          capitaliza && !(mesCambioCapitalizacion != null && periodo >= mesCambioCapitalizacion);

      final saldoInicio = saldo;
      final interes = saldoInicio * (tasaVigente / 100);
      final saldoFin = capitalizaEstePeriodo ? saldoInicio + interes : saldoInicio;

      cuotas.add({
        'numero_periodo': periodo,
        'fecha_vencimiento': _sumarPeriodo(fechaInicio, frecuenciaPago, periodo),
        'saldo_inicio_periodo': saldoInicio,
        'tasa_aplicada': tasaVigente,
        'monto_interes_generado': interes,
        'monto_capital_amortizado': 0.0,
        'interes_capitalizado': capitalizaEstePeriodo,
        'saldo_fin_periodo': saldoFin,
      });

      saldo = saldoFin;
    }

    assert(cuotas.length == numeroCuotas, 'El cronograma debe tener exactamente numeroCuotas periodos');

    return cuotas;
  }

  /// Recalcula únicamente los periodos [periodoInicial]..[numeroCuotas] a
  /// partir de un nuevo saldo (por ejemplo, tras un Abono a Capital hecho
  /// "hoy"). Los periodos anteriores a [periodoInicial] no se tocan: quedan
  /// contablemente cerrados con lo que ya se generó.
  ///
  /// Usa exactamente las mismas reglas de tasa/capitalización que
  /// [generarCronograma] (basadas en el número de periodo absoluto), así que
  /// respeta cualquier cambio de tasa o fin de capitalización ya programado
  /// para el préstamo. [movimientosFuturos] son movimientos de capital
  /// planificados que aún no se habían aplicado (periodoDesde >=
  /// [periodoInicial]) y que deben seguir aplicándose sobre el nuevo saldo.
  static List<Map<String, dynamic>> recalcularDesde({
    required bool capitaliza,
    required double saldoInicial,
    required double tasaInicial,
    double? nuevaTasa,
    int? mesCambioTasa,
    int? mesCambioCapitalizacion,
    required int numeroCuotas,
    required String frecuenciaPago,
    required DateTime fechaInicio,
    required int periodoInicial,
    List<MovimientoCapitalPlanificado> movimientosFuturos = const [],
  }) {
    if (periodoInicial < 1 || periodoInicial > numeroCuotas) {
      throw ArgumentError.value(periodoInicial, 'periodoInicial', 'Debe estar entre 1 y numeroCuotas ($numeroCuotas)');
    }

    final tieneVariacion = mesCambioTasa != null || nuevaTasa != null;

    final ajustesPorPeriodo = <int, double>{};
    for (final m in movimientosFuturos) {
      if (m.periodoDesde < periodoInicial || m.periodoDesde > numeroCuotas) continue;
      final delta = m.esInyeccion ? m.monto : -m.monto;
      ajustesPorPeriodo[m.periodoDesde] = (ajustesPorPeriodo[m.periodoDesde] ?? 0) + delta;
    }

    final cuotas = <Map<String, dynamic>>[];
    double saldo = saldoInicial;

    for (int periodo = periodoInicial; periodo <= numeroCuotas; periodo++) {
      final ajuste = ajustesPorPeriodo[periodo];
      if (ajuste != null) {
        saldo += ajuste;
        if (saldo < 0) {
          throw ArgumentError(
            'Un movimiento de capital en la cuota $periodo deja el saldo en negativo (${saldo.toStringAsFixed(2).replaceFirst('.', ',')}).',
          );
        }
      }

      final tasaVigente = (tieneVariacion && periodo >= mesCambioTasa!) ? nuevaTasa! : tasaInicial;
      final capitalizaEstePeriodo =
          capitaliza && !(mesCambioCapitalizacion != null && periodo >= mesCambioCapitalizacion);

      final saldoInicioPeriodo = saldo;
      final interes = saldoInicioPeriodo * (tasaVigente / 100);
      final saldoFin = capitalizaEstePeriodo ? saldoInicioPeriodo + interes : saldoInicioPeriodo;

      cuotas.add({
        'numero_periodo': periodo,
        'fecha_vencimiento': _sumarPeriodo(fechaInicio, frecuenciaPago, periodo),
        'saldo_inicio_periodo': saldoInicioPeriodo,
        'tasa_aplicada': tasaVigente,
        'monto_interes_generado': interes,
        'monto_capital_amortizado': 0.0,
        'interes_capitalizado': capitalizaEstePeriodo,
        'saldo_fin_periodo': saldoFin,
      });

      saldo = saldoFin;
    }

    return cuotas;
  }

  /// Fecha de vencimiento del periodo [n] (1-indexado) según [frecuencia],
  /// contada desde [inicio]. Se expone para poder fechar los movimientos
  /// de capital planificados de forma consistente con el cronograma.
  static DateTime fechaDePeriodo(DateTime inicio, String frecuencia, int n) {
    return _sumarPeriodo(inicio, frecuencia, n);
  }

  static DateTime _sumarPeriodo(DateTime inicio, String frecuencia, int n) {
    switch (frecuencia) {
      case 'Diario':
        return inicio.add(Duration(days: n));
      case 'Semanal':
        return inicio.add(Duration(days: 7 * n));
      case 'Quincenal':
        return inicio.add(Duration(days: 15 * n));
      case 'Anual':
        return DateTime(inicio.year + n, inicio.month, inicio.day);
      case 'Mensual':
      default:
        final totalMonths = inicio.month - 1 + n;
        final year = inicio.year + totalMonths ~/ 12;
        final month = totalMonths % 12 + 1;
        final ultimoDiaDelMes = DateTime(year, month + 1, 0).day;
        final day = inicio.day > ultimoDiaDelMes ? ultimoDiaDelMes : inicio.day;
        return DateTime(year, month, day);
    }
  }
}
