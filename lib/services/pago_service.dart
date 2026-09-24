import 'api_client.dart';
import 'auth_service.dart';

/// Igual que antes en su interfaz pública, pero por dentro ya no habla
/// directo con MySQL: llama al servidor MAF API en el VPS.
class PagoService {
  Future<Map<String, String>> _headers() async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');
    return headers;
  }

  Never _throwError(ApiResponse response, String mensajeGenerico) {
    final err = response.data['error'] as String?;
    if (err != null) throw ArgumentError(err);
    throw StateError(mensajeGenerico);
  }

  /// Trae los recibos de pago con los datos formateados para las tarjetas
  /// de la pantalla de Historial de Pagos.
  Future<List<Map<String, dynamic>>> fetchAll() async {
    final response = await ApiClient.instance.get('/api/pagos/', headers: await _headers());
    if (!response.ok) throw StateError('No se pudieron cargar los pagos.');
    return (response.data['pagos'] as List).cast<Map<String, dynamic>>();
  }

  /// Trae todos los datos de un recibo puntual, ya armados como los
  /// necesita el PDF.
  Future<Map<String, dynamic>> fetchReciboDetalle(String codigoRecibo) async {
    final response = await ApiClient.instance.get('/api/pagos/recibo/$codigoRecibo', headers: await _headers());
    if (!response.ok) _throwError(response, 'No se pudo cargar el recibo.');
    return response.data;
  }

  /// Registra el pago COMPLETO de una cuota (tipo 'Cuota Ordinaria').
  Future<void> registrarPago({
    required int cuotaId,
    required double monto,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/pagos/cuota/$cuotaId/pago',
      headers: await _headers(),
      body: {
        'monto': monto,
        'descripcionConcepto': descripcionConcepto,
        'metodoPago': metodoPago,
        'referencia': referencia,
        'fechaEmision': fechaEmision.toIso8601String(),
      },
    );
    if (!response.ok) _throwError(response, 'No se pudo registrar el pago.');
  }

  /// Registra un pago PARCIAL de una cuota (tipo 'Pago Parcial').
  Future<void> registrarPagoParcial({
    required int cuotaId,
    required double monto,
    required String descripcionConcepto,
    String? metodoPago,
    String? referencia,
    required DateTime fechaEmision,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/pagos/cuota/$cuotaId/pago-parcial',
      headers: await _headers(),
      body: {
        'monto': monto,
        'descripcionConcepto': descripcionConcepto,
        'metodoPago': metodoPago,
        'referencia': referencia,
        'fechaEmision': fechaEmision.toIso8601String(),
      },
    );
    if (!response.ok) _throwError(response, 'No se pudo registrar el pago parcial.');
  }
}
