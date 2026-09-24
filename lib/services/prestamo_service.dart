import 'api_client.dart';
import 'auth_service.dart';
import 'loan_calculator.dart';

/// Se lanza cuando el servidor rechaza el alta de un préstamo porque ya
/// existe otro con el mismo código de referencia (colisión muy poco
/// probable del contador secuencial, pero posible con creaciones
/// concurrentes).
class PrestamoCodigoDuplicadoException implements Exception {}

/// Igual que antes en su interfaz pública, pero por dentro ya no habla
/// directo con MySQL: llama al servidor MAF API en el VPS. Toda la lógica
/// de negocio (cronogramas, recálculos, validaciones) ahora vive del lado
/// del servidor; ver `server/lib/prestamo_service.dart`.
class PrestamoService {
  Future<Map<String, String>> _headers() async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');
    return headers;
  }

  /// Convierte una respuesta de error del servidor en la misma excepción
  /// que lanzaba el código anterior (que hablaba directo con MySQL), para
  /// que las pantallas que ya atrapan `ArgumentError` no necesiten cambios.
  Never _throwError(ApiResponse response, String mensajeGenerico) {
    final err = response.data['error'] as String?;
    if (err != null) throw ArgumentError(err);
    throw StateError(mensajeGenerico);
  }

  Future<List<Map<String, dynamic>>> fetchActivosPorCliente(int clienteId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/cliente/$clienteId/activos',
      headers: await _headers(),
    );
    if (!response.ok) throw StateError('No se pudieron cargar los préstamos del cliente.');
    return (response.data['prestamos'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchCuotasPendientes(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/cuotas-pendientes',
      headers: await _headers(),
    );
    if (!response.ok) throw StateError('No se pudieron cargar las cuotas pendientes.');
    return (response.data['cuotas'] as List).cast<Map<String, dynamic>>();
  }

  /// Datos completos de un préstamo (cambio de tasa programado, operación
  /// por fases, cliente, frecuencia, etc.) — usado para el encabezado del
  /// PDF del plan de pagos.
  Future<Map<String, dynamic>> fetchDetalle(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/detalle',
      headers: await _headers(),
    );
    if (!response.ok) _throwError(response, 'No se pudo cargar el detalle del préstamo.');
    return response.data;
  }

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final response = await ApiClient.instance.get('/api/prestamos/', headers: await _headers());
    if (!response.ok) throw StateError('No se pudieron cargar los préstamos.');
    return (response.data['prestamos'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchCuotas(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/cuotas',
      headers: await _headers(),
    );
    if (!response.ok) throw StateError('No se pudo cargar el plan de pagos.');
    return (response.data['cuotas'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchMovimientosCapital(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/movimientos-capital',
      headers: await _headers(),
    );
    if (!response.ok) throw StateError('No se pudieron cargar los movimientos de capital.');
    return (response.data['movimientos'] as List).cast<Map<String, dynamic>>();
  }

  Future<String> generateNextCodigo() async {
    final response = await ApiClient.instance.get('/api/prestamos/next-codigo', headers: await _headers());
    if (!response.ok) throw StateError('No se pudo generar el código de referencia.');
    return response.data['codigo'] as String;
  }

  /// [tipoTasa] es 'Fija' o 'Variable'. [tipoCalculo] es 'Simple' o 'Compuesto'.
  /// Cuando [tipoTasa] es 'Variable', [mesCambioTasa] y [nuevaTasaInteres] son
  /// obligatorios; cuando es 'Fija', ambos deben venir null.
  Future<void> create({
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
    final response = await ApiClient.instance.post(
      '/api/prestamos/',
      headers: await _headers(),
      body: {
        'codigoReferencia': codigoReferencia,
        'clienteId': clienteId,
        'tipoTasa': tipoTasa,
        'tipoCalculo': tipoCalculo,
        'capitalInicial': capitalInicial,
        'tasaInteresMensual': tasaInteresMensual,
        'mesCambioTasa': mesCambioTasa,
        'nuevaTasaInteres': nuevaTasaInteres,
        'mesCambioCapitalizacion': mesCambioCapitalizacion,
        'frecuenciaPago': frecuenciaPago,
        'fechaInicio': fechaInicio.toIso8601String(),
        'numeroCuotas': numeroCuotas,
        'movimientosPlanificados': movimientosPlanificados
            .map((m) => {
                  'periodoDesde': m.periodoDesde,
                  'esInyeccion': m.esInyeccion,
                  'monto': m.monto,
                })
            .toList(),
      },
    );
    if (!response.ok) {
      if (response.statusCode == 409 && response.data['error'] == 'duplicate_codigo') {
        throw PrestamoCodigoDuplicadoException();
      }
      _throwError(response, 'No se pudo registrar el préstamo.');
    }
  }

  Future<Map<String, dynamic>> fetchSaldoActual(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/saldo-actual',
      headers: await _headers(),
    );
    if (!response.ok) _throwError(response, 'No se pudo cargar el saldo actual.');
    return response.data;
  }

  Future<Map<String, dynamic>> fetchAnclaAbono(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/ancla-abono',
      headers: await _headers(),
    );
    if (!response.ok) _throwError(response, 'No se pudo calcular el punto de anclaje del abono.');
    return response.data;
  }

  Future<String> registrarAbonoCapital({
    required int prestamoId,
    required double monto,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/prestamos/$prestamoId/abono-capital',
      headers: await _headers(),
      body: {
        'monto': monto,
        'descripcionConcepto': descripcionConcepto,
        'metodoPago': metodoPago,
        'referencia': referencia,
        'fechaEmision': fechaEmision.toIso8601String(),
      },
    );
    if (!response.ok) _throwError(response, 'No se pudo registrar el abono a capital.');
    return response.data['codigoRecibo'] as String;
  }

  Future<String> registrarLiquidacionTotal({
    required int prestamoId,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/prestamos/$prestamoId/liquidacion-total',
      headers: await _headers(),
      body: {
        'descripcionConcepto': descripcionConcepto,
        'metodoPago': metodoPago,
        'referencia': referencia,
        'fechaEmision': fechaEmision.toIso8601String(),
      },
    );
    if (!response.ok) _throwError(response, 'No se pudo registrar la liquidación total.');
    return response.data['codigoRecibo'] as String;
  }

  Future<List<Map<String, dynamic>>> fetchCuotasElegiblesParaInyeccion(int prestamoId) async {
    final response = await ApiClient.instance.get(
      '/api/prestamos/$prestamoId/cuotas-elegibles-inyeccion',
      headers: await _headers(),
    );
    if (!response.ok) throw StateError('No se pudieron cargar las cuotas elegibles.');
    return (response.data['elegibles'] as List).cast<Map<String, dynamic>>();
  }

  Future<double> registrarInyeccionCapital({
    required int prestamoId,
    required int periodoDesde,
    required double monto,
    String? descripcionConcepto,
    required DateTime fechaTransaccion,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/prestamos/$prestamoId/inyeccion-capital',
      headers: await _headers(),
      body: {
        'periodoDesde': periodoDesde,
        'monto': monto,
        'descripcionConcepto': descripcionConcepto,
        'fechaTransaccion': fechaTransaccion.toIso8601String(),
      },
    );
    if (!response.ok) _throwError(response, 'No se pudo registrar la inyección de capital.');
    return (response.data['nuevoBalance'] as num).toDouble();
  }
}
