import 'api_client.dart';
import 'auth_service.dart';

/// Igual que antes en su interfaz pública, pero por dentro ya no habla
/// directo con MySQL: llama al servidor MAF API en el VPS.
class ReporteService {
  Future<List<Map<String, dynamic>>> fetchDatos({
    required String modulo,
    int? clienteId,
    String? tipoAccion,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');

    final query = {
      'modulo': modulo,
      if (clienteId != null) 'clienteId': '$clienteId',
      if (tipoAccion != null) 'tipoAccion': tipoAccion,
      if (fechaDesde != null) 'fechaDesde': fechaDesde.toIso8601String(),
      if (fechaHasta != null) 'fechaHasta': fechaHasta.toIso8601String(),
    };
    final path = '/api/reportes/?${Uri(queryParameters: query).query}';

    final response = await ApiClient.instance.get(path, headers: headers);
    if (!response.ok) throw StateError('No se pudieron cargar los datos del reporte.');
    return (response.data['filas'] as List).cast<Map<String, dynamic>>();
  }
}
